#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run with sudo: sudo bash $0"
    exit 1
fi

USB_DEV="/dev/sda"
ISO_PATH="/home/aplanche/Downloads/Win11_25H2_English_x64_v2.iso"

if [ ! -b "$USB_DEV" ]; then
    echo "[-] USB device $USB_DEV not found!"
    exit 1
fi

if [ ! -f "$ISO_PATH" ]; then
    echo "[-] Windows 11 ISO not found at $ISO_PATH!"
    exit 1
fi

echo "============================================================"
echo "  Creating Native Windows 11 UEFI USB Installer             "
echo "============================================================"

echo "[*] Installing required tools (ntfsprogs, ntfs-3g, dosfstools, rsync, parted)..."
pacman -Sy --needed --noconfirm ntfsprogs ntfs-3g dosfstools rsync parted

echo "[*] Unmounting all partitions on $USB_DEV..."
umount -l ${USB_DEV}* 2>/dev/null || true

echo "[*] Creating standard GPT partition table on $USB_DEV..."
wipefs --all --force "$USB_DEV"
parted -s "$USB_DEV" mklabel gpt
parted -s "$USB_DEV" mkpart "WINBOOT" fat32 1MiB 1024MiB
parted -s "$USB_DEV" set 1 esp on
parted -s "$USB_DEV" mkpart "WININSTALL" ntfs 1024MiB 100%

# Allow kernel to register partitions
partprobe "$USB_DEV" 2>/dev/null || true
udevadm settle
sleep 2

echo "[*] Formatting FAT32 UEFI Boot partition..."
mkfs.vfat -F32 -n "WINBOOT" "${USB_DEV}1"

echo "[*] Formatting NTFS Install Data partition..."
mkfs.ntfs -f -L "WININSTALL" "${USB_DEV}2"

# Allow kernel to update filesystem signatures
partprobe "$USB_DEV" 2>/dev/null || true
udevadm settle
sleep 2

echo "[*] Mounting partitions and ISO..."
MOUNT_BOOT=$(mktemp -d)
MOUNT_INSTALL=$(mktemp -d)
MOUNT_ISO=$(mktemp -d)

mount -o loop,ro "$ISO_PATH" "$MOUNT_ISO"
mount -t vfat "${USB_DEV}1" "$MOUNT_BOOT"
mount.ntfs-3g "${USB_DEV}2" "$MOUNT_INSTALL"

echo "[*] Copying all files to NTFS partition (including install.wim)..."
rsync -a --info=progress2 "$MOUNT_ISO/" "$MOUNT_INSTALL/"

echo "[*] Copying standard Microsoft UEFI bootloader files to FAT32 partition..."
rsync -a --info=progress2 --exclude='sources/install.wim' "$MOUNT_ISO/" "$MOUNT_BOOT/"

echo "[*] Syncing data to disk (ensuring complete write)..."
sync

echo "[*] Cleaning up temporary mounts..."
umount "$MOUNT_ISO" "$MOUNT_BOOT" "$MOUNT_INSTALL"
rm -rf "$MOUNT_ISO" "$MOUNT_BOOT" "$MOUNT_INSTALL"

echo "============================================================"
echo "  Native Windows 11 USB Created Successfully!               "
echo "  - Partition 1: FAT32 Standard UEFI Boot                   "
echo "  - Partition 2: NTFS Windows Installation Data             "
echo "                                                            "
echo "  You can now reboot and select the USB in the boot menu!   "
echo "============================================================"
