
# Kiro CLI pre block. Keep at the top of this file.
[[ -f "${HOME}/.local/share/kiro-cli/shell/zshrc.pre.zsh" ]] && builtin source "${HOME}/.local/share/kiro-cli/shell/zshrc.pre.zsh"

# Workaround: kiro-cli-term launch is blocked on Linux due to process ancestry detection bug.
# Force launch it manually if it isn't already running.
if [[ -z "$Q_TERM" ]] && [[ -t 1 ]] && command -v kiro-cli-term &>/dev/null; then
  Q_SHELL=/usr/bin/zsh exec -a "zsh (kiro-cli-term)" kiro-cli-term
fi

# ~/.zshrc — read by interactive shells only: prompt, plugins, aliases,
# options, key bindings. Environment variables live in ~/.zprofile.

export ZSH="$HOME/.oh-my-zsh"
ZSH_THEME="agnoster"
# Tab titles are handled by ghostty-tab-number.zsh (sourced below)
DISABLE_AUTO_TITLE="true"
plugins=(git fzf)
source $ZSH/oh-my-zsh.sh

# git
alias gdiff="git diff"
alias gdiff1="git diff HEAD~1 HEAD"
alias gqr="git commit -am \"WIP\""
alias gq="git autocommit -a"
alias ga="git commit --amend -a --no-edit"

# random
alias pbc="pbcopy"

gri() {
  if [ -z "$1" ]; then
    git rebase -i HEAD~1
  else
    git rebase -i HEAD~$1
  fi
}

# kubectl
alias kgp="kubectl get pods"
alias kgn="kubectl get nodes"
alias kl="kubectl logs"

alias q="kiro-cli --v3"

# Ghostty: number tabs 1, 2, 3, …
source ~/.config/zsh/ghostty-tab-number.zsh

setopt SHARE_HISTORY

bindkey "^[r" fzf-history-widget


# First terminal after login (Hyprland starts it with FASTFETCH_ON_START=1): show fastfetch.
# Near the end so it runs inside Kiro's shell wrapper (kiro-cli-term), not before it.
if [[ -n $FASTFETCH_ON_START ]]; then
  unset FASTFETCH_ON_START
  fastfetch
fi

# Local LLM: llama-server (systemd user unit, Qwen3.6 on the 9070 XT)
# ai                -> start llama-server if needed, wait until ready
#                      (OpenAI-compatible API: http://127.0.0.1:8080/v1, model qwen3.6-35b-a3b)
# llmstop           -> stop llama-server and free the GPU (e.g. before gaming)
ai() {
  if ! curl -sf http://127.0.0.1:8080/health >/dev/null; then
    echo "Starting llama-server..."
    systemctl --user start llama-server || return 1
    until curl -sf http://127.0.0.1:8080/health >/dev/null; do
      systemctl --user is-active -q llama-server || { echo "llama-server failed: journalctl --user -u llama-server"; return 1; }
      sleep 1
    done
  fi
  echo "llama-server ready: http://127.0.0.1:8080/v1 (model: qwen3.6-35b-a3b)"
}
alias llmstop='systemctl --user stop llama-server && echo "llama-server stopped, GPU freed"'

# Kiro CLI post block. Keep at the bottom of this file.
[[ -f "${HOME}/.local/share/kiro-cli/shell/zshrc.post.zsh" ]] && builtin source "${HOME}/.local/share/kiro-cli/shell/zshrc.post.zsh"

