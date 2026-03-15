#!/usr/bin/env bash

# Low-level tmux API
#   sft_tmux_start_session command [args...]
#   sft_tmux_capture
#   sft_tmux_send_text text
#   sft_tmux_send_keys key [key ...]
#   sft_tmux_wait_until text [timeout_secs] [poll_secs]
#   sft_tmux_wait_until_regex pattern [timeout_secs] [poll_secs]
#   sft_tmux_wait_until_compact_text text [timeout_secs] [poll_secs]
#   sft_tmux_matches_regex pattern
#   sft_tmux_type_and_wait_visible text [timeout_secs] [poll_secs]
#   sft_tmux_stop
#   sft_tmux_cleanup
#
# This helper tracks a single current tmux session per shell execution. Do not
# use it for concurrent tmux jobs within the same shell.

if [[ -z "${SFT_TMUX_HELPER_LOADED:-}" ]]; then
  SFT_TMUX_HELPER_LOADED=1
  SFT_TMUX_CURRENT_SESSION=""
fi

sft_tmux_unique_name() {
  local prefix="${1:-tmux-bg}"

  printf '%s-%s-%s-%s\n' "${prefix}" "$(date +%s)" "$$" "$RANDOM"
}

sft_tmux_shell_join() {
  local word=""

  for word in "$@"; do
    printf '%q ' "${word}"
  done
}

sft_tmux_capture_normal() {
  sft_tmux_require_current_session || return 1
  tmux capture-pane -p -J -N -t "${SFT_TMUX_CURRENT_SESSION}" 2>/dev/null || true
}

sft_tmux_capture_alternate() {
  sft_tmux_require_current_session || return 1
  tmux capture-pane -a -p -J -N -t "${SFT_TMUX_CURRENT_SESSION}" 2>/dev/null || true
}

sft_tmux_capture_score() {
  local capture_output="${1:-}"

  [[ -n "${capture_output}" ]] || {
    printf '0\n'
    return 0
  }

  printf '%s' "${capture_output}" | tr -d '[:space:]' | wc -c | tr -d '[:space:]'
}

sft_tmux_has_visible_content() {
  local capture_output="${1:-}"

  [[ -n "${capture_output}" ]] || return 1
  [[ -n "$(printf '%s' "${capture_output}" | tr -d '[:space:]')" ]]
}

sft_tmux_select_capture() {
  local normal_output="${1:-}"
  local alt_output="${2:-}"
  local normal_score=0
  local alt_score=0

  normal_score="$(sft_tmux_capture_score "${normal_output}")"
  alt_score="$(sft_tmux_capture_score "${alt_output}")"

  if (( alt_score > normal_score )); then
    printf '%s\n' "${alt_output}"
  elif sft_tmux_has_visible_content "${normal_output}"; then
    printf '%s\n' "${normal_output}"
  else
    printf '%s\n' "${alt_output}"
  fi
}

sft_tmux_output_matches_grep() {
  local capture_output="${1:-}"

  shift
  [[ -n "${capture_output}" ]] || return 1
  printf '%s\n' "${capture_output}" | grep "$@"
}

sft_tmux_outputs_match_grep() {
  local normal_output="${1:-}"
  local alt_output="${2:-}"

  shift 2
  sft_tmux_output_matches_grep "${normal_output}" "$@" && return 0
  [[ "${alt_output}" != "${normal_output}" ]] || return 1
  sft_tmux_output_matches_grep "${alt_output}" "$@"
}

sft_tmux_output_matches_compact_text() {
  local capture_output="${1:-}"
  local compact_needle="${2:-}"
  local compact_output=""

  [[ -n "${capture_output}" ]] || return 1
  compact_output="$(printf '%s' "${capture_output}" | tr -d '[:space:]')"
  [[ "${compact_output}" == *"${compact_needle}"* ]]
}

sft_tmux_outputs_match_compact_text() {
  local normal_output="${1:-}"
  local alt_output="${2:-}"
  local compact_needle="${3:-}"

  sft_tmux_output_matches_compact_text "${normal_output}" "${compact_needle}" && return 0
  [[ "${alt_output}" != "${normal_output}" ]] || return 1
  sft_tmux_output_matches_compact_text "${alt_output}" "${compact_needle}"
}

sft_tmux_log_last_output() {
  local normal_output="${1:-}"
  local alt_output="${2:-}"
  local best_output=""

  if [[ "${alt_output}" == "${normal_output}" ]]; then
    printf '%s\n' 'last tmux output:' >&2
    printf '%s\n' "${normal_output}" >&2
    return 0
  fi

  best_output="$(sft_tmux_select_capture "${normal_output}" "${alt_output}")"
  printf '%s\n' 'last tmux output (best capture):' >&2
  printf '%s\n' "${best_output}" >&2

  if sft_tmux_has_visible_content "${normal_output}"; then
    printf '%s\n' 'last tmux normal output:' >&2
    printf '%s\n' "${normal_output}" >&2
  fi

  if sft_tmux_has_visible_content "${alt_output}"; then
    printf '%s\n' 'last tmux alternate output:' >&2
    printf '%s\n' "${alt_output}" >&2
  fi
}

sft_tmux_require_current_session() {
  [[ -n "${SFT_TMUX_CURRENT_SESSION:-}" ]] || {
    printf 'tmux helper requires an active current session\n' >&2
    return 1
  }
}

sft_tmux_create_session_named() {
  local session_name="${1:-}"
  local workdir="${2:-${PWD}}"

  [[ -n "${session_name}" ]] || {
    printf 'usage: sft_tmux_create_session_named session_name [workdir]\n' >&2
    return 1
  }

  if tmux has-session -t "${session_name}" >/dev/null 2>&1; then
    tmux kill-session -t "${session_name}" >/dev/null 2>&1 || true
  fi

  tmux new-session -d -s "${session_name}" -c "${workdir}"
  tmux set-option -t "${session_name}" remain-on-exit on >/dev/null
  SFT_TMUX_CURRENT_SESSION="${session_name}"
}

sft_tmux_run() {
  local command_string=""

  sft_tmux_require_current_session || return 1
  [[ $# -gt 0 ]] || {
    printf 'usage: sft_tmux_run command [args...]\n' >&2
    return 1
  }

  command_string="$(sft_tmux_shell_join "$@")"
  tmux respawn-pane -k -t "${SFT_TMUX_CURRENT_SESSION}:0.0" "${command_string}"
}

sft_tmux_start_session() {
  local session_name=""

  [[ $# -gt 0 ]] || {
    printf 'usage: sft_tmux_start_session command [args...]\n' >&2
    return 1
  }

  session_name="$(sft_tmux_unique_name tmux-bg)"
  sft_tmux_create_session_named "${session_name}" "${PWD}"
  sft_tmux_run "$@"
}

sft_tmux_capture() {
  local normal_output=""
  local alt_output=""

  sft_tmux_require_current_session || return 1

  normal_output="$(sft_tmux_capture_normal 2>/dev/null || true)"
  alt_output="$(sft_tmux_capture_alternate 2>/dev/null || true)"
  sft_tmux_select_capture "${normal_output}" "${alt_output}"
}

sft_tmux_send_text() {
  local input_text="${1:-}"

  sft_tmux_require_current_session || return 1
  [[ -n "${input_text}" ]] || {
    printf 'usage: sft_tmux_send_text input_text\n' >&2
    return 1
  }

  tmux send-keys -t "${SFT_TMUX_CURRENT_SESSION}" -l -- "${input_text}"
}

sft_tmux_send_keys() {
  local key_name=""

  sft_tmux_require_current_session || return 1
  (($# > 0)) || {
    printf 'usage: sft_tmux_send_keys key [key ...]\n' >&2
    return 1
  }

  for key_name in "$@"; do
    tmux send-keys -t "${SFT_TMUX_CURRENT_SESSION}" "${key_name}"
  done
}

sft_tmux_current_pane_dead() {
  sft_tmux_require_current_session || return 1
  [[ "$(tmux display-message -p -t "${SFT_TMUX_CURRENT_SESSION}" '#{pane_dead}' 2>/dev/null || printf '1')" == "1" ]]
}

_sft_tmux_wait_until_grep() {
  local timeout_secs="${1:-20}"
  local poll_secs="${2:-0.2}"
  local timeout_label="${3:-match}"
  local deadline=0
  local normal_output=""
  local alt_output=""
  local -a grep_args=()

  shift 3
  grep_args=("$@")

  sft_tmux_require_current_session || return 1
  deadline="$(( $(date +%s) + timeout_secs ))"

  while true; do
    normal_output="$(sft_tmux_capture_normal 2>/dev/null || true)"
    alt_output="$(sft_tmux_capture_alternate 2>/dev/null || true)"

    if sft_tmux_outputs_match_grep "${normal_output}" "${alt_output}" "${grep_args[@]}"; then
      return 0
    fi

    if sft_tmux_current_pane_dead; then
      printf 'tmux pane exited while waiting for %s in %s\n' "${timeout_label}" "${SFT_TMUX_CURRENT_SESSION}" >&2
      sft_tmux_log_last_output "${normal_output}" "${alt_output}"
      return 1
    fi

    if (( $(date +%s) >= deadline )); then
      printf 'timed out after %ss waiting for %s in %s\n' "${timeout_secs}" "${timeout_label}" "${SFT_TMUX_CURRENT_SESSION}" >&2
      sft_tmux_log_last_output "${normal_output}" "${alt_output}"
      return 1
    fi

    sleep "${poll_secs}"
  done
}

sft_tmux_wait_until() {
  local needle="${1:-}"
  local timeout_secs="${2:-10}"
  local poll_secs="${3:-0.2}"

  [[ -n "${needle}" ]] || {
    printf 'usage: sft_tmux_wait_until text [timeout_secs] [poll_secs]\n' >&2
    return 1
  }

  _sft_tmux_wait_until_grep "${timeout_secs}" "${poll_secs}" "text" -Fq -- "${needle}"
}

sft_tmux_wait_until_regex() {
  local pattern="${1:-}"
  local timeout_secs="${2:-20}"
  local poll_secs="${3:-0.2}"

  [[ -n "${pattern}" ]] || {
    printf 'usage: sft_tmux_wait_until_regex pattern [timeout_secs] [poll_secs]\n' >&2
    return 1
  }

  _sft_tmux_wait_until_grep "${timeout_secs}" "${poll_secs}" "/${pattern}/" -Eq -- "${pattern}"
}

sft_tmux_wait_until_compact_text() {
  local needle="${1:-}"
  local timeout_secs="${2:-10}"
  local poll_secs="${3:-0.2}"
  local compact_needle=""
  local deadline=0
  local normal_output=""
  local alt_output=""

  [[ -n "${needle}" ]] || {
    printf 'usage: sft_tmux_wait_until_compact_text text [timeout_secs] [poll_secs]\n' >&2
    return 1
  }

  compact_needle="$(printf '%s' "${needle}" | tr -d '[:space:]')"
  sft_tmux_require_current_session || return 1
  deadline="$(( $(date +%s) + timeout_secs ))"

  while true; do
    normal_output="$(sft_tmux_capture_normal 2>/dev/null || true)"
    alt_output="$(sft_tmux_capture_alternate 2>/dev/null || true)"

    if sft_tmux_outputs_match_compact_text "${normal_output}" "${alt_output}" "${compact_needle}"; then
      return 0
    fi

    if sft_tmux_current_pane_dead; then
      printf 'tmux pane exited while waiting for compact text in %s\n' "${SFT_TMUX_CURRENT_SESSION}" >&2
      sft_tmux_log_last_output "${normal_output}" "${alt_output}"
      return 1
    fi

    if (( $(date +%s) >= deadline )); then
      printf 'timed out after %ss waiting for compact text in %s\n' "${timeout_secs}" "${SFT_TMUX_CURRENT_SESSION}" >&2
      sft_tmux_log_last_output "${normal_output}" "${alt_output}"
      return 1
    fi

    sleep "${poll_secs}"
  done
}

sft_tmux_matches_regex() {
  local pattern="${1:-}"
  local normal_output=""
  local alt_output=""

  [[ -n "${pattern}" ]] || {
    printf 'usage: sft_tmux_matches_regex pattern\n' >&2
    return 1
  }

  normal_output="$(sft_tmux_capture_normal 2>/dev/null || true)"
  alt_output="$(sft_tmux_capture_alternate 2>/dev/null || true)"
  sft_tmux_outputs_match_grep "${normal_output}" "${alt_output}" -Eq -- "${pattern}"
}

sft_tmux_type_and_wait_visible() {
  local input_text="${1:-}"
  local timeout_secs="${2:-5}"
  local poll_secs="${3:-0.2}"

  [[ -n "${input_text}" ]] || {
    printf 'usage: sft_tmux_type_and_wait_visible text [timeout_secs] [poll_secs]\n' >&2
    return 1
  }

  sft_tmux_send_text "${input_text}"
  sft_tmux_wait_until "${input_text}" "${timeout_secs}" "${poll_secs}"
}

sft_tmux_kill_process_group() {
  local pane_pid=""
  local pane_pgid=""
  local wait_idx=0

  sft_tmux_require_current_session || return 1
  pane_pid="$(tmux display-message -p -t "${SFT_TMUX_CURRENT_SESSION}" '#{pane_pid}' 2>/dev/null || true)"
  [[ "${pane_pid}" =~ ^[0-9]+$ ]] || return 0

  pane_pgid="$(ps -o pgid= -p "${pane_pid}" 2>/dev/null | tr -d '[:space:]' || true)"
  if [[ "${pane_pgid}" =~ ^[0-9]+$ ]]; then
    kill -TERM -- "-${pane_pgid}" >/dev/null 2>&1 || true
    for wait_idx in {1..10}; do
      kill -0 -- "-${pane_pgid}" >/dev/null 2>&1 || return 0
      sleep 0.1
    done
    kill -KILL -- "-${pane_pgid}" >/dev/null 2>&1 || true
  fi
}

sft_tmux_stop() {
  local session_name="${SFT_TMUX_CURRENT_SESSION:-}"

  [[ -n "${session_name}" ]] || return 0
  sft_tmux_kill_process_group || true
  tmux kill-session -t "${session_name}" >/dev/null 2>&1 || true
  SFT_TMUX_CURRENT_SESSION=""
}

sft_tmux_cleanup() {
  sft_tmux_stop || true
}
