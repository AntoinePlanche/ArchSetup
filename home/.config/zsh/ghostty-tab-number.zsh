# Ghostty: title each tab with its position (1, 2, 3, …) instead of cwd/command.
# Ghostty has no tab-index option, so: the tab's root process is the ancestor whose
# parent is the ghostty process, and tabs are ranked by that root's start time
# (new tabs open at the end: window-new-tab-position = end). When a tab closes it
# pokes the other tabs (SIGUSR1) so they renumber right away.
# Limits: dragging tabs or several windows in one Ghostty process skew the numbers.

_gtn_dir="${XDG_RUNTIME_DIR:-/tmp}/ghostty-tab-number"

_gtn_find_root() {
  local pid=$$ ppid comm
  while (( pid > 1 )); do
    ppid=$(ps -o ppid= -p $pid 2>/dev/null) || return 1
    ppid=${ppid// /}
    comm=$(ps -o comm= -p $ppid 2>/dev/null)
    if [[ $comm == ghostty ]]; then
      _gtn_ghostty=$ppid _gtn_root=$pid
      return 0
    fi
    pid=$ppid
  done
  return 1
}

_gtn_update() {
  local -a tabs
  tabs=(${(f)"$(ps --ppid $_gtn_ghostty -o pid= --sort=start_time 2>/dev/null)"})
  tabs=(${tabs// /})
  local n=${tabs[(ie)$_gtn_root]}
  (( n <= $#tabs )) && print -Pn "\e]2;$n\a" > /dev/tty
}

_gtn_poke_others() {
  rm -f "$_gtn_dir/$$"
  local f
  for f in "$_gtn_dir"/*(N); do
    kill -USR1 ${f:t} 2>/dev/null || rm -f "$f"
  done
}

if [[ -o interactive ]] && _gtn_find_root; then
  mkdir -p "$_gtn_dir" && : > "$_gtn_dir/$$"
  autoload -Uz add-zsh-hook
  add-zsh-hook precmd  _gtn_update   # re-assert after programs (nvim, ssh…) change it
  add-zsh-hook preexec _gtn_update
  add-zsh-hook zshexit _gtn_poke_others
  TRAPUSR1() { _gtn_update }
  TRAPHUP()  { _gtn_poke_others; exit 129 }  # closing the tab sends SIGHUP
fi
