#!/usr/bin/env bash

# E2E harness on top of tmux_utils.bash
#   setup / teardown
#   sft_tmux_start safehouse [safehouse-args ...] -- [ENV=VALUE ...] command [args...]
#   sft_safehouse_run_capture output_file command [args...]
#   sft_agent_tui_add_gate [--before-ready] [--once] pattern [key ...]
#   sft_agent_tui_add_skip_gate pattern reason
#   sft_agent_tui_handle_startup_gates
#   sft_agent_tui_dismiss_gate gate_pattern [key ...]
#   sft_agent_tui_write_screen_capture [normal_output alt_output]
#   sft_tmux_assert_roundtrip

SFT_AGENT_TUI_HELPER_DIR="$(cd -- "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

setup() {
  sft_setup_test_env
  sft_agent_tui_setup_test_env
}

teardown() {
  sft_agent_tui_teardown_test_env
  sft_teardown_test_env
}

sft_agent_tui_setup_test_env() {
  command -v tmux >/dev/null 2>&1 || skip "tmux is required"
  sft_agent_tui_preflight_sandbox_exec_or_skip

  export HOME="${SAFEHOUSE_HOST_HOME:-${HOME:?}}"

  AGENT_TUI_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR:-/tmp}/safehouse-agent-tui-root.XXXXXX")"
  AGENT_TUI_WORKDIR="${AGENT_TUI_ROOT}/workdir"
  AGENT_TUI_SCREEN_PATH="${AGENT_TUI_ROOT}/screen.txt"
  AGENT_TUI_SESSION_NAME=""
  AGENT_TUI_NAME=""
  AGENT_TUI_FAILED=0
  AGENT_TUI_STARTUP_WAIT_SECS="${SAFEHOUSE_AGENT_TUI_STARTUP_WAIT_SECS:-10}"
  AGENT_TUI_RESPONSE_TIMEOUT_SECS="${SAFEHOUSE_AGENT_TUI_RESPONSE_TIMEOUT_SECS:-20}"
  AGENT_TUI_PROMPT_VISIBLE_TIMEOUT_SECS="${SAFEHOUSE_AGENT_TUI_PROMPT_VISIBLE_TIMEOUT_SECS:-5}"
  AGENT_TUI_POLL_INTERVAL_SECS="${SAFEHOUSE_AGENT_TUI_POLL_INTERVAL_SECS:-0.2}"
  AGENT_TUI_GATE_CLEAR_TIMEOUT_SECS="${SAFEHOUSE_AGENT_TUI_GATE_CLEAR_TIMEOUT_SECS:-5}"
  AGENT_TUI_FAILURE_SETTLE_SECS="${SAFEHOUSE_AGENT_TUI_FAILURE_SETTLE_SECS:-2.0}"
  AGENT_TUI_PRE_PROMPT_DELAY_SECS="${SAFEHOUSE_AGENT_TUI_PRE_PROMPT_DELAY_SECS:-0}"
  AGENT_TUI_SUBMIT_DELAY_SECS="${SAFEHOUSE_AGENT_TUI_SUBMIT_DELAY_SECS:-0.3}"
  AGENT_TUI_KEEP_SESSION="${SAFEHOUSE_AGENT_TUI_KEEP_SESSION:-0}"
  AGENT_TUI_KEEP_SESSION_ON_FAIL="${SAFEHOUSE_AGENT_TUI_KEEP_SESSION_ON_FAIL:-0}"
  AGENT_TUI_PRE_PROMPT_KEYS=()
  AGENT_TUI_PROMPT_SEND_MODE="${SAFEHOUSE_AGENT_TUI_PROMPT_SEND_MODE:-bulk}"
  AGENT_TUI_PROMPT_CHAR_DELAY_SECS="${SAFEHOUSE_AGENT_TUI_PROMPT_CHAR_DELAY_SECS:-0.03}"
  AGENT_TUI_SUBMIT_KEYS=(Enter)
  # NOTE: Avoid '?' in the prompt.
  #       Codex 0.149.0 echoes any such prompt back with the '?' missing.
  AGENT_TUI_PROMPT_TEXT="Name the capital city of England. Reply with only the city name."
  AGENT_TUI_PROMPT_VISIBLE_MODE="literal"
  AGENT_TUI_PROMPT_VISIBLE_TEXT="${AGENT_TUI_PROMPT_TEXT}"
  AGENT_TUI_PROMPT_VISIBLE_REGEX=""
  AGENT_TUI_EXPECTED_TOKEN="London"

  sft_agent_tui_reset_gates

  mkdir -p "${AGENT_TUI_WORKDIR}"
  AGENT_TUI_WORKDIR="$(cd -- "${AGENT_TUI_WORKDIR}" && pwd -P)"
  : >"${AGENT_TUI_SCREEN_PATH}"
}

sft_agent_tui_teardown_test_env() {
  local keep_now="${AGENT_TUI_KEEP_SESSION:-0}"
  local root_path="${AGENT_TUI_ROOT:-}"

  if [[ "${AGENT_TUI_FAILED:-0}" == "1" && "${AGENT_TUI_KEEP_SESSION_ON_FAIL:-0}" == "1" ]]; then
    keep_now="1"
  fi

  if [[ "${keep_now}" != "1" ]]; then
    sft_tmux_cleanup
  fi

  if [[ "${keep_now}" != "1" ]] && [[ -n "${root_path}" ]]; then
    case "${root_path}" in
      "${BATS_TEST_TMPDIR:-/tmp}"/safehouse-agent-tui-root.*)
        rm -rf -- "${root_path}"
        ;;
      *)
        printf 'refusing to remove unsafe agent tui path: %s\n' "${root_path}" >&2
        return 1
        ;;
    esac
  fi
}

sft_agent_tui_preflight_sandbox_exec_or_skip() {
  local preflight_policy=""

  preflight_policy="$(mktemp /tmp/safehouse-agent-tui-preflight.XXXXXX)"
  printf '(version 1)\n(allow default)\n' >"${preflight_policy}"

  if ! sandbox-exec -f "${preflight_policy}" -- /bin/echo ok >/dev/null 2>&1; then
    rm -f "${preflight_policy}"
    skip "sandbox-exec cannot run from this terminal session"
  fi

  rm -f "${preflight_policy}"
}

sft_agent_tui_dist_safehouse_path() {
  if [[ -n "${DIST_SAFEHOUSE:-}" ]]; then
    printf '%s\n' "${DIST_SAFEHOUSE}"
  else
    printf '%s/dist/safehouse.sh\n' "$(cd -- "${SFT_AGENT_TUI_HELPER_DIR}/../.." && pwd -P)"
  fi
}

sft_agent_tui_unique_name() {
  local component="agent"

  if [[ -n "${BATS_TEST_FILENAME:-}" ]]; then
    component="$(printf '%s' "${BATS_TEST_FILENAME##*/}" | tr -cs '[:alnum:]' '-')"
    component="${component#-}"
    component="${component%-}"
    [[ -n "${component}" ]] || component="agent"
  fi

  printf 'safehouse-agent-tui-%s-%s-%s-%s\n' "${component}" "$(date +%s)" "$$" "$RANDOM"
}

sft_agent_tui_add_dir() {
  local current="$1"
  local path_value="$2"

  [[ -n "${path_value}" ]] || {
    printf '%s\n' "${current}"
    return 0
  }

  if [[ "${path_value}" != */* ]]; then
    path_value="$(command -v "${path_value}" 2>/dev/null || printf '%s' "${path_value}")"
  fi
  if [[ "${path_value}" == */* ]]; then
    if [[ -d "$(dirname -- "${path_value}")" ]]; then
      path_value="$(cd -- "$(dirname -- "${path_value}")" && pwd -P)"
    else
      path_value="$(dirname -- "${path_value}")"
    fi
  fi

  [[ -d "${path_value}" ]] || {
    printf '%s\n' "${current}"
    return 0
  }

  case ":${current}:" in
    *:"${path_value}":*)
      ;;
    *)
      current="${current:+${current}:}${path_value}"
      ;;
  esac

  printf '%s\n' "${current}"
}

sft_agent_tui_allow_dirs_ro() {
  local command_name="$1"
  local path_list="${2:-${PATH}}"
  local old_ifs="${IFS}"
  local dir=""
  local allow_dirs_ro=""
  local -a path_dirs=()

  IFS=':'
  read -r -a path_dirs <<<"${path_list}"
  IFS="${old_ifs}"

  for dir in "${path_dirs[@]-}"; do
    allow_dirs_ro="$(sft_agent_tui_add_dir "${allow_dirs_ro}" "${dir}")"
  done

  allow_dirs_ro="$(sft_agent_tui_add_dir "${allow_dirs_ro}" "${command_name}")"
  printf '%s\n' "${allow_dirs_ro}"
}

sft_agent_tui_resolve_command_path() {
  local command_name="$1"
  local resolved_path="$1"
  local resolved_dir=""

  if [[ "${resolved_path}" != */* ]]; then
    resolved_path="$(command -v "${command_name}" 2>/dev/null || true)"
  fi

  [[ -n "${resolved_path}" ]] || return 1
  [[ "${resolved_path}" == */* ]] || {
    printf '%s\n' "${resolved_path}"
    return 0
  }

  resolved_dir="$(cd -- "$(dirname -- "${resolved_path}")" && pwd -P)"
  printf '%s/%s\n' "${resolved_dir}" "$(basename -- "${resolved_path}")"
}

# Assigns the resolved path to the caller variable <var_name>, or skips. It
# assigns instead of printing because `skip` inside a command substitution would
# exit only that subshell.
sft_agent_tui_command_path_or_skip() {
  local var_name="$1"
  local command_name="$2"
  local resolved_path=""

  resolved_path="$(sft_agent_tui_resolve_command_path "${command_name}" || true)"
  [[ -n "${resolved_path}" ]] || skip "${command_name} is not installed"

  printf -v "${var_name}" '%s' "${resolved_path}"
}

sft_agent_tui_prepend_path_dir() {
  local current_path="$1"
  local path_value="$2"
  local old_ifs="${IFS}"
  local path_entry=""
  local rebuilt_path=""
  local -a path_entries=()

  [[ -n "${path_value}" && -d "${path_value}" ]] || {
    printf '%s\n' "${current_path}"
    return 0
  }

  IFS=':'
  read -r -a path_entries <<<"${current_path}"
  IFS="${old_ifs}"

  for path_entry in "${path_entries[@]-}"; do
    [[ -n "${path_entry}" ]] || continue
    [[ "${path_entry}" == "${path_value}" ]] && continue
    rebuilt_path="${rebuilt_path:+${rebuilt_path}:}${path_entry}"
  done

  if [[ -n "${rebuilt_path}" ]]; then
    printf '%s:%s\n' "${path_value}" "${rebuilt_path}"
  else
    printf '%s\n' "${path_value}"
  fi
}

sft_agent_tui_build_exec_path() {
  local command_path="$1"
  local current_path="${PATH}"
  local command_dir=""
  local pnpm_root=""
  local pnpm_node_bin=""

  if [[ "${command_path}" == */* ]]; then
    command_dir="$(cd -- "$(dirname -- "${command_path}")" && pwd -P)"
    current_path="$(sft_agent_tui_prepend_path_dir "${current_path}" "${command_dir}")"

    case "${command_dir}" in
      */Library/pnpm)
        pnpm_root="${command_dir}"
        ;;
      */Library/pnpm/*)
        pnpm_root="${command_dir%%/Library/pnpm/*}/Library/pnpm"
        ;;
    esac

    if [[ -n "${pnpm_root}" ]]; then
      pnpm_node_bin="${pnpm_root}/nodejs_current/bin"
      current_path="$(sft_agent_tui_prepend_path_dir "${current_path}" "${pnpm_node_bin}")"
    fi
  fi

  printf '%s\n' "${current_path}"
}

sft_agent_tui_collect_env_pass_names() {
  local idx=0
  local arg_count="${#safehouse_args[@]}"
  local current_arg=""

  SFT_AGENT_TUI_ENV_PASS_NAMES=()

  while (( idx < arg_count )); do
    current_arg="${safehouse_args[$idx]}"
    case "${current_arg}" in
      --env-pass)
        if (( idx + 1 < arg_count )); then
          SFT_AGENT_TUI_ENV_PASS_NAMES+=("${safehouse_args[$((idx + 1))]}")
          idx=$((idx + 2))
          continue
        fi
        ;;
      --env-pass=*)
        SFT_AGENT_TUI_ENV_PASS_NAMES+=("${current_arg#*=}")
        ;;
    esac
    idx=$((idx + 1))
  done
}

sft_agent_tui_apply_env_pass_names() {
  local session_name="$1"
  local csv=""
  local env_name=""
  local old_ifs="${IFS}"
  local -a env_names=()

  for csv in "${SFT_AGENT_TUI_ENV_PASS_NAMES[@]-}"; do
    IFS=','
    read -r -a env_names <<<"${csv}"
    IFS="${old_ifs}"

    for env_name in "${env_names[@]-}"; do
      env_name="$(printf '%s' "${env_name}" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')"
      [[ "${env_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || continue

      if [[ "${!env_name+x}" == "x" ]]; then
        sft_tmux set-environment -t "${session_name}" "${env_name}" "${!env_name}"
      else
        sft_tmux set-environment -t "${session_name}" -u "${env_name}" >/dev/null 2>&1 || true
      fi
    done
  done
}

sft_agent_tui_run_with_timeout() {
  local timeout_secs="$1"
  shift

  perl -e '
use strict;
use warnings;

my $timeout = shift @ARGV;
my $pid = fork();
die "fork failed: $!" if !defined $pid;

if ($pid == 0) {
  setpgrp(0, 0);
  exec @ARGV;
  die "exec failed: $!";
}

$SIG{ALRM} = sub {
  kill "TERM", -$pid;
  sleep 2;
  kill "KILL", -$pid;
  exit 124;
};

alarm($timeout);
waitpid($pid, 0);
alarm(0);
exit($? >> 8);
' "${timeout_secs}" "$@"
}

sft_tmux_start() {
  local -a safehouse_args=()
  local -a wrapped_command_env=()
  local -a command_args=()
  local command_name=""
  local command_env_name=""
  local command_exec_path=""
  local dist_safehouse=""
  local allow_dirs_ro=""
  local resolved_command_name=""
  local session_name=""

  [[ "$#" -gt 0 && "$1" == "safehouse" ]] || {
    printf 'sft_tmux_start requires safehouse [safehouse-args ...] -- [ENV=VALUE ...] command [args...]\n' >&2
    AGENT_TUI_FAILED=1
    return 1
  }
  shift

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --)
        shift
        break
        ;;
      *)
        safehouse_args+=("$1")
        shift
        ;;
    esac
  done

  while [[ "$#" -gt 0 && "$1" == *=* ]]; do
    command_env_name="${1%%=*}"
    [[ "${command_env_name}" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]] || break
    wrapped_command_env+=("$1")
    shift
  done

  [[ "$#" -gt 0 ]] || {
    printf 'sft_tmux_start requires a wrapped command after safehouse args\n' >&2
    AGENT_TUI_FAILED=1
    return 1
  }

  command_name="$1"
  command_args=("${@:2}")
  [[ -n "${AGENT_TUI_NAME:-}" ]] || AGENT_TUI_NAME="${command_name##*/}"

  resolved_command_name="$(sft_agent_tui_resolve_command_path "${command_name}" || true)"
  if [[ -n "${resolved_command_name}" ]]; then
    command_name="${resolved_command_name}"
  fi
  command_exec_path="$(sft_agent_tui_build_exec_path "${command_name}")"

  dist_safehouse="$(sft_agent_tui_dist_safehouse_path)"
  [[ -x "${dist_safehouse}" ]] || {
    printf 'dist/safehouse.sh is not available: %s\n' "${dist_safehouse}" >&2
    AGENT_TUI_FAILED=1
    return 1
  }

  allow_dirs_ro="$(sft_agent_tui_allow_dirs_ro "${command_name}" "${command_exec_path}")"
  sft_agent_tui_collect_env_pass_names

  sft_tmux_cleanup || true

  session_name="$(sft_agent_tui_unique_name)"
  AGENT_TUI_SESSION_NAME="${session_name}"
  sft_tmux_create_session_named "${session_name}" "${AGENT_TUI_WORKDIR}"
  sft_agent_tui_apply_env_pass_names "${session_name}"
  sft_tmux_run /usr/bin/env \
    "PATH=${command_exec_path}" \
    "${dist_safehouse}" \
    "${safehouse_args[@]}" \
    --workdir "${AGENT_TUI_WORKDIR}" \
    --add-dirs-ro "${allow_dirs_ro}" \
    -- \
    "${wrapped_command_env[@]}" \
    "${command_name}" \
    "${command_args[@]}"
}

sft_safehouse_run_capture() {
  local output_file="$1"
  local command_name="$2"
  local command_exec_path=""
  local dist_safehouse=""
  local allow_dirs_ro=""
  local resolved_command_name=""

  shift 2

  resolved_command_name="$(sft_agent_tui_resolve_command_path "${command_name}" || true)"
  if [[ -n "${resolved_command_name}" ]]; then
    command_name="${resolved_command_name}"
  fi
  command_exec_path="$(sft_agent_tui_build_exec_path "${command_name}")"
  dist_safehouse="$(sft_agent_tui_dist_safehouse_path)"
  allow_dirs_ro="$(sft_agent_tui_allow_dirs_ro "${command_name}" "${command_exec_path}")"

  set +e
  (
    cd "${AGENT_TUI_WORKDIR:-${PWD}}" || exit 1
    PATH="${command_exec_path}" \
      sft_agent_tui_run_with_timeout "${AGENT_TUI_RESPONSE_TIMEOUT_SECS:-20}" \
      "${dist_safehouse}" \
      --workdir "${AGENT_TUI_WORKDIR:-${PWD}}" \
      --add-dirs-ro "${allow_dirs_ro}" \
      -- \
      "${command_name}" \
      "$@"
  ) >"${output_file}" 2>&1
  local status=$?
  set -e

  return "${status}"
}

# Dump the screen for a failure report.
#
# Prints up to three sections, each shown only when it differs from the one
# before it:
# 1. decision frame: the frame the caller actually judged, when it passed one.
# 2. current frame: the screen at the moment of failure.
# 3. settled frame: the screen after AGENT_TUI_FAILURE_SETTLE_SECS more.
sft_agent_tui_write_screen_capture() {
  local -a decision_frame=()
  local settle_secs="${AGENT_TUI_FAILURE_SETTLE_SECS:-2.0}"
  local captured=0
  local shown_normal=""
  local shown_alt=""
  local frame_change=""
  local report=""

  case "$#" in
    0) ;;
    2) decision_frame=("$1" "$2") ;;
    *)
      printf 'usage: sft_agent_tui_write_screen_capture [normal_output alt_output]\n' >&2
      return 1
      ;;
  esac

  # Capture current frame (and check whether TUI session still available)
  if sft_tmux_capture_full 2>/dev/null; then
    captured=1
  fi

  # Print:
  # 1. decision frame (if available)
  # 2. current frame
  if (( ${#decision_frame[@]} == 2 )); then
    report="--- decision frame ---"$'\n'
    report="${report}$(sft_tmux_select_capture "${decision_frame[0]}" "${decision_frame[1]}")"$'\n'
    shown_normal="${decision_frame[0]}"
    shown_alt="${decision_frame[1]}"

    frame_change="$(sft_agent_tui_describe_frame_change \
      "${shown_normal}" "${shown_alt}" \
      "${SFT_TMUX_LAST_CAPTURE[0]}" "${SFT_TMUX_LAST_CAPTURE[1]}")"

    if [[ -n "${frame_change}" ]]; then
      report="${report}--- current frame (${frame_change}) ---"$'\n'
      report="${report}$(sft_tmux_select_capture "${SFT_TMUX_LAST_CAPTURE[@]}")"$'\n'
      shown_normal="${SFT_TMUX_LAST_CAPTURE[0]}"
      shown_alt="${SFT_TMUX_LAST_CAPTURE[1]}"
    fi
  else
    report="--- current frame (no decision frame) ---"$'\n'
    report="${report}$(sft_tmux_select_capture "${SFT_TMUX_LAST_CAPTURE[@]}")"$'\n'
    shown_normal="${SFT_TMUX_LAST_CAPTURE[0]}"
    shown_alt="${SFT_TMUX_LAST_CAPTURE[1]}"
  fi
  
  # Print:
  # 3. settled frame (unless session is gone, assumed when first capture failed)
  if (( captured == 1 )) && [[ "${settle_secs}" != "0" && "${settle_secs}" != "0.0" ]]; then
    sleep "${settle_secs}"

    if sft_tmux_capture_full 2>/dev/null; then
      frame_change="$(sft_agent_tui_describe_frame_change \
        "${shown_normal}" "${shown_alt}" \
        "${SFT_TMUX_LAST_CAPTURE[0]}" "${SFT_TMUX_LAST_CAPTURE[1]}")"

      if [[ -n "${frame_change}" ]]; then
        report="${report}--- settled frame, +${settle_secs}s (${frame_change}) ---"$'\n'
        report="${report}$(sft_tmux_select_capture "${SFT_TMUX_LAST_CAPTURE[@]}")"$'\n'
      fi
    fi
  fi

  if [[ -n "${AGENT_TUI_SCREEN_PATH:-}" ]]; then
    printf '%s' "${report}" >"${AGENT_TUI_SCREEN_PATH}"
  fi
  printf '%s' "${report}"
}

# Name the buffers that moved between two frames,
# or print nothing if neither did.
sft_agent_tui_describe_frame_change() {
  local before_normal="${1:-}"
  local before_alt="${2:-}"
  local after_normal="${3:-}"
  local after_alt="${4:-}"
  local -a moved=()

  [[ "${before_normal}" == "${after_normal}" ]] || moved+=("normal")
  [[ "${before_alt}" == "${after_alt}" ]] || moved+=("alternate")

  case "${#moved[@]}" in
    0) return 0 ;;
    1) printf '%s buffer differs\n' "${moved[0]}" ;;
    *) printf 'normal + alternate buffers differ\n' ;;
  esac
}

# Dismiss one startup gate: send its keys (if any), then wait for the gate to
# stop matching before letting the caller re-check the screen.
sft_agent_tui_dismiss_gate() {
  local gate_pattern="$1"

  shift

  if (( $# > 0 )); then
    sft_tmux_send_keys "$@" || return 1
  fi

  # NOTE: A gate that never clears is not an error here. The caller will retry
  #       a limited number of times.
  sft_tmux_wait_until_regex_gone \
    "${gate_pattern}" \
    "${AGENT_TUI_GATE_CLEAR_TIMEOUT_SECS:-5}" \
    "${AGENT_TUI_POLL_INTERVAL_SECS:-0.2}" || true

  return 0
}

# Startup gate registry
#
# A gate is something an agent TUI paints before it is ready for input: a trust
# prompt, an auth picker, a promo overlay. Tests register the gates their agent
# is known to show, then call sft_agent_tui_handle_startup_gates to answer them.
sft_agent_tui_reset_gates() {
  AGENT_TUI_READY_PATTERN=""
  AGENT_TUI_GATE_PATTERNS=()
  AGENT_TUI_GATE_KEYS=()
  AGENT_TUI_GATE_FLAGS=()
  AGENT_TUI_GATE_REASONS=()
}

# sft_agent_tui_add_gate [--before-ready] [--once] pattern [key1 key2 ...]
# 
# Gates are checked in registration order, with --before-ready ones before the
# AGENT_TUI_READY_PATTERN check and others after it.
#
# Parameters:
# * --once: Retires the gate after it is answered,
#   for a gate that must not be answered twice.
# * keys: tmux key names sent to dismiss the gate.
#   A gate registered with no keys is simply waited out.
sft_agent_tui_add_gate() {
  local flags=""
  local pattern=""

  while (( $# > 0 )); do
    case "$1" in
      --before-ready) flags="${flags} before-ready" ;;
      --once) flags="${flags} once" ;;
      --) shift; break ;;
      -*)
        printf 'sft_agent_tui_add_gate: unknown option: %s\n' "$1" >&2
        return 1
        ;;
      *) break ;;
    esac
    shift
  done

  pattern="${1:-}"
  [[ -n "${pattern}" ]] || {
    printf 'usage: sft_agent_tui_add_gate [--before-ready] [--once] pattern [key1 key2 ...]\n' >&2
    return 1
  }
  shift

  AGENT_TUI_GATE_PATTERNS+=("${pattern}")
  AGENT_TUI_GATE_KEYS+=("$*")
  AGENT_TUI_GATE_FLAGS+=("${flags}")
  AGENT_TUI_GATE_REASONS+=("")
}

# sft_agent_tui_add_skip_gate pattern reason
# 
# Adds a pseudo-gate that when matched skips the current test with the
# specified reason. Always is a --before-ready gate, checked before the
# AGENT_TUI_READY_PATTERN check.
sft_agent_tui_add_skip_gate() {
  local pattern="${1:-}"
  local reason="${2:-}"

  [[ -n "${pattern}" && -n "${reason}" ]] || {
    printf 'usage: sft_agent_tui_add_skip_gate pattern reason\n' >&2
    return 1
  }

  AGENT_TUI_GATE_PATTERNS+=("${pattern}")
  AGENT_TUI_GATE_KEYS+=("")
  AGENT_TUI_GATE_FLAGS+=("before-ready skip")
  AGENT_TUI_GATE_REASONS+=("${reason}")
}

# Answer startup gates until the agent is ready for input.
# 
# Note that if a "skip gate" was registered with sft_agent_tui_add_skip_gate,
# this function may skip the current test rather than returning. 
sft_agent_tui_handle_startup_gates() {
  local max_passes="${AGENT_TUI_GATE_MAX_PASSES:-5}"
  local gate_count="${#AGENT_TUI_GATE_PATTERNS[@]}"
  local combined_pattern=""
  local phase=""
  local flags=""
  local pass=0
  local i=0
  local matched=-1
  local -a frame=()
  local -a keys=()
  local -a retired=()

  [[ -n "${AGENT_TUI_READY_PATTERN:-}" ]] || {
    printf 'sft_agent_tui_handle_startup_gates: AGENT_TUI_READY_PATTERN is unset\n' >&2
    return 1
  }

  for (( i = 0; i < gate_count; i++ )); do
    retired[i]=0
  done

  for (( pass = 1; pass <= max_passes; pass++ )); do
    combined_pattern="${AGENT_TUI_READY_PATTERN}"
    for (( i = 0; i < gate_count; i++ )); do
      (( retired[i] == 0 )) || continue
      combined_pattern="${combined_pattern}|${AGENT_TUI_GATE_PATTERNS[i]}"
    done

    # Wait for a startup gate to appear
    sft_tmux_wait_until_regex \
      "${combined_pattern}" \
      "${AGENT_TUI_STARTUP_WAIT_SECS}" \
      "${AGENT_TUI_POLL_INTERVAL_SECS}" || {
        AGENT_TUI_FAILED=1
        sft_agent_tui_write_screen_capture >&2 || true
        return 1
      }
    frame=("${SFT_TMUX_LAST_CAPTURE[@]}")

    # Identify which startup gate did appear
    matched=-1
    for phase in before-ready after-ready; do
      if [[ "${phase}" == "after-ready" ]] \
        && sft_tmux_matches_regex "${AGENT_TUI_READY_PATTERN}" "${frame[@]}"; then
        return 0
      fi

      for (( i = 0; i < gate_count; i++ )); do
        (( retired[i] == 0 )) || continue
        flags=" ${AGENT_TUI_GATE_FLAGS[i]} "
        case "${phase}" in
          before-ready) [[ "${flags}" == *" before-ready "* ]] || continue ;;
          *) [[ "${flags}" != *" before-ready "* ]] || continue ;;
        esac

        if sft_tmux_matches_regex "${AGENT_TUI_GATE_PATTERNS[i]}" "${frame[@]}"; then
          matched="${i}"
          break 2
        fi
      done
    done

    # Lookup information for the matched startup gate
    if (( matched < 0 )); then
      # Unreachable situation, unless a future gate pattern does not survive
      # being joined with | when it is added to ${combined_pattern} above
      AGENT_TUI_FAILED=1
      printf 'unhandled startup gate\n' >&2
      sft_agent_tui_write_screen_capture "${frame[@]}" >&2 || true
      return 1
    fi
    flags=" ${AGENT_TUI_GATE_FLAGS[matched]} "
    # NOTE: Deliberately unquoted. tmux key names are single words, so the
    #       stored list splits back into the arguments it was built from.
    # shellcheck disable=SC2206
    keys=(${AGENT_TUI_GATE_KEYS[matched]})

    # If is a skip gate, exit the test
    if [[ "${flags}" == *" skip "* ]]; then
      skip "${AGENT_TUI_GATE_REASONS[matched]}"
    fi

    # Dismiss the gate by pressing the appropriate keys (if specified)
    if (( ${#keys[@]} > 0 )); then
      sft_agent_tui_dismiss_gate "${AGENT_TUI_GATE_PATTERNS[matched]}" "${keys[@]}"
    else
      sft_agent_tui_dismiss_gate "${AGENT_TUI_GATE_PATTERNS[matched]}"
    fi

    # If the gate is a --once gate, don't look for it again in the current loop
    [[ "${flags}" != *" once "* ]] || retired[matched]=1
  done

  AGENT_TUI_FAILED=1
  printf 'too many startup gate passes\n' >&2
  sft_agent_tui_write_screen_capture >&2 || true
  return 1
}

sft_agent_tui_wait_for_prompt_visible() {
  local timeout_secs="${AGENT_TUI_PROMPT_VISIBLE_TIMEOUT_SECS:-5}"
  local poll_secs="${AGENT_TUI_POLL_INTERVAL_SECS:-0.2}"
  local visible_mode="${AGENT_TUI_PROMPT_VISIBLE_MODE:-literal}"
  local visible_text="${AGENT_TUI_PROMPT_VISIBLE_TEXT:-${AGENT_TUI_PROMPT_TEXT}}"

  case "${visible_mode}" in
    none)
      # Some TUIs keep rendering the placeholder until submit, so prompt echo
      # visibility is not a reliable signal that input landed.
      return 0
      ;;
    ""|literal)
      sft_tmux_wait_until "${visible_text}" "${timeout_secs}" "${poll_secs}"
      ;;
    compact)
      sft_tmux_wait_until_compact_text "${visible_text}" "${timeout_secs}" "${poll_secs}"
      ;;
    regex)
      [[ -n "${AGENT_TUI_PROMPT_VISIBLE_REGEX:-}" ]] || {
        printf 'AGENT_TUI_PROMPT_VISIBLE_REGEX is required when AGENT_TUI_PROMPT_VISIBLE_MODE=regex\n' >&2
        return 1
      }
      sft_tmux_wait_until_regex "${AGENT_TUI_PROMPT_VISIBLE_REGEX}" "${timeout_secs}" "${poll_secs}"
      ;;
    *)
      printf 'unsupported AGENT_TUI_PROMPT_VISIBLE_MODE: %s\n' "${visible_mode}" >&2
      return 1
      ;;
  esac
}

sft_agent_tui_send_prompt_text() {
  local send_mode="${AGENT_TUI_PROMPT_SEND_MODE:-bulk}"

  case "${send_mode}" in
    ""|bulk)
      sft_tmux_send_text "${AGENT_TUI_PROMPT_TEXT}"
      ;;
    slow)
      sft_tmux_send_text_slow "${AGENT_TUI_PROMPT_TEXT}" "${AGENT_TUI_PROMPT_CHAR_DELAY_SECS:-0.03}"
      ;;
    *)
      printf 'unsupported AGENT_TUI_PROMPT_SEND_MODE: %s\n' "${send_mode}" >&2
      return 1
      ;;
  esac
}

sft_tmux_assert_roundtrip() {
  local key_name=""

  for key_name in "${AGENT_TUI_PRE_PROMPT_KEYS[@]-}"; do
    [[ -n "${key_name}" ]] || continue
    sft_tmux_send_keys "${key_name}" || {
      AGENT_TUI_FAILED=1
      return 1
    }
  done

  if [[ "${AGENT_TUI_PRE_PROMPT_DELAY_SECS:-0}" != "0" && "${AGENT_TUI_PRE_PROMPT_DELAY_SECS:-0}" != "0.0" ]]; then
    sleep "${AGENT_TUI_PRE_PROMPT_DELAY_SECS}"
  fi
  sft_agent_tui_send_prompt_text || {
      AGENT_TUI_FAILED=1
      return 1
    }
  sft_agent_tui_wait_for_prompt_visible || {
      AGENT_TUI_FAILED=1
      sft_agent_tui_write_screen_capture >&2 || true
      return 1
    }
  if [[ "${AGENT_TUI_SUBMIT_DELAY_SECS:-0}" != "0" && "${AGENT_TUI_SUBMIT_DELAY_SECS:-0}" != "0.0" ]]; then
    sleep "${AGENT_TUI_SUBMIT_DELAY_SECS}"
  fi
  for key_name in "${AGENT_TUI_SUBMIT_KEYS[@]-}"; do
    [[ -n "${key_name}" ]] || continue
    sft_tmux_send_keys "${key_name}" || {
      AGENT_TUI_FAILED=1
      return 1
    }
  done
  sft_tmux_wait_until_compact_text "${AGENT_TUI_EXPECTED_TOKEN}" "${AGENT_TUI_RESPONSE_TIMEOUT_SECS:-20}" "${AGENT_TUI_POLL_INTERVAL_SECS:-0.2}" || {
    AGENT_TUI_FAILED=1
    sft_agent_tui_write_screen_capture >&2 || true
    return 1
  }
}
