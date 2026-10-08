#!/usr/bin/env bash
# Rclone bidirectional sync (rclone bisync) - newest wins on conflicts
# Linux twin of rclone-backup.ps1 (Windows). R2 is the hub between both OSes.
# Edit exclusions in filters-documents.txt / filters-pictures.txt (same folder)
#
# Cost-optimized for Cloudflare R2:
#   --fast-list             -> one recursive LIST per 1000 objects instead of one LIST per folder (Class A)
#   --compare size,checksum -> uses the MD5 already returned by the listing, so no per-file HEAD (Class B)
#   bisync                  -> one pass per folder instead of a pull + push that each re-scanned everything
# Conflicts (same file edited on both sides between two runs) are resolved locally afterwards:
# bisync keeps both copies (.conflict1 = local, .conflict2 = R2), we keep the newer one
# under the original name and bisync again to push the result.
#
# Runs every 5 min via systemd user timer: rclone-sync.timer -> rclone-sync.service

set -u
RCLONE="${RCLONE:-rclone}"
DIR="$(cd "$(dirname "$0")" && pwd)"
LOG="$DIR/rclone-backup.log"
STATE="$DIR/bisync-state"

# One instance at a time; lowest CPU/IO priority so the desktop never stutters
exec 9>"$DIR/.rclone-backup.lock"
flock -n 9 || exit 0
renice -n 19 -p $$ >/dev/null 2>&1
ionice -c 3 -p $$ >/dev/null 2>&1

run_bisync() {  # local remote filters [extra args...]
    local local_dir=$1 remote=$2 filters=$3
    shift 3
    [ $# -eq 0 ] && set -- --compare size,checksum
    "$RCLONE" bisync "$local_dir" "$remote" \
        --fast-list --skip-links --resilient --recover --max-lock 30m \
        --filter-from "$DIR/$filters" --workdir "$STATE" \
        --log-file "$LOG" --log-level INFO "$@"
}

# Keep the newer of each X.conflict1 (local) / X.conflict2 (R2) pair as X, delete the other.
# The local download of .conflict2 gets the download time as mtime, so its real mtime is
# read from R2 with one targeted request per conflicting file.
RESOLVED=0
resolve_conflicts() {  # local remote
    local local_dir=${1%/} remote=$2 c1 c2 base rel rt remote_s local_s winner loser side
    RESOLVED=0
    while IFS= read -r -d '' c1; do
        base=${c1%.conflict1}
        c2=$base.conflict2
        [[ -f $c2 && ! -e $base ]] || continue
        rel=${c2#"$local_dir"/}
        rt=$("$RCLONE" lsjson --stat "$remote/$rel" | grep -o '"ModTime":"[^"]*"' | cut -d'"' -f4)
        remote_s=$(date -d "$rt" +%s 2>/dev/null) || continue
        local_s=$(stat -c %Y "$c1")
        if (( remote_s > local_s )); then
            touch -d "@$remote_s" "$c2"
            winner=$c2 loser=$c1 side=R2
        else
            winner=$c1 loser=$c2 side=local
        fi
        mv -- "$winner" "$base"
        rm -f -- "$loser"
        echo "$(date '+%Y/%m/%d %H:%M:%S') NOTICE: Conflict resolved, kept newer $side copy - $base" >> "$LOG"
        RESOLVED=$((RESOLVED + 1))
    done < <(find "$local_dir" -type f -name '*.conflict1' -print0 2>/dev/null)
}

sync_folder() {  # local remote filters
    local local_dir=$1 remote=$2 filters=$3 before
    before=$(stat -c %s "$LOG" 2>/dev/null || echo 0)
    if ! run_bisync "$local_dir" "$remote" "$filters"; then
        # First run, or the filters file was edited: bisync needs a --resync.
        # Resync never deletes anything; it merges both sides keeping the newer copy.
        # It reads R2 modtimes (one request per file), acceptable since it only happens then.
        if tail -c +$((before + 1)) "$LOG" | grep -qiE 'must run --resync|cannot find prior Path1 or Path2 listings'; then
            run_bisync "$local_dir" "$remote" "$filters" --resync --resync-mode newer --compare size,modtime,checksum
        fi
        return
    fi
    # Push the resolution right away. --force only skips the "too many deletes" safety check,
    # which the removed .conflict copies would trip in small folders.
    resolve_conflicts "$local_dir" "$remote"
    if (( RESOLVED > 0 )); then
        run_bisync "$local_dir" "$remote" "$filters" --compare size,checksum --force
    fi
}

sync_folder "$HOME/Documents" "r2:aplanche-personal/Documents" "filters-documents.txt"
sync_folder "$HOME/Pictures"  "r2:aplanche-personal/Pictures"  "filters-pictures.txt"
