# shellcheck shell=bash
# CachyOS kernels (+ LTS fallback) as Unified Kernel Images, booted by systemd-boot.
# Same layout as the original machine:
#   /boot/EFI/Linux/arch-linux-cachyos.efi (default) and arch-linux-cachyos-lts.efi
#   /etc/kernel/cmdline holds the kernel command line, embedded into the UKIs.
# Signing for Secure Boot is done by steps/secureboot.sh (sbctl hooks re-sign on every update).

KERNELS=(linux-cachyos linux-cachyos-lts)

step_kernel() {
    title "Kernel: linux-cachyos + linux-cachyos-lts (UKI, systemd-boot)"
    local ucode; case $(cpu_vendor) in amd) ucode=amd-ucode ;; intel) ucode=intel-ucode ;; esac
    local pkgs=(linux-cachyos linux-cachyos-headers linux-cachyos-lts linux-firmware mkinitcpio plymouth "$ucode")
    root_on_lvm && pkgs+=(lvm2)
    [[ -n $(root_luks_dev) ]] && pkgs+=(cryptsetup)

    write_cmdline
    write_mkinitcpio_conf
    # Boot splash: motherboard logo (firmware BGRT) + Arch logo + spinner. Read when the
    # initramfs is built, so it must be in place before mkinitcpio runs below.
    install_system_file etc/plymouth/plymouthd.conf
    local k
    for k in "${KERNELS[@]}"; do write_preset "$k"; done
    # Kernel install triggers mkinitcpio, which now builds the UKIs directly
    pkg_install "${pkgs[@]}"
    # Rebuild in any case: on a re-run the packages are already there but cmdline/hooks may have changed
    for k in "${KERNELS[@]}"; do
        sudo mkinitcpio -p "$k" >>"$LOG" 2>&1 || die "mkinitcpio -p $k failed, see $LOG"
        root_test -f "/boot/EFI/Linux/arch-$k.efi" || die "UKI for $k was not created, see $LOG"
        ok "UKI /boot/EFI/Linux/arch-$k.efi"
    done

    setup_systemd_boot
    remove_stock_kernel
}

write_cmdline() {
    local src fstype subvol luks cmd
    src=$(root_source) fstype=$(root_fstype) subvol=$(root_subvol)
    if root_on_lvm; then
        cmd="root=$src"   # /dev/mapper/VG-LV is stable
    else
        cmd="root=UUID=$(findmnt -no UUID /)"
    fi
    luks=$(root_luks_dev)   # -d below: without it lsblk also prints the UUIDs of what is inside
    [[ -n $luks ]] && cmd="cryptdevice=UUID=$(lsblk -dno UUID "$luks"):$(lsblk -rsno NAME,TYPE "$src" | awk '$2=="crypt"{print $1; exit}') $cmd"
    [[ $fstype == btrfs && -n $subvol ]] && cmd+=" rootflags=subvol=${subvol#/}"
    # Same options as the original machine: zram instead of zswap, quiet boot + Plymouth splash
    cmd+=" rw rootfstype=$fstype zswap.enabled=0 quiet loglevel=3 splash"
    has_nvidia && cmd+=" nvidia_drm.modeset=1 nvidia_drm.fbdev=1"
    echo "$cmd" | sudo install -Dm644 /dev/stdin /etc/kernel/cmdline
    ok "/etc/kernel/cmdline: $cmd"
}

has_nvidia() { gpu_vendors | grep -qx nvidia; }

write_mkinitcpio_conf() {
    # Same hooks as the original machine; lvm2 / encrypt only when the disk layout needs them
    local hooks="base udev plymouth autodetect microcode modconf kms keyboard keymap consolefont"
    [[ -n $(root_luks_dev) ]] && hooks+=" encrypt"
    root_on_lvm && hooks+=" lvm2"
    hooks+=" block filesystems fsck"
    # NVIDIA: no kms hook (it would pull in nouveau); steps/drivers.sh adds the nvidia MODULES
    has_nvidia && hooks=${hooks/ kms/}
    sudo sed -i "s/^HOOKS=(.*)/HOOKS=($hooks)/" /etc/mkinitcpio.conf
    ok "mkinitcpio HOOKS=($hooks)"
}

write_preset() {  # kernel package name
    local k=$1
    sudo install -Dm644 /dev/stdin "/etc/mkinitcpio.d/$k.preset" <<EOF
# mkinitcpio preset file for the '$k' package (written by ArchSetup: UKI only)
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-$k"

PRESETS=('default')

default_uki="/boot/EFI/Linux/arch-$k.efi"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"
EOF
}

setup_systemd_boot() {
    # Replace GRUB / other loaders: UKIs are auto-discovered by systemd-boot, no entry files needed
    if ! sudo bootctl is-installed >/dev/null 2>&1; then
        sudo bootctl install >>"$LOG" 2>&1 || die "bootctl install failed, see $LOG"
    fi
    pacman -Qq grub &>/dev/null && warn "GRUB is installed but no longer used (systemd-boot is first in the boot order). Remove it with: sudo pacman -Rns grub"
    # Hidden menu (hold Space at boot to show it), CachyOS kernel by default
    printf 'timeout 0\ndefault arch-linux-cachyos.efi\n' | sudo install -Dm644 /dev/stdin /boot/loader/loader.conf
    # Keep /boot/EFI/systemd up to date when the systemd package updates
    sudo systemctl enable systemd-boot-update.service >>"$LOG" 2>&1 || true
    ok "systemd-boot: $(bootctl --version | head -1 | awk '{print $2}'), default arch-linux-cachyos.efi"
}

remove_stock_kernel() {
    # archinstall / live-install.sh may have installed Arch's own kernel: drop it once the CachyOS UKIs exist
    local k
    for k in linux linux-lts linux-zen; do
        pacman -Qq "$k" &>/dev/null || continue
        root_test -f /boot/EFI/Linux/arch-linux-cachyos.efi && root_test -f /boot/EFI/Linux/arch-linux-cachyos-lts.efi || return 0
        if confirm "Remove the stock '$k' kernel? (both CachyOS UKIs are built)"; then
            sudo pacman -Rns --noconfirm "$k" "$k-headers" 2>>"$LOG" >>"$LOG" || sudo pacman -Rns --noconfirm "$k" >>"$LOG" 2>&1
            sudo rm -f "/boot/EFI/Linux/arch-$k.efi" "/boot/EFI/Linux/arch-$k-fallback.efi" "/boot/initramfs-$k.img" "/boot/initramfs-$k-fallback.img"
            ok "Removed $k"
        fi
    done
    # Old Type #1 entries (archinstall) would point at removed kernels
    if [[ -n $(sudo find /boot/loader/entries -name '*.conf' 2>/dev/null) ]]; then
        sudo mkdir -p /boot/loader/entries.old
        sudo find /boot/loader/entries -name '*.conf' -exec mv -t /boot/loader/entries.old/ {} +
        ok "Moved old boot entries to /boot/loader/entries.old (UKIs are auto-detected)"
    fi
}
