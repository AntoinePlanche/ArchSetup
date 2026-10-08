# shellcheck shell=bash
# Symlink the dotfiles listed in links.txt into $HOME. Anything already there that is not
# the right link is moved to ~/.local/state/arch-setup/backup/<date>/ first.

step_dotfiles() {
    title "Dotfiles (symlinks into $REPO/home)"
    local backup="$STATE_DIR/backup/$(date +%F_%H%M%S)" rel src dst n=0 moved=0
    while read -r rel; do
        rel=${rel%%#*}; rel=${rel%"${rel##*[![:space:]]}"}
        [[ -z $rel ]] && continue
        src="$REPO/home/$rel" dst="$HOME/$rel"
        [[ -e $src ]] || { warn "Missing in repo: home/$rel"; continue; }
        if [[ -L $dst && $(readlink "$dst") == "$src" ]]; then n=$((n + 1)); continue; fi
        if [[ -e $dst || -L $dst ]]; then
            mkdir -p "$backup/$(dirname "$rel")"
            mv "$dst" "$backup/$rel"
            moved=$((moved + 1))
        fi
        mkdir -p "$(dirname "$dst")"
        ln -s "$src" "$dst"
        n=$((n + 1))
    done <"$REPO/links.txt"
    ok "$n links in place"
    ((moved)) && warn "$moved existing files/dirs moved to $backup"
    return 0
}
