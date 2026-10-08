#!/usr/bin/env bash
# rofi script mode: system actions mixed into Spotlight's app results.
# Invisible "meta" keywords make "reboot", "poweroff", "windows"... find the right row.
# Everything except Lock asks for confirmation first.

row() { printf '%s\0icon\x1f%s\x1fmeta\x1f%s\x1finfo\x1f%s\n' "$1" "$2" "$3" "$4"; }
run() { setsid -f sh -c "$1" >/dev/null 2>&1; }

case "${ROFI_INFO:-}" in
    "")
        row "Lock Screen"          system-lock-screen "lock screen hyprlock away"            lock
        row "Restart"              system-reboot      "restart reboot"                       ask:reboot
        row "Shut Down"            system-shutdown    "shut down shutdown poweroff power off" ask:poweroff
        row "Restart into Windows" distributor-logo-windows            "windows reboot boot dual"             ask:windows
        row "Log Out"              system-log-out     "log out logout exit session"          ask:logout
        ;;
    lock) run "hyprlock" ;;
    ask:*)
        action=${ROFI_INFO#ask:}
        printf '\0prompt\x1fConfirm\n'
        printf '\0message\x1fAre you sure? Save your work first.\n'
        row "Yes, continue" dialog-ok     "" "do:$action"
        row "Cancel"        dialog-cancel "" ""
        ;;
    do:reboot)   run "systemctl reboot" ;;
    do:poweroff) run "systemctl poweroff" ;;
    do:windows)  run "sudo -n efibootmgr --bootnext 0003 && systemctl reboot" ;;
    do:logout)   run "hyprctl dispatch 'hl.dsp.exit()'" ;;
esac
