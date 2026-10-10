#!/usr/bin/env bash
# Graphical setup wizard, run inside Hyprland (autostarted by hyprland.lua as ~/.local/bin/arch-setup-wizard).
# Everything that needs an account or a reboot into the firmware lives here instead of the TTY:
# browser logins (OAuth) where the service offers it, zenity forms and password pop-ups otherwise.
#
#   arch-setup-wizard              show the remaining tasks
#   arch-setup-wizard --if-pending exit silently when nothing is left (used at login)
#   arch-setup-wizard --all        list every task, done or not (to redo one)
set -uo pipefail

REPO=$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")/.." && pwd)
source "$REPO/lib/common.sh"
source "$REPO/lib/hw.sh"
source "$REPO/steps/secureboot.sh"

export SUDO_ASKPASS="$HOME/.local/bin/sudo-askpass"
# No terminal here: every sudo (also inside the sourced helpers) asks with the zenity pop-up
sudo() { command sudo -A "$@"; }
DONE_DIR="$STATE_DIR/wizard"
mkdir -p "$DONE_DIR"
TITLE="New machine setup"
R2_BUCKET="aplanche-personal"   # same bucket as ~/rclone-sync/rclone-sync.sh

z() { zenity --title="$TITLE" --width=520 "$@" 2>/dev/null; }
mark_done() { date '+%F %T' >"$DONE_DIR/$1"; }
is_done() { [[ -f $DONE_DIR/$1 ]]; }
in_terminal() { ghostty --title="$TITLE" -e bash -c "$1; echo; read -rp 'Press Enter to close'"; }
notify() { notify-send -a "$TITLE" "$@" 2>/dev/null || true; }

# ---------------------------------------------------------------------------------------------
# Tasks: "id|Label|description". pending_<id> returns 0 when the task still has to be done.
TASKS=(
    "secureboot|Secure Boot|Your own keys; Secure Boot stays OFF until the last step (up to two firmware reboots)"
    "r2|Cloudflare R2 (Documents + Pictures)|rclone remote + first sync, then every 5 minutes"
    "pcloud|pCloud|rclone remote, browser login"
    "github|Git + GitHub|Name/email for commits, GitHub login in the browser"
    "google|Google account|Evolution: calendar for the bar and gcalendar-events, browser login"
    "browsers|Chrome + VS Code sync|Sign in to get bookmarks, extensions and settings back"
    "nordvpn|NordVPN|Browser login"
    "hyprpm|Hyprland plugins|Build Hyprspace (SUPER+Tab overview) and hyprfocus"
    "llm|Local LLM model|Download Qwen3.6-35B-A3B (about 22 GB) for llama-server"
)

pending_secureboot() { ! is_vm && [[ $(conf_get SECUREBOOT) != skipped ]] && ! { sb_enrolled && sb_enabled; }; }
pending_r2()       { ! rclone listremotes 2>/dev/null | grep -qx 'r2:'; }
pending_pcloud()   { ! rclone listremotes 2>/dev/null | grep -qx 'pcloud:' && ! is_done pcloud; }
pending_github()   { [[ -z $(git config --global user.email) ]] || ! is_done github; }
pending_google()   { ! is_done google; }
pending_browsers() { ! is_done browsers; }
pending_nordvpn()  { has_opt vpn && ! is_done nordvpn; }
pending_hyprpm()   { ! hyprpm list 2>/dev/null | grep -q 'Plugin Hyprspace'; }
pending_llm()      { has_opt llm && [[ ! -f $(llm_model_path) ]]; }

# ---------------------------------------------------------------------------------------------
# Secure Boot takes up to three firmware visits; each dialog says which stage you are at, so
# "Secure Boot is still off" never looks like a bug.
#   1/3 firmware not in Setup Mode -> reboot to firmware, clear the factory keys
#   2/3 Setup Mode                 -> enroll our keys + Microsoft's here (no reboot needed for that)
#   3/3 keys enrolled, still off   -> reboot to firmware, switch Secure Boot ON
sb_stage() {
    if sb_enrolled; then sb_enabled && echo done || echo 3
    elif sb_setup_mode; then echo 2
    else echo 1; fi
}
sb_task_desc() {
    case $(sb_stage) in
        1) echo "Step 1/3: reboot into the firmware and clear the factory keys (Setup Mode)" ;;
        2) echo "Step 2/3: the firmware is ready, enroll your keys now (no reboot)" ;;
        3) echo "Step 3/3: keys enrolled. Secure Boot is still OFF until you switch it on in the firmware" ;;
    esac
}
SB_FIRMWARE_HINTS="Where to find it (it depends on the brand):
  • ASUS: Advanced Mode (F7) → Boot → Secure Boot → Key Management
  • MSI: Settings → Security → Secure Boot
  • Gigabyte: BIOS → Secure Boot
  • Lenovo: Security → Secure Boot
  • Dell: Boot Configuration → Secure Boot → Expert Key Management
  • HP: Security → Secure Boot Configuration"

# Shown before every firmware reboot, while the user can still read it: once a wrong setting
# blocks the boot, Linux (and this wizard) can't tell them anything.
SB_RESCUE="<b>If the PC then refuses to boot</b> (red \"Secure Boot violation\" / \"Invalid signature\" screen):
nothing is broken. Enter the firmware again (Del / F2 at power-on), set Secure Boot to
<b>Disabled</b>, Save &amp; Exit: Linux starts and this wizard picks up where you are."

# Why a firmware visit may not have taken effect, per step
sb_retry_text() {
    case $1 in
        1) echo "<b>The firmware still has its factory keys.</b> Common causes:
  • the change was not saved: use <b>Save &amp; Exit</b> (often F10), not just Exit
  • Secure Boot mode is <b>Standard</b>: switch it to <b>Custom</b> first, then the key options appear
  • the option is called differently: Clear Secure Boot keys / Delete all keys / Delete PK /
    Reset to Setup Mode (only the PK has to go)
  • the options are greyed out: disable <b>CSM</b> first, or set a <b>supervisor password</b> (Lenovo, HP, Dell)" ;;
        3) echo "<b>Secure Boot is still off.</b> Common causes:
  • the change was not saved: use <b>Save &amp; Exit</b> (often F10)
  • the switch is greyed out: disable <b>CSM</b> first (ASUS: Boot → CSM), or set a supervisor password
  • on ASUS boards the switch is <b>OS Type</b>: choose <b>Windows UEFI mode</b> (it means Secure Boot on)
  • do <b>not</b> pick \"Restore factory keys\" / \"Install default keys\": that removes your keys again" ;;
    esac
}

# Ask before a firmware reboot. Echoes reboot / later / skip.
sb_ask() {
    local text=$1 out rc
    out=$(z --question --width=640 --ok-label="Reboot to firmware" --cancel-label="Later" \
        --extra-button="Skip Secure Boot" --text="$text")
    rc=$?
    if [[ $out == "Skip Secure Boot" ]]; then echo skip
    elif ((rc == 0)); then echo reboot
    else echo later; fi
}

sb_reboot_or_not() {  # stage text
    case $(sb_ask "$2") in
        reboot)
            conf_set SB_LAST_TRY "$1"   # compared with the firmware state after the reboot
            systemctl reboot --firmware-setup ;;
        skip)
            conf_set SECUREBOOT skipped
            z --info --text="Secure Boot skipped: Linux keeps booting without it and the wizard won't ask again.\nTo do it later: <tt>arch-setup-wizard --all</tt>, tick Secure Boot." ;;
    esac
    return 1
}

task_secureboot() {
    # Picked explicitly (e.g. with --all): a previous "skip" no longer applies
    [[ $(conf_get SECUREBOOT) == skipped ]] && conf_set SECUREBOOT pending
    local stage retry=""
    stage=$(sb_stage)
    # Back from the firmware but nothing changed: say why, instead of the same dialog again
    if [[ $(conf_get SB_LAST_TRY) == "$stage" ]]; then
        retry="⚠ <b>Last firmware visit did not take effect.</b>
$(sb_retry_text "$stage")

"
    elif [[ $(conf_get SB_LAST_TRY) == 3 && $stage == 1 ]]; then
        retry="⚠ <b>Your keys are no longer in the firmware</b> (\"Restore factory / default keys\" was probably used).
No harm done: start again from step 1, step 2 enrolls your keys again.

"
    fi
    case $stage in
        done)
            conf_set SECUREBOOT enrolled; conf_set SB_LAST_TRY ""
            z --info --text="✔ Secure Boot is <b>ON</b>, with your own keys. Nothing left to do."
            return 0 ;;
        3)
            conf_set SECUREBOOT enrolled
            sb_reboot_or_not 3 "$retry<b>Secure Boot, step 3/3</b>

Your keys are enrolled, but <b>Secure Boot is still OFF</b>. That is expected, not a bug:
the on/off switch only exists in the firmware, Linux cannot flip it.

In the firmware: set <b>Secure Boot</b> to <b>Enabled</b>, then <b>Save &amp; Exit</b>.
Do not restore the factory/default keys: that would undo step 2.

$SB_FIRMWARE_HINTS

$SB_RESCUE" ;;
        2)
            conf_set SB_LAST_TRY ""
            z --info --ok-label="Enroll" --text="<b>Secure Boot, step 2/3</b>\n\nThe firmware is in Setup Mode. Your keys are enrolled now, together with Microsoft's\n(so Windows and the GPU firmware keep booting). Your password is asked."
            sudo true || return 1
            sudo test -f /var/lib/sbctl/keys/PK/PK.pem || sudo sbctl create-keys >/dev/null 2>&1
            sb_cache_cert
            sign_boot_files >/dev/null
            if sudo sbctl enroll-keys --microsoft >>"$LOG" 2>&1; then
                conf_set SECUREBOOT enrolled
                task_secureboot   # continues with step 3/3
            else
                z --error --width=640 --text="Enrolling the keys failed: nothing was changed in the firmware.\n\n<tt>$(tail -n 5 "$LOG" | sed 's/&/\&amp;/g; s/</\&lt;/g')</tt>\n\nSome firmwares lock the key variables until they are fully in Setup Mode:\ngo back to step 1 and also clear the KEK/db keys (\"Delete all keys\")."
            fi
            return 1 ;;
        1)
            sb_reboot_or_not 1 "$retry<b>Secure Boot, step 1/3</b>

To boot with your own keys, the firmware must first forget its factory keys (<b>Setup Mode</b>).
In the firmware:
  1. Secure Boot mode: <b>Custom</b> (if the option exists)
  2. <b>Reset to Setup Mode</b>, or <b>Delete all Secure Boot keys</b> / <b>Clear keys</b>
  3. Leave Secure Boot <b>off</b> for now, then <b>Save &amp; Exit</b>
Turning Secure Boot <b>on</b> now, with the factory keys still there, blocks Linux from booting.

$SB_FIRMWARE_HINTS

$SB_RESCUE

Back in Hyprland, this wizard opens again at step 2/3." ;;
    esac
}

task_r2() {
    local form id key secret
    form=$(z --forms --text="Cloudflare R2 API token (R2 → Manage API tokens, \"Object Read &amp; Write\").\nBucket: $R2_BUCKET" \
        --add-entry="Account ID" --add-entry="Access Key ID" --add-password="Secret Access Key" --separator=$'\t') || return 1
    IFS=$'\t' read -r id key secret <<<"$form"
    [[ -n $id && -n $key && -n $secret ]] || { z --error --text="All three fields are needed."; return 1; }
    rclone config create r2 s3 provider=Cloudflare access_key_id="$key" secret_access_key="$secret" \
        endpoint="https://$id.r2.cloudflarestorage.com" acl=private no_check_bucket=true >/dev/null || return 1
    if ! rclone lsf --max-depth 1 "r2:$R2_BUCKET" >/dev/null 2>&1; then
        rclone config delete r2
        z --error --text="Could not list r2:$R2_BUCKET with these credentials. Nothing was saved."
        return 1
    fi
    # First run of the sync script detects the missing state and does a non-destructive --resync
    systemctl --user enable --now rclone-sync.timer
    systemctl --user start --no-block rclone-sync.service
    notify "R2 sync started" "Documents and Pictures are downloading in the background (log: ~/rclone-sync/rclone-backup.log). Wallpapers appear as soon as Pictures/Wallpapers is there."
    return 0
}

task_pcloud() {
    z --question --ok-label="Sign in" --cancel-label="Skip" --text="pCloud: your browser opens to sign in (EU region)." || { mark_done pcloud; return 0; }
    # rclone starts a local server and opens the browser for the OAuth login
    rclone config create pcloud pcloud hostname=eapi.pcloud.com >/dev/null 2>&1 &&
        rclone lsd pcloud: --max-depth 1 >/dev/null 2>&1 && { mark_done pcloud; return 0; }
    z --error --text="pCloud login did not complete."
    return 1
}

task_github() {
    local form name email
    form=$(z --forms --text="Git identity for your commits" --add-entry="Name" --add-entry="Email" --separator=$'\t') || return 1
    IFS=$'\t' read -r name email <<<"$form"
    [[ -n $name ]] && git config --global user.name "$name"
    [[ -n $email ]] && git config --global user.email "$email"
    git config --global init.defaultBranch main
    pacman -Qq github-cli &>/dev/null || sudo -n pacman -S --needed --noconfirm github-cli >/dev/null 2>&1 || sudo -A pacman -S --needed --noconfirm github-cli >/dev/null
    # Device-code login: the browser opens, the terminal shows the code to paste
    in_terminal "gh auth login --hostname github.com --git-protocol https --web && gh auth setup-git"
    gh auth status >/dev/null 2>&1 && { mark_done github; return 0; }
    return 1
}

task_google() {
    z --info --ok-label="Open Evolution" --text="Evolution opens. Add your Google account:\n<b>File → New → Collection Account</b>, type your Gmail address, then sign in in the browser window.\n\nThe bar calendar and gcalendar-events use this account."
    evolution >/dev/null 2>&1 &
    z --question --ok-label="Done" --cancel-label="Later" --text="Google account added in Evolution?" || return 1
    if "$HOME/.local/bin/gcalendar-events" --list-calendars 2>/dev/null | grep -qx Google; then
        mark_done google; return 0
    fi
    z --warning --text="No \"Google\" calendar in Evolution yet. It can take a minute to appear after signing in;\nthe wizard asks again at next login."
    return 1
}

task_browsers() {
    z --info --ok-label="Open them" --text="Chrome and VS Code open.\n • Chrome: sign in with Google (profile icon) to sync bookmarks and passwords.\n • VS Code: Accounts icon (bottom left) → <b>Backup and Sync Settings</b>, sign in with GitHub/Microsoft to get extensions and settings back."
    google-chrome-stable >/dev/null 2>&1 &
    code >/dev/null 2>&1 &
    z --question --ok-label="Done" --cancel-label="Later" --text="Signed in to Chrome and VS Code?" && { mark_done browsers; return 0; }
    return 1
}

task_nordvpn() {
    # Prints a login URL and opens the browser; the callback completes the login
    in_terminal "nordvpn login"
    nordvpn account >/dev/null 2>&1 && { mark_done nordvpn; return 0; }
    return 1
}

task_hyprpm() {
    (
        echo "# Downloading Hyprland headers (password asked)…"
        sudo -A true
        hyprpm update </dev/null
        echo "# Building Hyprspace…"
        yes | hyprpm add https://github.com/KZDKM/Hyprspace
        echo "# Building hyprland-plugins (hyprfocus)…"
        yes | hyprpm add https://github.com/hyprwm/hyprland-plugins
        hyprpm enable Hyprspace
        hyprpm enable hyprfocus
        hyprpm reload && hyprctl reload config-only
    ) 2>&1 | tee -a "$LOG" | z --progress --pulsate --auto-close --no-cancel --text="Building Hyprland plugins…"
    pacman -Q hyprland | awk '{print $2}' >"${XDG_STATE_HOME:-$HOME/.local/state}/hyprpm.built-for"
    ! pending_hyprpm
}

llm_model_path() { sed -n 's/^LLAMA_ARG_MODEL=//p' "$HOME/.config/llama/server/environment.conf" 2>/dev/null; }
task_llm() {
    local dest url
    dest=$(llm_model_path)
    url="https://huggingface.co/unsloth/Qwen3.6-35B-A3B-GGUF/resolve/main/$(basename "$dest")"
    mkdir -p "$(dirname "$dest")"
    curl -fL -C - -o "$dest.part" "$url" --progress-bar 2>&1 |
        stdbuf -oL tr '\r' '\n' | stdbuf -oL grep -oE '[0-9]+(\.[0-9])?%' | stdbuf -oL tr -d '%' |
        z --progress --auto-close --text="Downloading $(basename "$dest")…"
    if [[ ${PIPESTATUS[0]} -eq 0 ]]; then
        mv "$dest.part" "$dest"
        notify "Local LLM ready" "Type 'ai' in a terminal to start llama-server."
        return 0
    fi
    z --error --text="Download failed or cancelled (it resumes next time).\n$url"
    return 1
}

# ---------------------------------------------------------------------------------------------
main() {
    local mode=${1:-}
    # "Don't show at login" never hides a Secure Boot setup that is half done (steps 2/3 and 3/3):
    # the firmware state is what tells us where the user is, so we pick up right there.
    if [[ $mode == --if-pending && -f $DONE_DIR/dismissed ]]; then
        if ! pending_secureboot || [[ $(sb_stage) != [23] ]]; then exit 0; fi
    fi
    command -v zenity >/dev/null || exit 0

    if ! is_vm && [[ $(conf_get SECUREBOOT) == enrolled ]] && sb_enabled && ! is_done secureboot; then
        mark_done secureboot
        notify "Secure Boot is ON" "Your own keys are in use. Kernel updates are signed automatically."
    fi

    local rows=() t id label desc
    for t in "${TASKS[@]}"; do
        IFS='|' read -r id label desc <<<"$t"
        [[ $id == secureboot ]] && pending_secureboot && desc=$(sb_task_desc)
        if [[ $mode == --all ]] || "pending_$id"; then rows+=(TRUE "$id" "$label" "$desc"); fi
    done
    if ((${#rows[@]} == 0)); then
        [[ $mode == --if-pending ]] || z --info --text="Nothing left to set up. 🎉\n(Run with --all to redo a step.)"
        exit 0
    fi

    local chosen rc
    chosen=$(z --list --checklist --height=460 --width=820 --separator=' ' \
        --text="A few things need you (logins happen in your browser). Unticked items are asked again at next login." \
        --column="" --column="id" --column="Task" --column="What happens" --hide-column=2 --print-column=2 \
        --ok-label="Start" --cancel-label="Later" --extra-button="Don't show at login" "${rows[@]}")
    rc=$?
    if [[ $chosen == "Don't show at login" ]]; then
        touch "$DONE_DIR/dismissed"
        z --info --text="OK. Open it again any time with:\n<tt>arch-setup-wizard</tt>"
        exit 0
    fi
    ((rc == 0)) || exit 0

    local done=() left=()
    # Secure Boot last: its steps end with a reboot into the firmware, which would cut the
    # other tasks short. Progress is read back from the firmware at the next login.
    chosen=$(tr ' ' '\n' <<<"$chosen" | grep -vx secureboot; grep -qw secureboot <<<"$chosen" && echo secureboot)
    for id in $chosen; do
        if "task_$id"; then done+=("$id"); else left+=("$id"); fi
    done
    z --info --text="Done: ${done[*]:-nothing}\nStill to do: ${left[*]:-nothing}${left:+\n\nThe wizard comes back at next login (or run arch-setup-wizard).}"
}

main "$@"
