# shellcheck shell=bash
# Secure Boot with your own keys (sbctl), Microsoft keys kept (-m) for Windows and GPU option ROMs.
# Keys can only be enrolled while the firmware is in Setup Mode; if it isn't, the first-login
# wizard walks you through it (reboot to firmware -> reset/clear keys -> back -> enroll).
# Once enrolled, sbctl's pacman hook and mkinitcpio post hook re-sign everything on updates.

SB_FILES=(
    /boot/EFI/systemd/systemd-bootx64.efi
    /boot/EFI/BOOT/BOOTX64.EFI
    /boot/EFI/Linux/arch-linux-cachyos.efi
    /boot/EFI/Linux/arch-linux-cachyos-lts.efi
)

# Read straight from the EFI variables: no root needed (the wizard checks this at every login)
EFI_GLOBAL=8be4df61-93ca-11d2-aa0d-00e098032b8c
efivar_byte() { od -An -tu1 "/sys/firmware/efi/efivars/$1-$EFI_GLOBAL" 2>/dev/null | awk '{print $NF}'; }
sb_setup_mode() { [[ $(efivar_byte SetupMode) == 1 ]]; }
sb_enabled()    { [[ $(efivar_byte SecureBoot) == 1 ]]; }
sb_keys_exist() { sudo test -f /var/lib/sbctl/keys/PK/PK.pem; }
# Our Platform Key is the one in the firmware (not just created on disk). The public cert is
# cached in ~/.config/arch-setup so this needs no root either.
SB_PK_CERT="$CONF_DIR/secureboot-PK.der"
sb_cache_cert() { sudo openssl x509 -in /var/lib/sbctl/keys/PK/PK.pem -outform DER >"$SB_PK_CERT.tmp" && mv "$SB_PK_CERT.tmp" "$SB_PK_CERT"; }
sb_enrolled() {
    [[ -s $SB_PK_CERT ]] || return 1
    local der; der=$(od -An -tx1 -v "$SB_PK_CERT" | tr -d ' \n')
    [[ -n $der ]] && od -An -tx1 -v "/sys/firmware/efi/efivars/PK-$EFI_GLOBAL" 2>/dev/null | tr -d ' \n' | grep -q "$der"
}

step_secureboot() {
    title "Secure Boot"
    if is_vm; then warn "Virtual machine: Secure Boot skipped"; return 0; fi
    pkg_install sbctl

    sb_keys_exist || sudo sbctl create-keys >>"$LOG" 2>&1 || die "sbctl create-keys failed"
    sb_cache_cert
    sign_boot_files

    if sb_enrolled; then
        conf_set SECUREBOOT enrolled
        if sb_enabled; then ok "Secure Boot is on, with your keys"; else warn "Keys enrolled but Secure Boot is off: enable it in the firmware"; fi
    elif sb_setup_mode; then
        sudo sbctl enroll-keys --microsoft >>"$LOG" 2>&1 || die "sbctl enroll-keys failed, see $LOG"
        ok "Keys enrolled (yours + Microsoft)."
        sb_enabled || warn "Secure Boot is still OFF: switch it on in the firmware. The wizard reminds you (step 3/3)."
        conf_set SECUREBOOT enrolled
    else
        warn "Firmware is not in Setup Mode: keys created and files signed. Secure Boot stays OFF for now;"
        warn "the first-login wizard takes you through it (step 1/3 → 3/3, with firmware menu hints)."
        conf_set SECUREBOOT pending
    fi
}

sign_boot_files() {
    # Signed copy of systemd-boot that `bootctl install/update` picks up automatically
    sudo sbctl sign -s -o /usr/lib/systemd/boot/efi/systemd-bootx64.efi.signed /usr/lib/systemd/boot/efi/systemd-bootx64.efi >>"$LOG" 2>&1
    sudo bootctl update --graceful >>"$LOG" 2>&1 || true
    local f
    for f in "${SB_FILES[@]}"; do
        root_test -f "$f" && { sudo sbctl sign -s "$f" >>"$LOG" 2>&1 || warn "Could not sign $f"; }
    done
    ok "Signed: $(sudo sbctl list-files 2>/dev/null | grep -c '^/') boot files (re-signed automatically on updates)"
}
