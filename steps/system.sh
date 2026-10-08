# shellcheck shell=bash
# System files from system/ (copied as root: sudoers, units, keyd, SDDM theme), services,
# snapper, shell, and the user timers (scripts/crons).

step_system() {
    title "System configuration"

    # Everything under system/etc and system/usr, except the optional/ and snapper/ folders
    local f mode
    while IFS= read -r -d '' f; do
        f=${f#"$REPO/system/"}
        case $f in etc/sudoers.d/*) mode=440 ;; *) mode=644 ;; esac
        install_system_file "$f" "/$f" "$mode"
    done < <(find "$REPO/system/etc" "$REPO/system/usr" -type f -print0)
    sudo visudo -cq || die "sudoers syntax error (system/etc/sudoers.d)"
    ok "Copied $(find "$REPO/system/etc" "$REPO/system/usr" -type f | wc -l) files from system/"

    # Login-screen wallpapers: the theme reads ./backgrounds, filled from ~/Pictures/Logging
    sudo install -d -o "$USER" -g "$USER" /usr/share/sddm/themes/liquid-glass/backgrounds
    mkdir -p "$HOME/Pictures/Logging"
    [[ -n $(ls -A /usr/share/sddm/themes/liquid-glass/backgrounds 2>/dev/null) ]] ||
        cp /usr/share/sddm/themes/*/Backgrounds/*.{jpg,png} /usr/share/sddm/themes/liquid-glass/backgrounds/ 2>/dev/null || true

    # Services (same set as the original machine)
    sudo systemctl daemon-reload
    local svc
    for svc in NetworkManager systemd-resolved systemd-timesyncd sddm keyd ananicy-cpp scx sddm-backgrounds.path; do
        sudo systemctl enable "$svc" >>"$LOG" 2>&1 || warn "Could not enable $svc"
    done
    has_opt vpn && { sudo systemctl enable nordvpnd.service nordvpnd.socket >>"$LOG" 2>&1; sudo usermod -aG nordvpn "$USER"; }
    ok "Services enabled"

    setup_snapper
    setup_shell
    setup_user_units
}

setup_snapper() {
    [[ $(root_fstype) == btrfs ]] || { warn "Root is not btrfs: snapper skipped"; return 0; }
    local cfg sub
    for cfg in root home; do
        [[ $cfg == root ]] && sub=/ || sub=/home
        sudo test -f "/etc/snapper/configs/$cfg" || sudo snapper -c "$cfg" create-config "$sub" >>"$LOG" 2>&1 || { warn "snapper create-config $cfg failed"; continue; }
        install_system_file "snapper/$cfg.conf" "/etc/snapper/configs/$cfg" 640
    done
    sudo systemctl enable snapper-timeline.timer snapper-cleanup.timer >>"$LOG" 2>&1
    ok "Snapper: hourly snapshots of / and /home"
}

setup_shell() {
    [[ -d $HOME/.oh-my-zsh ]] || git clone -q --depth 1 https://github.com/ohmyzsh/ohmyzsh.git "$HOME/.oh-my-zsh"
    [[ $(getent passwd "$USER" | cut -d: -f7) == /usr/bin/zsh ]] || sudo chsh -s /usr/bin/zsh "$USER"
    ok "zsh + oh-my-zsh"
}

setup_user_units() {
    # Works from a TTY too: talks to the user manager directly
    systemctl --user daemon-reload
    local t
    for t in system-update ghostty-rotate-bg spotlight-download; do
        systemctl --user enable "$t.timer" >>"$LOG" 2>&1 || warn "Could not enable $t.timer"
    done
    # rclone-sync.timer is enabled by the first-login wizard, once the R2 remote exists
    if rclone listremotes 2>/dev/null | grep -qx 'r2:'; then
        systemctl --user enable rclone-sync.timer >>"$LOG" 2>&1
    fi
    mkdir -p "$HOME/rclone-sync" "$HOME/Documents" "$HOME/Pictures/Wallpapers" "$HOME/Pictures/Terminal"
    ok "User timers: system-update, ghostty-rotate-bg, spotlight-download$(rclone listremotes 2>/dev/null | grep -qx 'r2:' && echo ', rclone-sync')"
}
