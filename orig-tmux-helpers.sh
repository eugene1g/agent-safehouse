#!/usr/bin/env bash

# Basic API
#   tmux_bg_start command [args...]
#     Start a command in a fresh tmux session and track it as the current one.
#   tmux_bg_wait_for_regex pattern [timeout_secs] [poll_secs]
#   tmux_bg_wait_for_text text [timeout_secs] [poll_secs]
#     Poll the visible tmux screen until it matches.
#   tmux_bg_type_and_wait_visible text [timeout_secs] [poll_secs]
#     Type literal text and wait until it appears on screen.
#   tmux_bg_send_key key_name
#     Send a raw tmux key like Enter, Escape, C-c, or /.
#   tmux_bg_capture
#     Capture the visible screen, using tmux's active screen state for TUIs.
#
# Typical flow
#   tmux_bg_start safehouse -- amp
#   tmux_bg_wait_for_regex 'Welcome to Amp'
#   tmux_bg_type_and_wait_visible 'hello'
#   before="$(tmux_bg_capture)"
#   tmux_bg_send_key Enter
#   sleep 6
#   after="$(tmux_bg_capture)"
#
# This helper tracks a single current tmux session per shell execution. Do not
# use it for concurrent tmux jobs within the same shell.

if [[ -z "${TMUX_BG_HELPER_LOADED:-}" ]]; then
  TMUX_BG_HELPER_LOADED=1
  TMUX_BG_CLEANUP_TRAP_INSTALLED=0
  TMUX_BG_PREVIOUS_EXIT_TRAP_BODY=""
  TMUX_BG_CURRENT_SESSION=""
  TMUX_BG_SESSIONS=()
fi

tmux_bg_unique_name() {
  local prefix="${1:-tmux-bg}"

  printf '%s-%s-%s-%s\n' "${prefix}" "$(date +%s)" "$$" "$RANDOM"
}

tmux_bg_has_visible_content() {
  local capture_output="${1:-}"

  [[ -n "${capture_output}" ]] || return 1
  [[ -n "$(printf '%s' "${capture_output}" | tr -d '[:space:]')" ]]
}

tmux_bg_shell_join() {
  local word=""

  for word in "$@"; do
    printf '%q ' "${word}"
  done
}

tmux_bg_register_session() {
  local session_name="$1"
  local existing=""

  for existing in "${TMUX_BG_SESSIONS[@]-}"; do
    [[ "${existing}" == "${session_name}" ]] && return 0
  done

  TMUX_BG_SESSIONS+=("${session_name}")
  TMUX_BG_CURRENT_SESSION="${session_name}"
}

tmux_bg_unregister_session() {
  local session_name="$1"
  local remaining=()
  local existing=""

  for existing in "${TMUX_BG_SESSIONS[@]-}"; do
    [[ "${existing}" == "${session_name}" ]] && continue
    remaining+=("${existing}")
  done

  if ((${#remaining[@]} > 0)); then
    TMUX_BG_SESSIONS=("${remaining[@]}")
  else
    TMUX_BG_SESSIONS=()
  fi

  if [[ "${TMUX_BG_CURRENT_SESSION:-}" == "${session_name}" ]]; then
    if ((${#TMUX_BG_SESSIONS[@]} > 0)); then
      TMUX_BG_CURRENT_SESSION="${TMUX_BG_SESSIONS[${#TMUX_BG_SESSIONS[@]}-1]}"
    else
      TMUX_BG_CURRENT_SESSION=""
    fi
  fi
}

tmux_bg_require_current_session() {
  [[ -n "${TMUX_BG_CURRENT_SESSION:-}" ]] || {
    printf 'tmux helper requires an active current session\n' >&2
    return 1
  }
}

tmux_bg_start() {
  local session_name=""
  local command_string=""

  [[ $# -gt 0 ]] || {
    printf 'usage: tmux_bg_start command [args...]\n' >&2
    return 1
  }

  session_name="$(tmux_bg_unique_name tmux-bg)"
  command_string="$(tmux_bg_shell_join "$@")"
  tmux_bg_install_cleanup_trap

  tmux new-session -d -s "${session_name}" -c "${PWD}" "${command_string}"
  # Keep the pane visible after the process exits so callers can still capture
  # the final screen contents instead of racing a pane that disappeared.
  tmux set-option -t "${session_name}" remain-on-exit on >/dev/null
  tmux_bg_register_session "${session_name}"
}

tmux_bg_capture() {
  local normal_output=""
  local alt_output=""
  local alternate_on="0"

  tmux_bg_require_current_session || return 1

  normal_output="$(tmux capture-pane -p -J -N -t "${TMUX_BG_CURRENT_SESSION}" 2>/dev/null || true)"
  alt_output="$(tmux capture-pane -a -p -J -N -t "${TMUX_BG_CURRENT_SESSION}" 2>/dev/null || true)"
  alternate_on="$(tmux display-message -p -t "${TMUX_BG_CURRENT_SESSION}" '#{alternate_on}' 2>/dev/null || printf '0')"

  # Prefer tmux's reported active screen, but fall back because some TUIs still
  # expose the visible content through the normal capture buffer.
  if [[ "${alternate_on}" == "1" ]]; then
    if tmux_bg_has_visible_content "${alt_output}"; then
      printf '%s\n' "${alt_output}"
    else
      printf '%s\n' "${normal_output}"
    fi
  else
    if tmux_bg_has_visible_content "${normal_output}"; then
      printf '%s\n' "${normal_output}"
    else
      printf '%s\n' "${alt_output}"
    fi
  fi
}

tmux_bg_send_text() {
  local input_text="${1:-}"

  tmux_bg_require_current_session || return 1
  [[ -n "${input_text}" ]] || {
    printf 'usage: tmux_bg_send_text input_text\n' >&2
    return 1
  }

  tmux send-keys -t "${TMUX_BG_CURRENT_SESSION}" -l -- "${input_text}"
}

tmux_bg_send_key() {
  local key_name="${1:-}"

  tmux_bg_require_current_session || return 1

  [[ -n "${key_name}" ]] || {
    printf 'usage: tmux_bg_send_key key_name\n' >&2
    return 1
  }

  tmux send-keys -t "${TMUX_BG_CURRENT_SESSION}" "${key_name}"
}

tmux_bg_wait_until_grep() {
  local timeout_secs="${1:-10}"
  local poll_secs="${2:-0.5}"
  local timeout_label="${3:-match}"
  local deadline=0
  local output=""
  local -a grep_args=()

  shift 3
  grep_args=("$@")

  tmux_bg_require_current_session || return 1

  deadline="$(( $(date +%s) + timeout_secs ))"

  while true; do
    output="$(tmux_bg_capture 2>/dev/null || true)"

    if printf '%s\n' "${output}" | grep "${grep_args[@]}"; then
      return 0
    fi

    if (( $(date +%s) >= deadline )); then
      printf 'timed out after %ss waiting for %s in %s\n' "${timeout_secs}" "${timeout_label}" "${TMUX_BG_CURRENT_SESSION}" >&2
      printf '%s\n' 'last tmux output:' >&2
      printf '%s\n' "${output}" >&2
      return 1
    fi

    sleep "${poll_secs}"
  done
}

tmux_bg_wait_for_text() {
  local expected_text="${1:-}"
  local timeout_secs="${2:-10}"
  local poll_secs="${3:-0.5}"

  [[ -n "${expected_text}" ]] || {
    printf 'usage: tmux_bg_wait_for_text expected_text [timeout_secs] [poll_secs]\n' >&2
    return 1
  }

  tmux_bg_wait_until_grep "${timeout_secs}" "${poll_secs}" "text" -Fq -- "${expected_text}"
}

tmux_bg_type_and_wait_visible() {
  local input_text="${1:-}"
  local timeout_secs="${2:-5}"
  local poll_secs="${3:-0.2}"

  [[ -n "${input_text}" ]] || {
    printf 'usage: tmux_bg_type_and_wait_visible input_text [timeout_secs] [poll_secs]\n' >&2
    return 1
  }

  tmux_bg_send_text "${input_text}"
  tmux_bg_wait_for_text "${input_text}" "${timeout_secs}" "${poll_secs}"
}

tmux_bg_wait_for_regex() {
  local pattern="${1:-}"
  local timeout_secs="${2:-10}"
  local poll_secs="${3:-0.5}"

  [[ -n "${pattern}" ]] || {
    printf 'usage: tmux_bg_wait_for_regex pattern [timeout_secs] [poll_secs]\n' >&2
    return 1
  }

  tmux_bg_wait_until_grep "${timeout_secs}" "${poll_secs}" "/${pattern}/" -Eq -- "${pattern}"
}

tmux_bg_stop() {
  local session_name="${TMUX_BG_CURRENT_SESSION:-}"

  tmux_bg_require_current_session || return 1

  if tmux has-session -t "${session_name}" >/dev/null 2>&1; then
    tmux kill-session -t "${session_name}" >/dev/null 2>&1 || true
  fi

  tmux_bg_unregister_session "${session_name}"
}

tmux_bg_cleanup() {
  local session_name=""

  for session_name in "${TMUX_BG_SESSIONS[@]-}"; do
    tmux kill-session -t "${session_name}" >/dev/null 2>&1 || true
  done

  TMUX_BG_CURRENT_SESSION=""
  TMUX_BG_SESSIONS=()
}

tmux_bg_run_exit_trap() {
  local exit_status=$?

  tmux_bg_cleanup

  if [[ -n "${TMUX_BG_PREVIOUS_EXIT_TRAP_BODY:-}" ]]; then
    eval "${TMUX_BG_PREVIOUS_EXIT_TRAP_BODY}"
  fi

  return "${exit_status}"
}

tmux_bg_install_cleanup_trap() {
  local existing_exit_trap=""
  local quoted_command=""

  [[ "${TMUX_BG_CLEANUP_TRAP_INSTALLED}" == "1" ]] && return 0
  existing_exit_trap="$(trap -p EXIT || true)"

  if [[ -n "${existing_exit_trap}" ]]; then
    # trap -p returns a shell-quoted command body. Preserve that body so we can
    # chain the caller's original EXIT trap after tmux cleanup.
    quoted_command="${existing_exit_trap#trap -- }"
    quoted_command="${quoted_command% EXIT}"
    eval "TMUX_BG_PREVIOUS_EXIT_TRAP_BODY=${quoted_command}"
  else
    TMUX_BG_PREVIOUS_EXIT_TRAP_BODY=""
  fi

  trap 'tmux_bg_run_exit_trap' EXIT
  TMUX_BG_CLEANUP_TRAP_INSTALLED=1
}

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
  set -euo pipefail

  pattern="${1:-READY}"
  timeout_secs="${2:-10}"

  tmux_bg_start \
    bash -lc 'printf "starting\n"; sleep 2; printf "READY\n"; sleep 30'

  tmux_bg_wait_for_regex "${pattern}" "${timeout_secs}"
  printf 'matched /%s/ in %s\n' "${pattern}" "${TMUX_BG_CURRENT_SESSION}"

  tmux_bg_stop
fi
