#!/usr/bin/env bash
set -euo pipefail

LOG_DIR="${HOME}/.local/state"
LOG_FILE="${LOG_DIR}/system-update.log"
STAMP_FILE="${LOG_DIR}/system-update.last-success"
INTERVAL_DAYS=7
mkdir -p "${LOG_DIR}"

notify() {
    command -v notify-send >/dev/null 2>&1 && notify-send -a "System Updater" "$@" || true
}

# Skip if the last successful update is recent enough
if [[ -f "${STAMP_FILE}" ]] && [[ -z "$(find "${STAMP_FILE}" -mtime +$((INTERVAL_DAYS - 1)))" ]]; then
    echo "Last successful update: $(date -r "${STAMP_FILE}"), skipping."
    exit 0
fi

# Wait up to 2 minutes for the network (user units can't depend on network-online.target)
for _ in $(seq 24); do
    curl -fsS --max-time 5 -o /dev/null https://archlinux.org && break
    sleep 5
done

# Log interruptions (shutdown/logout) instead of dying silently
trap 'echo "=== System Update Interrupted: $(date) (will retry next login) ===" >> "${LOG_FILE}"; exit 143' TERM INT

notify -u normal "Weekly Update Started" "Updating official repos and AUR packages..."
echo "=== System Update Started: $(date) ===" >> "${LOG_FILE}"

# Full update: official repos (Arch + CachyOS) and AUR packages
# (covers packages installed with paru too — both use the same pacman database)
if /usr/bin/yay -Syu --noconfirm >> "${LOG_FILE}" 2>&1; then
    # omp (oh-my-pi) is a standalone binary in ~/.local/bin, not a package; non-fatal
    "${HOME}/.local/bin/omp" update >> "${LOG_FILE}" 2>&1 || echo "omp update failed (non-fatal)" >> "${LOG_FILE}"
    # Hyprland plugins (hyprpm) must be rebuilt for each new Hyprland version; non-fatal.
    # Only when Hyprland changed: hyprpm asks for the sudo password (pop-up) to install headers.
    HYPRPM_STAMP="${LOG_DIR}/hyprpm.built-for"
    HYPRLAND_VER=$(pacman -Q hyprland | awk '{print $2}')
    if [[ "$(cat "${HYPRPM_STAMP}" 2>/dev/null)" != "${HYPRLAND_VER}" ]]; then
        echo "--- hyprpm update for Hyprland ${HYPRLAND_VER} ---" >> "${LOG_FILE}"
        if SUDO_ASKPASS="${HOME}/.local/bin/sudo-askpass" hyprpm update < /dev/null >> "${LOG_FILE}" 2>&1; then
            echo "${HYPRLAND_VER}" > "${HYPRPM_STAMP}"
        else
            echo "hyprpm update failed (non-fatal)" >> "${LOG_FILE}"
            notify -u critical "Hyprland plugins not rebuilt" "Run 'hyprpm update' in a terminal, or SUPER+Tab may stop working after re-login."
        fi
    fi
    touch "${STAMP_FILE}"
    echo "=== System Update Succeeded: $(date) ===" >> "${LOG_FILE}"
    notify -u normal "System Update Complete" "All packages are up to date! Log: ~/.local/state/system-update.log"
else
    echo "=== System Update Failed: $(date) (will retry next login) ===" >> "${LOG_FILE}"
    notify -u critical "System Update Failed" "Will retry next login. Check ~/.local/state/system-update.log"
    exit 1
fi
