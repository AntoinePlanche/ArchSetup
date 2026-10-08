# shellcheck shell=bash
# Same packages as the original machine (packages/*.txt), plus the optional groups chosen in preflight.

step_packages() {
    title "Packages"
    local lists=(base desktop apps) g
    for g in gaming llm vpn legacy; do has_opt "$g" && lists+=("opt-$g"); done
    [[ $(conf_get DUALBOOT) != none ]] && lists+=(opt-dualboot)
    info "Repo packages: ${lists[*]}"

    local all aur
    mapfile -t all < <(pkglist "${lists[@]}")
    mapfile -t aur < <(pkglist aur)
    has_opt vpn && mapfile -t -O "${#aur[@]}" aur < <(pkglist opt-vpn)
    pkg_install "${all[@]}" "${aur[@]}"
    ok "$(pacman -Qq | wc -l) packages installed"
}
