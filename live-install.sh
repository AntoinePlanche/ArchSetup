#!/usr/bin/env bash
# Stage 0, from the Arch live USB (optional: a plain archinstall with systemd-boot and the ESP
# on /boot works too). It exists because dual boot on the SAME SSD has to be planned at
# partitioning time. Installs a minimal bootable Arch, then install.sh does everything else.
#
#   On the live USB:   iwctl                      (Wi-Fi only: station wlan0 connect <SSID>)
#                      pacman -Sy git
#                      git clone <this repo> && ArchSetup/live-install.sh
#
# Layout (same as the original machine, minus LVM):
#   ESP 1 GiB vfat on /boot (UKIs live there) | btrfs (optionally in LUKS): @ @home @pkg @log
set -euo pipefail

REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)
MNT=/mnt
BTRFS_OPTS="rw,relatime,compress=zstd:3,ssd,discard=async,space_cache=v2"

say()  { printf '\e[1;35m==>\e[0m %s\n' "$*"; }
warn() { printf '\e[33m  ! %s\e[0m\n' "$*"; }
die()  { printf '\e[31m  ✗ %s\e[0m\n' "$*" >&2; exit 1; }
ask()  { local r; read -rp "$1${2:+ [$2]}: " r; echo "${r:-${2:-}}"; }
yes_no() { local r; read -rp "$1 [y/N] " r; [[ $r == [yY]* ]]; }
choose() {  # "Question" option...  -> echoes the chosen option
    local q=$1; shift; local PS3="$q > " o
    select o in "$@"; do [[ -n $o ]] && { echo "$o"; return; }; done
}
password() {  # "Label" -> echoes the password (asked twice)
    local a b
    while true; do
        read -rsp "$1: " a; echo >&2; read -rsp "Again: " b; echo >&2
        [[ -n $a && $a == "$b" ]] && { echo "$a"; return; }
        warn "Empty or not matching, try again" >&2
    done
}
part() { [[ $1 == *[0-9] ]] && echo "${1}p$2" || echo "$1$2"; }   # /dev/nvme0n1 + 2 -> /dev/nvme0n1p2

[[ $EUID -eq 0 ]] || die "Run as root (the live USB logs you in as root)."
[[ -d /sys/firmware/efi ]] || die "Not booted in UEFI mode. Disable CSM/Legacy in the firmware."
curl -fsS --max-time 10 -o /dev/null https://archlinux.org || die "No internet. Wi-Fi: iwctl → station wlan0 connect <SSID>"
timedatectl set-ntp true

# ---------------------------------------------------------------- questions
say "Disks"
lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -vE 'loop|sr[0-9]|usb|zram' || true
# TYPE before TRAN: VM disks (virtio) have an empty TRAN, which would shift the columns
mapfile -t disks < <(lsblk -dpno NAME,TYPE,TRAN | awk '$2=="disk" && $3!="usb" && $1 !~ /zram/{print $1}')
((${#disks[@]})) || die "No internal disk found"
DISK=$(choose "Install Linux on" "${disks[@]}")

echo
say "Windows on $DISK:"
lsblk -pno NAME,SIZE,FSTYPE,PARTLABEL "$DISK"
MODE=$(choose "Dual boot" \
    "Linux only (erase $DISK)" \
    "Windows on ANOTHER SSD (erase $DISK)" \
    "Windows on THIS SSD, not installed yet (erase $DISK, keep space for Windows)" \
    "Windows on THIS SSD, already installed (use the free space, keep Windows)")
case $MODE in
    "Linux only"*)            MODE=none ;;
    "Windows on ANOTHER"*)    MODE=other-disk ;;
    *"not installed yet"*)    MODE=same-disk-later ;;
    *"already installed"*)    MODE=same-disk-existing ;;
esac

disk_gib=$(($(blockdev --getsize64 "$DISK") / 1024 / 1024 / 1024))
WIN_GIB=0
if [[ $MODE == same-disk-later ]]; then
    WIN_GIB=$(ask "Space to keep for Windows, in GiB (disk is ${disk_gib} GiB)" "$((disk_gib / 3))")
    ((WIN_GIB > 64 && WIN_GIB < disk_gib - 40)) || die "Windows needs > 64 GiB and Linux at least 40 GiB"
fi

HOSTNAME_=$(ask "Hostname" "archlinux")
USERNAME=$(ask "Username" "aplanche")
USERPASS=$(password "Password for $USERNAME (also used for sudo)")
TZ_GUESS=$(curl -fsS --max-time 5 https://ipapi.co/timezone 2>/dev/null || echo UTC)
TIMEZONE=$(ask "Time zone" "$TZ_GUESS")
[[ -f /usr/share/zoneinfo/$TIMEZONE ]] || die "Unknown time zone: $TIMEZONE"
KEYMAP=$(ask "Console keymap" "us")
LUKS=0
if yes_no "Encrypt the Linux partition with LUKS (recommended on a laptop; passphrase at every boot)?"; then
    LUKS=1; LUKSPASS=$(password "Disk encryption passphrase")
fi

echo
warn "About to write to $DISK (mode: $MODE). $([[ $MODE == same-disk-existing ]] && echo 'Existing partitions are kept.' || echo 'EVERYTHING ON IT WILL BE ERASED.')"
yes_no "Continue?" || die "Cancelled"

# ---------------------------------------------------------------- partitions
umount -R "$MNT" 2>/dev/null || true
if [[ $MODE == same-disk-existing ]]; then
    # Reuse the Windows ESP (UKIs need room: refuse a too small one) and the largest free area
    ESP=$(lsblk -pno NAME,PARTTYPE "$DISK" | awk 'tolower($2)=="c12a7328-f81f-11d2-ba4b-00a0c93ec93b"{print $1; exit}')
    [[ -n $ESP ]] || die "No EFI system partition on $DISK"
    esp_mib=$(($(blockdev --getsize64 "$ESP") / 1024 / 1024))
    ((esp_mib >= 500)) || die "The Windows EFI partition is only ${esp_mib} MiB (two kernel images need ~500). Easiest: reinstall with \"Windows not installed yet\" and install Windows after Linux."
    sgdisk -n 0:0:0 -t 0:8300 -c 0:linux "$DISK" >/dev/null || die "No free space on $DISK (shrink Windows from Disk Management first)"
    partprobe "$DISK"; sleep 1
    ROOT=$(lsblk -pno NAME,PARTLABEL "$DISK" | awk '$2=="linux"{print $1}' | tail -1)
else
    wipefs -af "$DISK" >/dev/null
    sgdisk -Z "$DISK" >/dev/null
    sgdisk -n 1:0:+1G -t 1:ef00 -c 1:ESP "$DISK" >/dev/null
    if ((WIN_GIB)); then
        # Windows Setup reuses this ESP and creates its MSR + NTFS partitions in the space left at the end
        sgdisk -n 2:0:-"${WIN_GIB}G" -t 2:8300 -c 2:linux "$DISK" >/dev/null
    else
        sgdisk -n 2:0:0 -t 2:8300 -c 2:linux "$DISK" >/dev/null
    fi
    partprobe "$DISK"; sleep 1
    ESP=$(part "$DISK" 1) ROOT=$(part "$DISK" 2)
    mkfs.fat -F32 -n ESP "$ESP" >/dev/null
fi

ROOTDEV=$ROOT
if ((LUKS)); then
    printf '%s' "$LUKSPASS" | cryptsetup luksFormat --type luks2 -q "$ROOT" -
    printf '%s' "$LUKSPASS" | cryptsetup open "$ROOT" root -
    ROOTDEV=/dev/mapper/root
fi
mkfs.btrfs -f -L arch "$ROOTDEV" >/dev/null
mount "$ROOTDEV" "$MNT"
for sv in @ @home @pkg @log; do btrfs subvolume create "$MNT/$sv" >/dev/null; done
umount "$MNT"
mount -o "$BTRFS_OPTS,subvol=@" "$ROOTDEV" "$MNT"
mkdir -p "$MNT"/{boot,home,var/cache/pacman/pkg,var/log}
mount -o "$BTRFS_OPTS,subvol=@home" "$ROOTDEV" "$MNT/home"
mount -o "$BTRFS_OPTS,subvol=@pkg"  "$ROOTDEV" "$MNT/var/cache/pacman/pkg"
mount -o "$BTRFS_OPTS,subvol=@log"  "$ROOTDEV" "$MNT/var/log"
mount -o fmask=0077,dmask=0077 "$ESP" "$MNT/boot"
say "Partitions ready: ESP=$ESP root=$ROOT$( ((LUKS)) && echo ' (LUKS)')"

# ---------------------------------------------------------------- base system
ucode=amd-ucode; grep -q GenuineIntel /proc/cpuinfo && ucode=intel-ucode
pkgs=(base linux linux-firmware "$ucode" btrfs-progs networkmanager sudo git zsh nano efibootmgr curl)
((LUKS)) && pkgs+=(cryptsetup)
say "pacstrap (stock kernel for the first boot; install.sh switches to linux-cachyos)"
pacstrap -K "$MNT" "${pkgs[@]}"
genfstab -U "$MNT" >>"$MNT/etc/fstab"

ROOT_UUID=$(blkid -s UUID -o value "$ROOTDEV")
CMDLINE="root=UUID=$ROOT_UUID rootflags=subvol=@ rw rootfstype=btrfs quiet loglevel=3"
HOOKS="base udev autodetect microcode modconf kms keyboard keymap consolefont block filesystems fsck"
if ((LUKS)); then
    CMDLINE="cryptdevice=UUID=$(blkid -s UUID -o value "$ROOT"):root $CMDLINE"
    HOOKS=${HOOKS/block filesystems/block encrypt filesystems}
fi

arch-chroot "$MNT" /bin/bash -e <<CHROOT
ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc
sed -i 's/^#en_US.UTF-8/en_US.UTF-8/' /etc/locale.gen && locale-gen >/dev/null
echo LANG=en_US.UTF-8 > /etc/locale.conf
echo KEYMAP=$KEYMAP > /etc/vconsole.conf
echo $HOSTNAME_ > /etc/hostname
printf '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 $HOSTNAME_\n' > /etc/hosts

useradd -m -G wheel -s /usr/bin/zsh $USERNAME
echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/00-wheel && chmod 440 /etc/sudoers.d/00-wheel
passwd -l root >/dev/null
systemctl enable NetworkManager systemd-timesyncd >/dev/null 2>&1

# Unified kernel image + systemd-boot (same scheme install.sh uses for the CachyOS kernels)
echo "$CMDLINE" > /etc/kernel/cmdline
sed -i "s/^HOOKS=(.*)/HOOKS=($HOOKS)/" /etc/mkinitcpio.conf
cat > /etc/mkinitcpio.d/linux.preset <<'P'
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux"
PRESETS=('default')
default_uki="/boot/EFI/Linux/arch-linux.efi"
P
mkdir -p /boot/EFI/Linux
mkinitcpio -P >/dev/null
bootctl install >/dev/null
printf 'timeout 3\ndefault arch-linux.efi\n' > /boot/loader/loader.conf
CHROOT
printf '%s:%s\n' "$USERNAME" "$USERPASS" | arch-chroot "$MNT" chpasswd

# ---------------------------------------------------------------- hand-off to install.sh
HOME_DIR="$MNT/home/$USERNAME"
mkdir -p "$HOME_DIR/Workspace"
cp -a "$REPO" "$HOME_DIR/Workspace/ArchSetup"
mkdir -p "$HOME_DIR/.config/arch-setup"
# Pre-answer the dual-boot question (install.sh asks the rest)
case $MODE in
    none) db=none ;; other-disk) db=other-disk ;; *) db=same-disk ;;
esac
echo "DUALBOOT=$db" >"$HOME_DIR/.config/arch-setup/machine.conf"
# First login on tty1 starts install.sh by itself. This .zprofile is replaced by the real one
# (a symlink into the repo) during the dotfiles step, so it only ever runs until then.
cat >"$HOME_DIR/.zprofile" <<'Z'
if [[ $(tty) == /dev/tty1 && -x ~/Workspace/ArchSetup/install.sh ]]; then
    echo "Starting ArchSetup. Wi-Fi? Press Ctrl+C, run nmtui, then ~/Workspace/ArchSetup/install.sh"
    sleep 3
    ping -c1 -W3 archlinux.org >/dev/null 2>&1 || nmtui
    ~/Workspace/ArchSetup/install.sh
fi
Z
arch-chroot "$MNT" chown -R "$USERNAME:$USERNAME" "/home/$USERNAME"

say "Done. Remove the USB key and reboot:  reboot"
echo "   Log in as $USERNAME on the console: install.sh starts by itself."
[[ $MODE == same-disk-later ]] && echo "   Windows later: boot its installer and pick the ${WIN_GIB} GiB of unallocated space."
exit 0
