
# Kiro CLI pre block. Keep at the top of this file.
[[ -f "${HOME}/.local/share/kiro-cli/shell/zprofile.pre.zsh" ]] && builtin source "${HOME}/.local/share/kiro-cli/shell/zprofile.pre.zsh"

# ~/.zprofile — read once by login shells. SDDM starts Hyprland through a zsh
# login shell, so everything exported here reaches the whole desktop session
# (terminals, apps launched from Hyprland, rofi...). Changes need a re-login.

# Set PATH here, not in .zshenv: /etc/profile (sourced by /etc/zsh/zprofile)
# rebuilds PATH for login shells.
path=("$HOME/.local/bin" $path)
export PATH

export EDITOR="code --wait"
export AWS_PROFILE="antplc-dev"
export AWS_DEFAULT_REGION="us-west-2"

# Machine-specific variables (GPU driver env...), written by arch-setup, not in git
[[ -f ~/.config/zsh/local.zprofile ]] && source ~/.config/zsh/local.zprofile


# Kiro CLI post block. Keep at the bottom of this file.
[[ -f "${HOME}/.local/share/kiro-cli/shell/zprofile.post.zsh" ]] && builtin source "${HOME}/.local/share/kiro-cli/shell/zprofile.post.zsh"
