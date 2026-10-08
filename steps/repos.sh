# shellcheck shell=bash
# CachyOS repositories (picks the znver4 / v4 / v3 optimized repos for this CPU) and the AUR helpers.

step_repos() {
    title "CachyOS repositories"
    if grep -q '^\[cachyos' /etc/pacman.conf; then
        ok "Already configured: $(grep -o '^\[cachyos[^]]*\]' /etc/pacman.conf | paste -sd' ')"
    else
        # Official installer: detects the CPU level, imports the key, installs keyring + mirrorlists
        local tmp; tmp=$(mktemp -d)
        curl -fsSL https://mirror.cachyos.org/cachyos-repo.tar.xz -o "$tmp/repo.tar.xz" || die "Cannot download the CachyOS repo installer"
        tar -xf "$tmp/repo.tar.xz" -C "$tmp"
        (cd "$tmp/cachyos-repo" && yes | sudo ./cachyos-repo.sh) >>"$LOG" 2>&1 || die "cachyos-repo.sh failed, see $LOG"
        rm -rf "$tmp"
        ok "Added: $(grep -o '^\[cachyos[^]]*\]' /etc/pacman.conf | paste -sd' ')"
    fi
    # Full upgrade so everything is rebuilt against the CachyOS toolchain (e.g. llvm-libs)
    sudo pacman -Syu --noconfirm >>"$LOG" 2>&1 || die "System upgrade failed, see $LOG"

    # AUR helpers from the CachyOS repo (no manual makepkg). paru is the one used here,
    # yay is the one used by ~/.local/bin/auto-update.sh.
    pkg_install paru yay
    # rust: rustup, never extra/rust (breaks against CachyOS llvm-libs)
    pacman -Qq rust &>/dev/null && sudo pacman -Rdd --noconfirm rust >>"$LOG" 2>&1
    pkg_install rustup
    rustup default stable >>"$LOG" 2>&1 || warn "rustup default stable failed"
    ok "paru, yay and rustup ready"
}
