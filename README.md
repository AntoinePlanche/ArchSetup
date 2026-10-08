# ArchSetup

Turns a fresh Arch install into this desktop: CachyOS kernel + Secure Boot, Hyprland + quickshell,
same packages, same scripts and timers, R2 sync. Documents and Pictures are not in git: they come
back from Cloudflare R2 through `rclone-sync`.

## New machine

**1. Base system (from the Arch USB)**: either one:

```sh
# a) Scripted, asks about dual boot and partitions accordingly (needed for Windows on the same SSD)
iwctl                          # Wi-Fi only: station wlan0 connect <SSID>
pacman -Sy git
git clone https://github.com/<you>/ArchSetup && ArchSetup/live-install.sh
```

b) `archinstall`, with the **systemd-boot** bootloader and the ESP mounted on **/boot**
(btrfs recommended for snapper). Then after reboot:
`git clone https://github.com/<you>/ArchSetup ~/Workspace/ArchSetup`.

**2. `~/Workspace/ArchSetup/install.sh`** as your user, from the console. With option a) it starts by
itself at the first login on tty1. It asks for the sudo password, whether to dual boot, and which
optional groups to install. Everything else is automatic.

**3. Reboot and log in.** The **setup wizard** opens in Hyprland for everything that needs you:
Secure Boot key enrollment (it reboots into the firmware for you), R2 keys, pCloud / GitHub /
NordVPN browser logins, Google account in Evolution, Chrome & VS Code sync, Hyprland plugins, and
the LLM model download. Unfinished items come back at the next login. Open it any time with
`arch-setup-wizard` (`--all` to redo a step).

## What `install.sh` does

| Step | |
|---|---|
| `preflight` | UEFI/ESP/network checks, pacman (Color, parallel downloads, multilib), machine questions |
| `repos` | CachyOS repos via the official script (znver4 / v4 / v3 picked from the CPU), paru, yay, rustup |
| `kernel` | `linux-cachyos` + `linux-cachyos-lts` as UKIs in `/boot/EFI/Linux`, `/etc/kernel/cmdline` built from the real root (UUID / LVM / LUKS / btrfs subvol), systemd-boot, removes the stock kernel |
| `drivers` | Only what the hardware needs: AMD (RADV) / Intel (ANV) / NVIDIA (CachyOS prebuilt open modules, or legacy for pre-Turing), hybrid → `nvidia-prime`, Bluetooth, Broadcom Wi-Fi, laptop power (UPower, power-profiles-daemon, brightnessctl), VM guest tools |
| `packages` | `packages/*.txt`: same list as the original machine; `opt-*` groups as chosen |
| `dotfiles` | Symlinks from `links.txt` (anything in the way is moved to `~/.local/state/arch-setup/backup/`) |
| `system` | `system/` copied as root (keyd, SDDM Liquid Glass theme, sudoers, scx, zram, units), services, snapper, zsh + oh-my-zsh, user timers |
| `dualboot` | Windows: sudoers for one-time BootNext, keeps Linux first in the UEFI order; nothing without dual boot |
| `secureboot` | sbctl keys, signs systemd-boot + UKIs; enrolls (with Microsoft keys) if the firmware is in Setup Mode, else hands over to the wizard |
| `extras` | omp, user dirs, arms the wizard |

Every step is idempotent: `./install.sh` again, or only some steps: `./install.sh dotfiles system`.
Answers are kept in `~/.config/arch-setup/machine.conf`; `./install.sh --reconfigure` asks again.

## Day to day

- Dotfiles are **symlinks into this repo**: edit `~/.config/hypr/hyprland.lua` (or any linked file)
  and the change is already here: commit + push. On another machine: `git pull`.
  Files under `system/` are copies (root-owned): after editing them, `./install.sh system`.
- New config to track: copy it to `home/<same path>`, add the path to `links.txt`, run `./install.sh dotfiles`.
- New package: add it to the right `packages/*.txt`.

## Scheduled jobs (systemd user timers)

| Timer | What |
|---|---|
| `rclone-sync` | every 5 min, bisync `~/Documents` + `~/Pictures` ↔ `r2:aplanche-personal` (enabled by the wizard once R2 is configured) |
| `system-update` | daily check, weekly `yay -Syu` + omp + hyprpm rebuild |
| `ghostty-rotate-bg` | every 15 min, Ghostty background from `~/Pictures/Terminal` |
| `spotlight-download` | weekly, Windows Spotlight images → `~/Pictures/Logging` → login screen |

## Machine-local, not in git

`~/.config/rclone/rclone.conf` (credentials), `~/rclone-sync/bisync-state`, `~/.config/zsh/local.zprofile`
(GPU env vars), `~/.config/ghostty/background.ghostty`, `~/.config/arch-setup/`.

## Not automated

kiro-cli / `q`, the Hermes agent venv (`~/.hermes`), agy, cua-driver: vendor installers, run them by hand.
