# shellcheck shell=bash
# Shared helpers for install.sh, the steps/ scripts and the first-login wizard.

REPO=${REPO:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}
CONF_DIR="$HOME/.config/arch-setup"
CONF="$CONF_DIR/machine.conf"          # answers for this machine (re-used on re-runs)
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/arch-setup"
LOG="$STATE_DIR/install.log"
mkdir -p "$CONF_DIR" "$STATE_DIR"

# ---------- output ----------
has_gum() { command -v gum >/dev/null 2>&1; }
_log() { printf '%s %s\n' "$(date '+%F %T')" "$*" >>"$LOG"; }
info()  { _log "INFO $*";  if has_gum; then gum style --foreground 212 "==> $*"; else printf '\e[1;35m==>\e[0m %s\n' "$*"; fi; }
ok()    { _log "OK $*";    if has_gum; then gum style --foreground 42 "  ✓ $*"; else printf '\e[32m  ✓\e[0m %s\n' "$*"; fi; }
warn()  { _log "WARN $*";  if has_gum; then gum style --foreground 214 "  ! $*"; else printf '\e[33m  !\e[0m %s\n' "$*"; fi; }
die()   { _log "FAIL $*";  printf '\e[31m  ✗ %s\e[0m\n' "$*" >&2; exit 1; }
title() { _log "STEP $*";  if has_gum; then gum style --border rounded --padding "0 2" --margin "1 0 0 0" --border-foreground 212 --bold "$*"; else printf '\n\e[1m### %s\e[0m\n' "$*"; fi; }

# ---------- questions (answers are saved in machine.conf) ----------
conf_get() { [[ -f $CONF ]] && sed -n "s/^$1=//p" "$CONF" | tail -1; }
conf_set() {
    touch "$CONF"
    sed -i "/^$1=/d" "$CONF"
    printf '%s=%s\n' "$1" "$2" >>"$CONF"
}

# ask_choice KEY "Question" "value|Label" ...   -> echoes the chosen value
ask_choice() {
    local key=$1 q=$2; shift 2
    local saved; saved=$(conf_get "$key")
    if [[ -n $saved && -z ${RECONFIGURE:-} ]]; then echo "$saved"; return; fi
    local labels=() opt label value
    for opt in "$@"; do labels+=("${opt#*|}"); done
    if has_gum; then
        label=$(gum choose --header "$q" "${labels[@]}") || die "Cancelled"
    else
        PS3="$q > "; select label in "${labels[@]}"; do [[ -n $label ]] && break; done
    fi
    for opt in "$@"; do [[ ${opt#*|} == "$label" ]] && value=${opt%%|*}; done
    conf_set "$key" "$value"
    echo "$value"
}

# ask_multi KEY "Question" "value|Label" ...   -> space-separated chosen values (all pre-selected)
ask_multi() {
    local key=$1 q=$2; shift 2
    if grep -q "^$key=" "$CONF" 2>/dev/null && [[ -z ${RECONFIGURE:-} ]]; then conf_get "$key"; return; fi
    local labels=() opt chosen=() line
    for opt in "$@"; do labels+=("${opt#*|}"); done
    local IFS=,; local all="${labels[*]}"; unset IFS
    while IFS= read -r line; do
        for opt in "$@"; do [[ ${opt#*|} == "$line" ]] && chosen+=("${opt%%|*}"); done
    done < <(gum choose --no-limit --header "$q (space = toggle, enter = confirm)" --selected="$all" "${labels[@]}")
    conf_set "$key" "${chosen[*]}"
    echo "${chosen[*]}"
}

confirm() { if has_gum; then gum confirm "$1"; else read -rp "$1 [y/N] " r; [[ $r == [yY]* ]]; fi; }
has_opt() { [[ " $(conf_get OPTIONAL) " == *" $1 "* ]]; }

# ---------- packages ----------
# Package names from list files, without comments / blank lines
pkglist() { local f; for f in "$@"; do sed -e 's/#.*//' -e 's/[[:space:]]//g' "$REPO/packages/$f.txt" | grep -v '^$'; done; }

# Install packages: repo ones with pacman in one transaction, the rest (AUR) with paru
pkg_install() {
    (($#)) || return 0
    local repo=() aur=() p
    local available; available=$(pacman -Slq 2>/dev/null)
    for p in "$@"; do
        if grep -qxF "$p" <<<"$available" || pacman -Qq "$p" &>/dev/null; then repo+=("$p"); else aur+=("$p"); fi
    done
    if ((${#repo[@]})); then
        sudo pacman -S --needed --noconfirm "${repo[@]}" 2>&1 | tee -a "$LOG"
        ((PIPESTATUS[0] == 0)) || die "pacman failed, see $LOG"
    fi
    if ((${#aur[@]})); then
        command -v paru >/dev/null || die "paru is missing (needed for: ${aur[*]})"
        paru -S --needed --noconfirm --skipreview "${aur[@]}" 2>&1 | tee -a "$LOG" || warn "Some AUR packages failed: ${aur[*]} (see $LOG)"
    fi
}

# ---------- files ----------
# Copy a file from system/ to / as root, filling @USER@ / @HOME@
install_system_file() {  # <path relative to system/> [dest] [mode]
    local src="$REPO/system/$1" dest=${2:-/$1} mode=${3:-644}
    sed -e "s|@USER@|$USER|g" -e "s|@HOME@|$HOME|g" "$src" | sudo install -Dm"$mode" /dev/stdin "$dest"
}

# /boot (the ESP) is root-only (dmask=0077): test paths there as root
root_test() { sudo test "$@"; }

# Keep sudo alive for the whole run (asked once, in the TTY)
sudo_keepalive() {
    sudo -v || die "sudo is required"
    ( while kill -0 "$$" 2>/dev/null; do sudo -n true; sleep 50; done ) 2>/dev/null &
}
