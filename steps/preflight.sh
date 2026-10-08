# shellcheck shell=bash
# Sanity checks, pacman options, the tools the installer itself needs, and the machine questions.

step_preflight() {
    title "Preflight"
    [[ -f /etc/arch-release ]] || die "This is not Arch Linux."
    [[ -d /sys/firmware/efi ]] || die "Booted in legacy BIOS mode: UEFI is required (systemd-boot + Secure Boot)."
    [[ $(findmnt -no FSTYPE /boot) == vfat ]] || die "/boot must be the EFI system partition (vfat). With archinstall, choose systemd-boot / ESP mounted at /boot."
    curl -fsS --max-time 10 -o /dev/null https://archlinux.org || die "No internet. Connect with: nmtui (or iwctl on the live USB)."

    # pacman: colors, parallel downloads, multilib (Steam, 32-bit Vulkan)
    sudo sed -i -e 's/^#Color/Color/' -e 's/^#\?ParallelDownloads.*/ParallelDownloads = 5/' /etc/pacman.conf
    if ! grep -q '^\[multilib\]' /etc/pacman.conf; then
        sudo sed -i '/^#\[multilib\]/,/^#Include/ s/^#//' /etc/pacman.conf
        ok "multilib enabled"
    fi
    sudo pacman -Syu --needed --noconfirm gum git base-devel curl pciutils usbutils >>"$LOG" 2>&1 || die "pacman failed, see $LOG"
    ok "pacman ready ($(pacman -Q pacman | cut -d' ' -f2))"

    ask_questions
}

ask_questions() {
    title "About this machine"
    local gpus; gpus=$(gpu_vendors | tr '\n' ' ')
    gum style --faint "CPU: $(cpu_vendor) ($(isa_level))   GPU: ${gpus:-none}   $(is_laptop && echo Laptop || echo Desktop)$(is_vm && echo "   VM: $(virt_kind)")"

    # Dual boot: pre-select what is already there
    local win_entry; win_entry=$(windows_boot_entry)
    local win_disks; win_disks=$(windows_partitions | awk '{print $2}' | sort -u | tr '\n' ' ')
    [[ -n $win_entry || -n $win_disks ]] && gum style --foreground 212 "Windows detected: ${win_entry:+UEFI entry Boot$win_entry }${win_disks:+on $win_disks}"
    local dual
    dual=$(ask_choice DUALBOOT "Dual boot with Windows?" \
        "none|No, Linux only" \
        "other-disk|Yes, Windows is (or will be) on another SSD" \
        "same-disk|Yes, Windows is (or will be) on this SSD, in its own partition")
    if [[ $dual == same-disk ]] && [[ ! $win_disks == *"$(boot_disk)"* ]]; then
        local free; free=$(sudo sfdisk --list-free "$(boot_disk)" 2>/dev/null | awk '$1 ~ /^[0-9]+$/ {print $NF}' | paste -sd' ')
        warn "No Windows partition on $(boot_disk) yet: Windows will need unallocated space on this SSD."
        warn "Unallocated now: ${free:-none}. live-install.sh reserves it when you pick \"same SSD\";"
        warn "otherwise shrink the Linux partition from the live USB first."
    fi

    ask_multi OPTIONAL "Optional groups (all were installed on the original machine)" \
        "gaming|Steam and 32-bit graphics" \
        "llm|Local LLM: llama.cpp Vulkan server + Qwen model download" \
        "vpn|NordVPN app" \
        "legacy|Superseded apps: waybar / hyprpanel / corners SDDM theme / neofetch" >/dev/null
    ok "Answers saved in $CONF (change them with ./install.sh --reconfigure)"
}
