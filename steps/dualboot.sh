# shellcheck shell=bash
# Windows dual boot. Linux keeps booting by default (systemd-boot, hidden menu); Windows is one
# click away in the quickshell bar ("Restart into Windows" = UEFI BootNext, one boot only).

step_dualboot() {
    title "Dual boot"
    local mode; mode=$(conf_get DUALBOOT)
    if [[ $mode == none ]]; then
        sudo rm -f /etc/sudoers.d/windows-boot
        ok "No dual boot: Windows button hidden, no NTFS tools"
        return 0
    fi

    install_system_file optional/windows-boot.sudoers /etc/sudoers.d/windows-boot 440
    sudo visudo -cq || die "sudoers syntax error (windows-boot)"

    local entry; entry=$(windows_boot_entry)
    if [[ -n $entry ]]; then
        # Windows updates sometimes put themselves first: keep systemd-boot first
        local linux; linux=$(efibootmgr | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Linux Boot Manager.*/\1/p' | head -1)
        if [[ -n $linux ]]; then
            local order; order=$(efibootmgr | sed -n 's/^BootOrder: //p' | tr ',' '\n' | grep -vx "$linux" | paste -sd,)
            sudo efibootmgr -o "$linux${order:+,$order}" >>"$LOG" 2>&1
        fi
        ok "Windows Boot Manager is Boot$entry; Linux stays first. Bar button: Restart into Windows."
    else
        cat <<EOF
  Windows is not installed yet. When you install it:
   - $( [[ $mode == same-disk ]] && echo "pick the unallocated space on $(boot_disk) (never the Linux partitions)" || echo "install it on the other SSD" )
   - Secure Boot can stay on: the Microsoft keys are enrolled next to yours (sbctl -m)
   - afterwards boot Linux from the firmware boot menu and run:  $REPO/install.sh dualboot
     (puts Linux first again; the bar button appears by itself)
EOF
    fi
}
