#!/usr/bin/env bash
# Rotate Hyprland wallpapers from ~/Pictures/Wallpapers every 5 minutes (awww).
# Shuffles the folder and shows every image once before reshuffling.
# The folder is re-read on each cycle, so images synced from R2 are picked up.
set -u
DIR="$HOME/Pictures/Wallpapers"
INTERVAL=300

# Only one rotator per session
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/wallpaper-rotate.lock"
flock -n 9 || exit 0

pgrep -x awww-daemon >/dev/null || { awww-daemon 9>&- & }
until awww query >/dev/null 2>&1; do sleep 0.2; done

last=""
while :; do
    mapfile -d '' images < <(find "$DIR" -maxdepth 1 -type f \
        \( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' -o -iname '*.gif' \) \
        -print0 | shuf -z)
    if (( ${#images[@]} == 0 )); then sleep "$INTERVAL" 9>&-; continue; fi
    # Don't show the same image twice in a row across reshuffles
    if (( ${#images[@]} > 1 )) && [[ ${images[0]} == "$last" ]]; then
        images=("${images[@]:1}" "${images[0]}")
    fi
    for img in "${images[@]}"; do
        [[ -f $img ]] || continue
        awww img "$img" --resize crop --transition-type fade --transition-duration 2 9>&-
        last=$img
        sleep "$INTERVAL" 9>&-
    done
done
