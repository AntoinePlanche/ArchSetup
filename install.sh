#!/usr/bin/env bash
# Rebuild this desktop on a fresh Arch install.
#
#   ./install.sh                 run every step (safe to re-run: each step is idempotent)
#   ./install.sh <step>...       run only some steps, e.g. ./install.sh dotfiles system
#   ./install.sh --reconfigure   ask the machine questions again (dual boot, optional groups)
#
# Steps: preflight repos kernel drivers packages dotfiles system dualboot secureboot extras
# Run it as your normal user (not root) from a TTY or a terminal; sudo is asked once.
# Account logins (R2, Google, GitHub, NordVPN...) are not asked here: they happen in the
# graphical first-login wizard (firstlogin/first-login.sh) once Hyprland is up.
set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
export REPO
source "$REPO/lib/common.sh"
source "$REPO/lib/hw.sh"

ALL_STEPS=(preflight repos kernel drivers packages dotfiles system dualboot secureboot extras)

[[ $EUID -ne 0 ]] || die "Run as your normal user, not root (sudo is used where needed)."

steps=()
for a in "$@"; do
    case $a in
        --reconfigure) export RECONFIGURE=1 ;;
        -h|--help) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        *) [[ " ${ALL_STEPS[*]} " == *" $a "* ]] || die "Unknown step: $a"; steps+=("$a") ;;
    esac
done
((${#steps[@]})) || steps=("${ALL_STEPS[@]}")

sudo_keepalive
_log "===== install.sh ${steps[*]} ====="

for s in "${steps[@]}"; do
    # shellcheck source=/dev/null
    source "$REPO/steps/$s.sh"
    "step_$s"
    date '+%F %T' >"$STATE_DIR/step-$s.done"
done

title "Done"
if [[ " ${steps[*]} " == *" extras "* ]]; then
    cat <<EOF
Everything that can be done from here is done. Next:
  1. Reboot. SDDM shows the Liquid Glass login, log in to Hyprland.
  2. The setup wizard opens by itself: Secure Boot keys, R2/pCloud (rclone), GitHub,
     Google, NordVPN, Hyprland plugins... all graphical, with browser logins.
     Secure Boot stays OFF until the wizard's last Secure Boot step (switching it on in the
     firmware): that is expected. The wizard shows which step you are at.
     Re-open it any time with: $REPO/firstlogin/first-login.sh
Log of this run: $LOG
EOF
    if confirm "Reboot now?"; then systemctl reboot; fi
fi
