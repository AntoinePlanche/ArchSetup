# shellcheck shell=bash
# Drivers for the hardware that is actually present (GPU, Wi-Fi, Bluetooth, laptop power, VM guest tools).
# Machine-specific session variables go to ~/.config/zsh/local.zprofile (sourced by .zprofile, not in git).

LOCAL_ZPROFILE="$HOME/.config/zsh/local.zprofile"

step_drivers() {
    title "Drivers"
    local pkgs=() env=() v
    local gaming=0; has_opt gaming && gaming=1

    for v in $(gpu_vendors); do
        case $v in
            amd)
                pkgs+=(mesa vulkan-radeon rocm-smi-lib)
                ((gaming)) && pkgs+=(lib32-mesa lib32-vulkan-radeon)
                ok "AMD GPU: Mesa RADV" ;;
            intel)
                pkgs+=(mesa vulkan-intel intel-media-driver)
                ((gaming)) && pkgs+=(lib32-mesa lib32-vulkan-intel)
                ok "Intel GPU: Mesa ANV + VA-API" ;;
            nvidia)
                case $(nvidia_branch) in
                    open)
                        # Prebuilt CachyOS modules matching both kernels, no DKMS build
                        pkgs+=(linux-cachyos-nvidia-open linux-cachyos-lts-nvidia-open nvidia-utils)
                        ((gaming)) && pkgs+=(lib32-nvidia-utils) ;;
                    580xx)
                        warn "Maxwell/Pascal/Volta NVIDIA GPU: legacy 580xx driver (DKMS, built for both kernels)"
                        pkgs+=(nvidia-580xx-dkms nvidia-580xx-utils linux-cachyos-headers linux-cachyos-lts-headers)
                        ((gaming)) && pkgs+=(lib32-nvidia-580xx-utils) ;;
                    470xx)
                        warn "Kepler NVIDIA GPU: legacy 470xx driver. Hyprland on it is barely usable (no GBM fixes);"
                        warn "if there is an integrated GPU, plug the screen there."
                        pkgs+=(nvidia-470xx-dkms nvidia-470xx-utils linux-cachyos-headers linux-cachyos-lts-headers)
                        ((gaming)) && pkgs+=(lib32-nvidia-470xx-utils) ;;
                esac
                pkgs+=(egl-wayland libva-nvidia-driver)
                [[ $(nvidia_branch) == open ]] && pkgs+=(nvidia-settings) || pkgs+=("nvidia-$(nvidia_branch)-settings")
                env+=("LIBVA_DRIVER_NAME=nvidia" "__GLX_VENDOR_LIBRARY_NAME=nvidia" "NVD_BACKEND=direct")
                ok "NVIDIA GPU: proprietary driver" ;;
        esac
    done
    # Hybrid laptop: render on the iGPU, `prime-run app` for the dGPU
    if [[ $(gpu_vendors | wc -l) -gt 1 ]] && gpu_vendors | grep -qx nvidia; then
        pkgs+=(nvidia-prime)
        ok "Hybrid graphics: use 'prime-run <app>' for the NVIDIA GPU"
    fi

    if has_bluetooth; then pkgs+=(bluez bluez-utils blueman); ok "Bluetooth"; fi
    if has_broadcom_wifi; then pkgs+=(broadcom-wl-dkms); ok "Broadcom Wi-Fi (broadcom-wl)"; fi
    if is_laptop; then
        # Battery (quickshell Battery.qml reads UPower), brightness keys, power profiles
        pkgs+=(upower power-profiles-daemon brightnessctl)
        ok "Laptop: UPower, power-profiles-daemon, brightnessctl"
    fi
    if is_vm; then
        case $(virt_kind) in
            kvm|qemu) pkgs+=(qemu-guest-agent spice-vdagent) ;;
            oracle)   pkgs+=(virtualbox-guest-utils) ;;
            vmware)   pkgs+=(open-vm-tools) ;;
        esac
        env+=("WLR_NO_HARDWARE_CURSORS=1")
        ok "Virtual machine ($(virt_kind)): guest tools"
    fi

    pkg_install "${pkgs[@]}"

    has_bluetooth && sudo systemctl enable --now bluetooth.service >>"$LOG" 2>&1
    is_laptop && sudo systemctl enable --now power-profiles-daemon.service >>"$LOG" 2>&1
    case $(virt_kind) in kvm|qemu) sudo systemctl enable qemu-guest-agent.service >>"$LOG" 2>&1 || true ;; esac

    if gpu_vendors | grep -qx nvidia; then
        sudo sed -i 's/^MODULES=(.*)/MODULES=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)/' /etc/mkinitcpio.conf
        sudo mkinitcpio -P >>"$LOG" 2>&1 || die "mkinitcpio failed after adding the NVIDIA modules, see $LOG"
        ok "NVIDIA modules in the initramfs"
    fi

    mkdir -p "$(dirname "$LOCAL_ZPROFILE")"
    {
        echo "# Machine-specific session variables, written by ArchSetup steps/drivers.sh (not in git)"
        for v in "${env[@]}"; do echo "export $v"; done
    } >"$LOCAL_ZPROFILE"
}
