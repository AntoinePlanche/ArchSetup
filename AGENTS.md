# AGENTS.md

Onboarding for coding agents. Read this before touching anything: **this repo is the live
configuration of the machine you are running on.**

## What this repo is

ArchSetup rebuilds one personal Arch Linux desktop (Hyprland + quickshell, CachyOS kernel,
Secure Boot) on a fresh install, and is at the same time the live source of its dotfiles.

Three stages, in order:

| Stage | Entry point | Runs | Interaction |
|---|---|---|---|
| 0 | `live-install.sh` | as root on the Arch live USB | TTY prompts (disk, dual boot, user, LUKS) |
| 1 | `install.sh [step...]` | as the user, from a TTY/terminal | `gum` prompts, sudo asked once |
| 2 | `firstlogin/first-login.sh` (linked as `~/.local/bin/arch-setup-wizard`) | inside Hyprland, autostarted | `zenity` dialogs, browser logins, `sudo -A` pop-ups |

Rule of thumb: anything needing an account, a browser or a firmware reboot belongs to stage 2,
never to the TTY.

## Layout

```
install.sh            orchestrator: sources lib/, runs steps/<name>.sh → step_<name>()
live-install.sh       stage 0 (partitioning, pacstrap, hands off to install.sh via ~/.zprofile)
lib/common.sh         logging (info/ok/warn/die/title), ask_choice/ask_multi (answers persisted),
                      pkg_install (repo vs AUR split), install_system_file, root_test, sudo_keepalive
lib/hw.sh             hardware detection: cpu_vendor, gpu_vendors, nvidia_branch, is_laptop, is_vm,
                      isa_level, root_* (fs/LVM/LUKS/subvol), windows_boot_entry, boot_disk
steps/*.sh            one function step_<name> each; order is ALL_STEPS in install.sh
firstlogin/           the zenity wizard: TASKS table + pending_<id>() + task_<id>() per task
packages/*.txt        package lists, one per line, # comments; opt-* are optional groups
links.txt             paths in $HOME that become symlinks into home/
home/                 dotfiles, mirrored at their $HOME-relative path
system/               files copied to / as root (@USER@ / @HOME@ are substituted)
system/optional/      copied only under a condition (e.g. dual boot sudoers)
system/snapper/       snapper configs, applied after `snapper create-config`
docs/screenshots/     README images
```

Per-machine state, never in git:
- `~/.config/arch-setup/machine.conf`: answers (DUALBOOT, OPTIONAL, SECUREBOOT, SB_LAST_TRY)
- `~/.config/arch-setup/secureboot-PK.der`: cached public PK cert (lets the wizard check enrollment without root)
- `~/.local/state/arch-setup/`: `install.log`, `step-*.done`, `wizard/` task markers, `backup/`
- `~/.config/zsh/local.zprofile`: GPU env vars written by `steps/drivers.sh`
- `~/.config/ghostty/background.ghostty`, `~/.config/rclone/rclone.conf`, `~/rclone-sync/bisync-state`

## Critical gotchas

1. **`home/` is live.** `~/.config/hypr`, `~/.config/quickshell`, `~/.zshrc`, `~/.local/bin/*`, the
   user timers… are symlinks into this repo. Editing a file here edits the running desktop
   immediately (Hyprland and quickshell auto-reload on change).
2. **Git operations that rewrite the working tree break the session for a moment.** `rebase`,
   `checkout`/`switch`, `reset --hard`, `stash` delete-and-recreate files; Hyprland may reload in
   between and keep a stale `cannot open …/hyprland.lua` error. Run `hyprctl reload` afterwards and
   check `hyprctl configerrors` is empty. Prefer a separate worktree/clone for history surgery.
3. **Moving or renaming the repo dangles every link.** Afterwards: `./install.sh dotfiles` then
   `hyprctl reload`.
4. **`system/` is copied, not linked** (root-owned targets; SDDM can't read `$HOME`). After editing,
   apply with `./install.sh system`. Never edit `/etc/...` or `/usr/share/sddm/themes/liquid-glass`
   directly: the change is lost from the repo and overwritten on the next run.
5. **Hyprland uses the Lua config** (`hyprland.lua`, `hl.*` API: `hl.bind`, `hl.exec_cmd`,
   `hl.dsp.*`, `hl.monitor`), not hyprlang. `hyprctl dispatch` takes Lua dispatcher syntax.
   `monitors.lua` is machine-local (nwg-displays) and git-ignored.
6. **sudo:** no TTY in an agent shell. Use `sudo -A` with `SUDO_ASKPASS=~/.local/bin/sudo-askpass`
   (a zenity pop-up the user answers). In the wizard, `sudo` is already wrapped to `sudo -A`.
7. **`/boot` is root-only** (ESP mounted `dmask=0077`): test paths there with `root_test -f …`, not `[[ -f ]]`.
8. **Idempotency is a contract.** Every step must be safe to re-run on an already configured
   machine (this one). Check before creating, use `--needed`, back up before replacing.
9. **Ghostty** is a single persistent process: reload its config with `pkill -USR2 -x ghostty`.
   Don't write to `config.ghostty` from scripts (it's a tracked symlink); use an included file.
10. **Rust:** use `rustup`, never `extra/rust` (breaks against CachyOS `llvm-libs`).

## Conventions

- Bash, `set -euo pipefail` in entry points; steps are sourced, so they use `return`, not `exit`.
- Output through `info/ok/warn/die/title` (they also write to the log). Long command output goes to `"$LOG"`.
- `sudo cmd >>"$LOG"` is intentional (the log is user-owned); ignore shellcheck SC2024.
- New machine question → `ask_choice`/`ask_multi` with a key, so it's asked once and stored.
- Comments explain *why* (hardware quirks, firmware behaviour), matching the existing density.
- Packages: prefer repo/CachyOS/AUR packages over vendor scripts or extra runtimes.
- Never put secrets in the repo. Credentials are typed in the wizard and stay in local config.
- Hardware-specific values (PCI addresses, boot entry numbers, monitor names) must be detected at
  runtime, not hardcoded. Existing examples: `boot-to-windows`, `SysStats.qml` GPU path, `nvidia_branch`.

## Commits

Conventional Commits (`feat:`, `fix(scope):`, `refactor:`, `docs:`…), subject ≤ 72 chars, body
explaining why. Author: Antoine Planche. **No `Co-Authored-By` or other AI attribution trailer.**
Commit only when asked.

## Verifying changes

There is no test suite; verify on the live machine, without side effects:

```sh
bash -n install.sh live-install.sh lib/*.sh steps/*.sh firstlogin/first-login.sh
shellcheck -x -e SC1091,SC2155,SC2024 install.sh live-install.sh lib/*.sh steps/*.sh firstlogin/first-login.sh
python3 -m py_compile home/.local/bin/gcalendar-events home/.config/quickshell/scripts/*.py
hyprctl reload && hyprctl configerrors          # must print nothing
qs log | tail                                    # last line: Configuration Loaded
~/.local/bin/arch-setup-wizard --if-pending      # on this machine: exits silently
```

To exercise a generator without writing, source the libs in a subshell and shadow `sudo`
(e.g. make `sudo install` print instead of write). Hardware branches you can't reach here
(NVIDIA, laptop, VM) can be tested by overriding `lspci`/`gpu_vendors` the same way.

## Where to look

| Task | Files |
|---|---|
| Add a package | `packages/<group>.txt` |
| Track a new config | copy to `home/<path>`, add the path to `links.txt`, `./install.sh dotfiles` |
| Add a timer/cron | unit pair in `home/.config/systemd/user/`, `links.txt`, enable in `steps/system.sh` `setup_user_units` |
| Add a wizard task | `TASKS` entry + `pending_<id>` + `task_<id>` in `firstlogin/first-login.sh` |
| Kernel cmdline / initramfs | `steps/kernel.sh` (`write_cmdline`, `write_mkinitcpio_conf`) |
| Driver selection | `steps/drivers.sh`, detection in `lib/hw.sh` |
| Secure Boot | `steps/secureboot.sh` (helpers shared with the wizard) |
| Bar / popups / widgets | `home/.config/quickshell/` (`shell.qml` is the root) |
| Login screen | `system/usr/share/sddm/themes/liquid-glass/` |
