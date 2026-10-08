#!/usr/bin/env bash
set -euo pipefail

if [ "$EUID" -ne 0 ]; then
    echo "[-] Please run this script with sudo: sudo bash $0"
    exit 1
fi

echo "============================================================"
echo "  CachyOS Kernel & Optimization Setup (AMD Ryzen 7 9850X3D) "
echo "============================================================"

# Step 1: Add CachyOS Repositories (Downloads official repo tarball)
echo "[*] Downloading and installing CachyOS repositories..."
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT

curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o "$WORK_DIR/cachyos-repo.tar.xz"
tar -xf "$WORK_DIR/cachyos-repo.tar.xz" -C "$WORK_DIR"
(cd "$WORK_DIR/cachyos-repo" && ./cachyos-repo.sh)

# Step 2: Install CachyOS Kernel, Headers, Schedulers and Settings
echo "[*] Installing linux-cachyos, scx-scheds, and cachyos-settings..."
pacman -Sy --needed --noconfirm linux-cachyos linux-cachyos-headers scx-scheds cachyos-settings

# Step 3: Configure UKI (Unified Kernel Image) preset for systemd-boot
echo "[*] Configuring mkinitcpio preset for UKI (/boot/EFI/Linux/arch-linux-cachyos.efi)..."
cat << 'PRESET_EOF' > /etc/mkinitcpio.d/linux-cachyos.preset
# mkinitcpio preset file for the 'linux-cachyos' package
ALL_config="/etc/mkinitcpio.conf"
ALL_kver="/boot/vmlinuz-linux-cachyos"

PRESETS=('default')

default_uki="/boot/EFI/Linux/arch-linux-cachyos.efi"
default_options="--splash /usr/share/systemd/bootctl/splash-arch.bmp"
PRESET_EOF

# Step 4: Build the UKI image
echo "[*] Building Unified Kernel Image for linux-cachyos..."
mkinitcpio -p linux-cachyos

# Step 5: Configure systemd-boot default entry
echo "[*] Setting default boot entry to arch-linux-cachyos.efi..."
bootctl set-default arch-linux-cachyos.efi || true

# Step 6: Configure scx scheduler (scx_lavd for optimal gaming/interactive latency + stability)
echo "[*] Configuring sched-ext to use scx_lavd..."
if [ -f /etc/default/scx ]; then
    sed -i 's/^SCX_SCHEDULER=.*/SCX_SCHEDULER=scx_lavd/' /etc/default/scx
else
    mkdir -p /etc/default
    echo "SCX_SCHEDULER=scx_lavd" > /etc/default/scx
fi

echo "[*] Enabling scx.service..."
systemctl enable scx.service || true

echo "============================================================"
echo "  Installation Complete!                                    "
echo "  Default kernel: linux-cachyos (UKI)                       "
echo "  Default scheduler: scx_lavd (with BORE fallback)          "
echo "                                                            "
echo "  You can now reboot your system:                           "
echo "    sudo reboot                                             "
echo "============================================================"
