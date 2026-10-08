#!/bin/bash

sock="$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock"

socat -U - UNIX-CONNECT:"$sock" | while read -r line; do
    case "$line" in
        fullscreen\>\>1|fullscreen\>\>0)
            pkill -SIGUSR1 -x waybar
            ;;
    esac
done