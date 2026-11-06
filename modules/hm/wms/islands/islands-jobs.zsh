# Tells the islands bar (shell/Jobs.qml) what this shell is running, so a
# command still going after 10 seconds shows beside the clock, then how it
# ended. One file per shell, $XDG_RUNTIME_DIR/islands/jobs/<pid>, holding a
# line of tab-separated fields: run|end, started, ended, exit code, the
# command with aliases expanded (what the bar matches its ignore list
# against), then the command as typed (what it shows). Builtins write it:
# nothing forks per command, and nothing waits on the bar.
if [[ -o interactive && -n $XDG_RUNTIME_DIR ]] &&
  zmodload zsh/datetime 2>/dev/null &&
  zmodload -F zsh/files b:zf_mkdir b:zf_rm 2>/dev/null; then
  typeset -g _islands_job=$XDG_RUNTIME_DIR/islands/jobs/$$
  typeset -g _islands_job_cmd= _islands_job_expanded= _islands_job_started= _islands_job_stopped=
  zf_mkdir -p ${_islands_job:h} 2>/dev/null

  # The braces quiet a failed write too (the directory gone, say), which a
  # redirection's own 2>/dev/null doesn't
  _islands_job_write() {
    { print -r -- "$1"$'\t'"$_islands_job_started"$'\t'"$2"$'\t'"$3"$'\t'"$_islands_job_expanded"$'\t'"$_islands_job_cmd" >| $_islands_job } 2>/dev/null
  }

  _islands_job_start() {
    # fg after Ctrl+Z carries on with the job it stopped, and its clock
    if [[ -n $_islands_job_stopped && $1 == (fg|fg *|%*) ]]; then
      _islands_job_stopped=
    else
      # On one line: the command's own newlines and tabs become spaces
      _islands_job_cmd=${${1//$'\n'/ }//$'\t'/ }
      _islands_job_expanded=${${2//$'\n'/ }//$'\t'/ }
      _islands_job_started=$EPOCHSECONDS
      _islands_job_stopped=
    fi
    _islands_job_write run
  }

  # A hook sees the command's exit status whatever ran before it
  _islands_job_end() {
    local code=$?
    [[ -n $_islands_job_started ]] || return 0
    _islands_job_write end $EPOCHSECONDS $code
    # 148: stopped by Ctrl+Z, which fg resumes
    if (( code == 148 )); then
      _islands_job_stopped=1
    else
      _islands_job_started=
    fi
  }

  _islands_job_exit() {
    zf_rm -f $_islands_job 2>/dev/null
  }

  autoload -Uz add-zsh-hook
  add-zsh-hook preexec _islands_job_start
  add-zsh-hook precmd _islands_job_end
  add-zsh-hook zshexit _islands_job_exit
fi
