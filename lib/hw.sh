# shellcheck shell=bash
# Hardware detection. Everything reads /proc, /sys and lspci, so it also works before drivers are installed.

cpu_vendor() {
    case $(grep -m1 vendor_id /proc/cpuinfo) in
        *AuthenticAMD*) echo amd ;;
        *GenuineIntel*) echo intel ;;
        *) echo other ;;
    esac
}

# GPU vendors present, one per line: amd / nvidia / intel (PCI classes 0300 VGA, 0302 3D, 0380 display)
gpu_vendors() {
    lspci -n | awk '$2 ~ /^03(00|02|80):/ {split($3, id, ":"); print id[1]}' | sort -u | while read -r v; do
        case $v in
            1002) echo amd ;;
            10de) echo nvidia ;;
            8086) echo intel ;;
        esac
    done
}

# NVIDIA GPUs older than Turing (GTX 10xx and before) are not supported by the open kernel modules
nvidia_is_legacy() {
    lspci | grep -iE 'vga|3d' | grep -i nvidia | grep -qiE 'GTX (9|10)[0-9]{2}|GT [0-9]{3,4}|Quadro (P|M|K)|Titan (X|Xp)'
}

is_vm()      { [[ $(systemd-detect-virt 2>/dev/null) != none ]]; }
virt_kind()  { systemd-detect-virt 2>/dev/null; }
is_laptop()  { compgen -G "/sys/class/power_supply/BAT*" >/dev/null || [[ $(hostnamectl chassis 2>/dev/null) == laptop ]]; }
has_bluetooth() { [[ -d /sys/class/bluetooth ]] && compgen -G "/sys/class/bluetooth/hci*" >/dev/null; }
has_broadcom_wifi() { lspci -n | awk '$2 ~ /^0280:/' | grep -q ' 14e4:'; }

# x86-64 micro-architecture level supported by the CPU (for the CachyOS optimized repos)
isa_level() {
    local out; out=$(/lib/ld-linux-x86-64.so.2 --help 2>/dev/null)
    if grep -q 'x86-64-v4 (supported' <<<"$out"; then echo v4
    elif grep -q 'x86-64-v3 (supported' <<<"$out"; then echo v3
    else echo v1; fi
}

# Root filesystem facts used to build the kernel command line
root_source()  { findmnt -no SOURCE / | sed 's/\[.*\]//'; }
root_fstype()  { findmnt -no FSTYPE /; }
root_subvol()  { findmnt -no OPTIONS / | tr ',' '\n' | sed -n 's/^subvol=//p'; }
root_on_lvm()  { [[ $(lsblk -no TYPE "$(root_source)" 2>/dev/null | head -1) == lvm ]]; }
# Underlying LUKS device of / (empty if not encrypted)
root_luks_dev() { lsblk -rsno NAME,TYPE "$(root_source)" 2>/dev/null | awk 'prev=="crypt"{print "/dev/" $1; exit} {prev=$2}'; }

# Windows Boot Manager entry number in the UEFI boot menu (empty if none)
windows_boot_entry() { efibootmgr 2>/dev/null | sed -n 's/^Boot\([0-9A-Fa-f]\{4\}\)\*\{0,1\} Windows Boot Manager.*/\1/p' | head -1; }

# Disk holding the ESP mounted on /boot (e.g. /dev/nvme0n1)
boot_disk() { local p; p=$(findmnt -no SOURCE /boot); echo "/dev/$(lsblk -no PKNAME "$p" | head -1)"; }

# NTFS partitions that look like a Windows install, as "DEVICE DISK" lines
windows_partitions() { lsblk -rpno NAME,FSTYPE,PKNAME | awk '$2=="ntfs"{print $1, $3}'; }
