# shellcheck shell=bash
# Tools that are not packages, user directories, and the hand-off to the first-login wizard.

step_extras() {
    title "Extras"
    # omp (oh-my-pi): standalone binary in ~/.local/bin, updated by auto-update.sh
    if [[ ! -x $HOME/.local/bin/omp ]]; then
        curl -fsSL https://omp.sh/install | sh -s -- --binary >>"$LOG" 2>&1 && ok "omp installed" || warn "omp install failed (curl -fsSL https://omp.sh/install | sh -s -- --binary)"
    fi
    has_opt llm && mkdir -p "$HOME/llm/models"
    xdg-user-dirs-update 2>/dev/null || true

    # Wizard state: start fresh on a new machine
    rm -f "$STATE_DIR/wizard/dismissed"
    ok "First-login wizard armed (autostarted by hyprland.lua)"
    cat <<'TXT'
  Not automated (install them by hand if you still use them):
    kiro-cli / q, hermes agent (~/.hermes venv), agy, cua-driver
TXT
}
