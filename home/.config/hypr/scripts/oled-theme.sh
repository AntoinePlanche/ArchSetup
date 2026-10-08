#!/usr/bin/env bash
# Dark mode while an OLED monitor is connected, light mode otherwise (burn-in care).
# Apps that follow the system theme (VS Code with window.autoDetectColorScheme,
# Chrome "Mode: Device", GTK/libadwaita apps) switch with it through the portal.
#
# Add a monitor by putting part of its description (`hyprctl monitors all`) below.
OLED_MONITORS=(
    "XG27AQWMG" # ASUS ROG Strix 27" WOLED
)

set -u

# One watcher per session
exec 9>"${XDG_RUNTIME_DIR:-/tmp}/oled-theme.lock"
flock -n 9 || exit 0

current=""

apply() {
    local want=light desc
    while IFS= read -r desc; do
        for oled in "${OLED_MONITORS[@]}"; do
            [[ $desc == *"$oled"* ]] && want=dark
        done
    done < <(hyprctl monitors -j | grep -o '"description": *"[^"]*"')

    [[ $want == "$current" ]] && return
    current=$want
    if [[ $want == dark ]]; then
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
        gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita-dark'
        gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Dark'
    else
        gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
        gsettings set org.gnome.desktop.interface gtk-theme 'Adwaita'
        gsettings set org.gnome.desktop.interface icon-theme 'Papirus-Light'
    fi
}

apply
sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"
socat -U - UNIX-CONNECT:"$sock" 9>&- | while read -r line; do
    case $line in
        monitoradded*|monitorremoved*) sleep 0.5; apply ;;
    esac
done
