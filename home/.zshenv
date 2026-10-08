# ~/.zshenv — read by EVERY zsh (scripts, cron, login and interactive shells).
# Keep it minimal: only variables that every zsh needs, no output, no slow commands.

export XDG_CONFIG_HOME="$HOME/.config"

# Drop duplicate PATH entries in every shell (e.g. nested shells re-adding ~/.local/bin)
typeset -U path PATH
