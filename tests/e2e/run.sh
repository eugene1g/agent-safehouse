#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd -P)"
SAFEHOUSE="${REPO_ROOT}/bin/safehouse.sh"
FIXTURE_SOURCE="${SCRIPT_DIR}/fixtures/fake-tui-agent.sh"
AGENT_PROFILES_DIR="${REPO_ROOT}/profiles/60-agents"

TUI_TIMEOUT_SECS="${SAFEHOUSE_E2E_TUI_TIMEOUT_SECS:-20}"
TUI_SESSION_TIMEOUT_SECS="${SAFEHOUSE_E2E_TUI_SESSION_TIMEOUT_SECS:-20}"
TUI_JOBS="${SAFEHOUSE_E2E_TUI_JOBS:-1}"

PROFILE_ONLY=""
LIST_PROFILES=0

SESSION_NAME=""
CURRENT_AGENT_PROFILE=""
CURRENT_AGENT_COMMAND=""
TMP_ROOT=""
WORKDIR=""
AGENT_PATH=""
CANARY_PATH=""
FORBIDDEN_PATH=""
FORBIDDEN_PARENT=""
FORBIDDEN_READ_PATH=""
FORBIDDEN_READ_PARENT=""
FORBIDDEN_READ_SECRET=""
PANE_LOG=""
POLICY_PATH=""
PASS_COUNT=0
TOTAL_COUNT=0

usage() {
	cat <<'EOF'
Usage:
  ./tests/e2e/run.sh
  ./tests/e2e/run.sh --profile <profile>
  ./tests/e2e/run.sh --jobs <n>
  ./tests/e2e/run.sh --list-profiles

Environment:
  SAFEHOUSE_E2E_TUI_TIMEOUT_SECS
  SAFEHOUSE_E2E_TUI_SESSION_TIMEOUT_SECS
  SAFEHOUSE_E2E_TUI_JOBS

Optional:
  SAFEHOUSE_E2E_LIVE=1 ./tests/e2e/run.sh
  SAFEHOUSE_E2E_LIVE=1 ./tests/e2e/run.sh --profile <profile>
EOF
}

fail() {
  local message="$1"
  if [[ -n "${CURRENT_AGENT_PROFILE}" ]]; then
    echo "FAIL: [${CURRENT_AGENT_PROFILE} -> ${CURRENT_AGENT_COMMAND}] ${message}" >&2
  else
    echo "FAIL: ${message}" >&2
  fi

  if [[ -n "${PANE_LOG}" && -f "${PANE_LOG}" ]]; then
    echo "---- tmux pane log (tail) ----" >&2
    tail -n 120 "${PANE_LOG}" >&2 || true
    echo "------------------------------" >&2
  fi
  if [[ -n "${POLICY_PATH}" && -f "${POLICY_PATH}" ]]; then
    echo "---- policy markers (tail) ----" >&2
    tail -n 80 "${POLICY_PATH}" >&2 || true
    echo "-------------------------------" >&2
  fi

  exit 1
}

cleanup() {
  if command -v tmux >/dev/null 2>&1; then
    if tmux has-session -t "${SESSION_NAME}" >/dev/null 2>&1; then
      tmux kill-session -t "${SESSION_NAME}" >/dev/null 2>&1 || true
    fi
  fi

  if [[ -n "${TMP_ROOT}" && -d "${TMP_ROOT}" ]]; then
    rm -rf "${TMP_ROOT}"
  fi

  if [[ -n "${FORBIDDEN_PARENT}" && -d "${FORBIDDEN_PARENT}" ]]; then
    rm -rf "${FORBIDDEN_PARENT}"
  fi
  if [[ -n "${FORBIDDEN_READ_PARENT}" && -d "${FORBIDDEN_READ_PARENT}" ]]; then
    rm -rf "${FORBIDDEN_READ_PARENT}"
  fi
}

require_command() {
  local command_name="$1"
  if ! command -v "${command_name}" >/dev/null 2>&1; then
    fail "missing required command: ${command_name}"
  fi
}

preflight_sandbox_exec() {
  local preflight_policy
  preflight_policy="$(mktemp /tmp/safehouse-e2e-preflight.XXXXXX)"
  printf '(version 1)\n(allow default)\n' >"${preflight_policy}"

  if ! sandbox-exec -f "${preflight_policy}" -- /bin/echo preflight-ok >/dev/null 2>&1; then
    rm -f "${preflight_policy}"
    fail "sandbox-exec cannot run (nested sandbox or SIP restriction)"
  fi

  rm -f "${preflight_policy}"
}

wait_for_pattern() {
  local pattern="$1"
  local timeout_secs="$2"
  local deadline=$((SECONDS + timeout_secs))

  while ((SECONDS < deadline)); do
    if [[ -f "${PANE_LOG}" ]] && rg -Fq -- "${pattern}" "${PANE_LOG}"; then
      return 0
    fi
    sleep 1
  done

  return 1
}

wait_for_session_end() {
  local timeout_secs="$1"
  local deadline=$((SECONDS + timeout_secs))

  while ((SECONDS < deadline)); do
    if ! tmux has-session -t "${SESSION_NAME}" >/dev/null 2>&1; then
      return 0
    fi
    sleep 1
  done

  return 1
}

command_basename_for_profile() {
  local profile_base="$1"

  case "${profile_base}" in
    claude-code) printf '%s\n' "claude" ;;
    cursor-agent) printf '%s\n' "cursor-agent" ;;
    kilo-code) printf '%s\n' "kilo" ;;
    *) printf '%s\n' "${profile_base}" ;;
  esac
}

launch_command_string() {
  local command_string=""

  printf -v command_string '%q ' /usr/bin/env \
    "SAFEHOUSE_E2E_CANARY_PATH=${CANARY_PATH}" \
    "SAFEHOUSE_E2E_FORBIDDEN_PATH=${FORBIDDEN_PATH}" \
    "SAFEHOUSE_E2E_FORBIDDEN_READ_PATH=${FORBIDDEN_READ_PATH}" \
    "${SAFEHOUSE}" \
    --env-pass SAFEHOUSE_E2E_CANARY_PATH,SAFEHOUSE_E2E_FORBIDDEN_PATH,SAFEHOUSE_E2E_FORBIDDEN_READ_PATH \
    --workdir "${WORKDIR}" \
    -- "${AGENT_PATH}"

  printf '%s' "${command_string}"
}

assert_policy_selected_agent() {
  local profile_base="$1"
  local marker=";; Source: 60-agents/${profile_base}.sb"

  if ! rg -Fq -- "${marker}" "${POLICY_PATH}"; then
    fail "expected policy marker missing: ${marker}"
  fi
}

start_tmux_session() {
  tmux new-session -d -s "${SESSION_NAME}" -c "${WORKDIR}"
  tmux pipe-pane -o -t "${SESSION_NAME}:0.0" "cat >> ${PANE_LOG}"
  tmux send-keys -t "${SESSION_NAME}:0.0" "$(launch_command_string)" C-m
}

run_tmux_interaction() {
  wait_for_pattern "SAFEHOUSE_FAKE_TUI_READY" "${TUI_TIMEOUT_SECS}" || fail "agent did not report ready state"

  tmux send-keys -t "${SESSION_NAME}:0.0" Enter
  wait_for_pattern "EVENT:WRITE_OK:${CANARY_PATH}" "${TUI_TIMEOUT_SECS}" || fail "canary write event was not observed"

  tmux send-keys -t "${SESSION_NAME}:0.0" Down Enter
  wait_for_pattern "EVENT:FORBIDDEN_WRITE_DENIED:${FORBIDDEN_PATH}" "${TUI_TIMEOUT_SECS}" || fail "forbidden write deny event was not observed"

  tmux send-keys -t "${SESSION_NAME}:0.0" Down Enter
  wait_for_pattern "EVENT:FORBIDDEN_READ_DENIED:${FORBIDDEN_READ_PATH}" "${TUI_TIMEOUT_SECS}" || fail "forbidden read deny event was not observed"

  tmux send-keys -t "${SESSION_NAME}:0.0" Down Enter
  wait_for_pattern "EVENT:EXIT" "${TUI_TIMEOUT_SECS}" || fail "exit event was not observed"
  tmux send-keys -t "${SESSION_NAME}:0.0" "exit" C-m

  wait_for_session_end "${TUI_SESSION_TIMEOUT_SECS}" || fail "tmux session did not exit cleanly"
}

assert_filesystem_outcomes() {
  if [[ ! -f "${CANARY_PATH}" ]]; then
    fail "canary file was not created"
  fi
  if [[ "$(cat "${CANARY_PATH}")" != "SAFEHOUSE_E2E_OK" ]]; then
    fail "canary file content did not match expected token"
  fi
  if [[ -f "${FORBIDDEN_PATH}" ]]; then
    fail "forbidden file was created outside sandbox workdir"
  fi
  if [[ ! -f "${FORBIDDEN_READ_PATH}" ]]; then
    fail "forbidden read file was unexpectedly deleted"
  fi
  if [[ "$(cat "${FORBIDDEN_READ_PATH}")" != "${FORBIDDEN_READ_SECRET}" ]]; then
    fail "forbidden read file content was unexpectedly modified"
  fi
}

prepare_layout_for_agent() {
  mkdir -p "${WORKDIR}" "${FORBIDDEN_PARENT}" "${FORBIDDEN_READ_PARENT}"
  printf '%s\n' "${FORBIDDEN_READ_SECRET}" >"${FORBIDDEN_READ_PATH}"
  cp /usr/bin/true "${AGENT_PATH}"
  chmod +x "${AGENT_PATH}"
}

prepare_fixture_binary() {
  cp "${FIXTURE_SOURCE}" "${AGENT_PATH}"
  chmod +x "${AGENT_PATH}"
}

generate_and_validate_policy() {
  if ! "${SAFEHOUSE}" --output "${POLICY_PATH}" -- "${AGENT_PATH}" >/dev/null 2>&1; then
    fail "policy generation/execution preflight failed"
  fi
  assert_policy_selected_agent "${CURRENT_AGENT_PROFILE}"
}

run_agent_case() {
  local profile_base="$1"
  local command_basename

  CURRENT_AGENT_PROFILE="${profile_base}"
  command_basename="$(command_basename_for_profile "${profile_base}")"
  CURRENT_AGENT_COMMAND="${command_basename}"
  SESSION_NAME="safehouse-e2e-${profile_base//[^A-Za-z0-9]/-}-${RANDOM}-${RANDOM}"

  WORKDIR="${TMP_ROOT}/work-${profile_base}"
  AGENT_PATH="${WORKDIR}/${command_basename}"
  CANARY_PATH="${WORKDIR}/safehouse-e2e-canary-${profile_base}.txt"
  POLICY_PATH="${TMP_ROOT}/policy-${profile_base}.sb"
  PANE_LOG="${TMP_ROOT}/pane-${profile_base}.log"
  FORBIDDEN_PARENT="${HOME}/.safehouse-e2e-forbidden.${SESSION_NAME}"
  FORBIDDEN_PATH="${FORBIDDEN_PARENT}/safehouse-e2e-forbidden-${profile_base}.txt"
  FORBIDDEN_READ_PARENT="${HOME}/.safehouse-e2e-forbidden-read.${SESSION_NAME}"
  FORBIDDEN_READ_PATH="${FORBIDDEN_READ_PARENT}/safehouse-e2e-forbidden-read-${profile_base}.txt"
  FORBIDDEN_READ_SECRET="SAFEHOUSE_E2E_READ_SECRET_${profile_base}_${RANDOM}_${RANDOM}"

  prepare_layout_for_agent
  generate_and_validate_policy
  prepare_fixture_binary
  start_tmux_session
  run_tmux_interaction
  assert_filesystem_outcomes

  rm -rf "${FORBIDDEN_PARENT}"
  FORBIDDEN_PARENT=""
  rm -rf "${FORBIDDEN_READ_PARENT}"
  FORBIDDEN_READ_PARENT=""
  PASS_COUNT=$((PASS_COUNT + 1))

  echo "PASS: [${CURRENT_AGENT_PROFILE} -> ${CURRENT_AGENT_COMMAND}] tmux simulation and policy selection validated."
}

trap cleanup EXIT

parse_args() {
	while [[ "$#" -gt 0 ]]; do
		case "$1" in
		--profile)
			PROFILE_ONLY="${2:-}"
			if [[ -z "${PROFILE_ONLY}" ]]; then
				fail "--profile requires a value"
			fi
			shift 2
			;;
		--jobs)
			TUI_JOBS="${2:-}"
			if [[ -z "${TUI_JOBS}" ]]; then
				fail "--jobs requires a value"
			fi
			shift 2
			;;
		--list-profiles)
			LIST_PROFILES=1
			shift
			;;
		-h | --help)
			usage
			exit 0
			;;
		*)
			fail "unknown argument: $1"
			;;
		esac
	done
}

list_profiles() {
	fd -t f '\.sb$' "${AGENT_PROFILES_DIR}" | sort | while IFS= read -r p; do
		[[ -n "${p}" ]] || continue
		basename "${p}" .sb
	done
}

run_all_profiles_sequential() {
	echo "Running tmux-driven TUI E2E checks across all configured agent profiles..."

	TMP_ROOT="$(mktemp -d /tmp/safehouse-e2e.XXXXXX)"

	while IFS= read -r profile_path; do
		[[ -n "${profile_path}" ]] || continue
		TOTAL_COUNT=$((TOTAL_COUNT + 1))
		run_agent_case "$(basename "${profile_path}" .sb)"
	done < <(fd -t f '\.sb$' "${AGENT_PROFILES_DIR}" | sort)

	if [[ "${TOTAL_COUNT}" -eq 0 ]]; then
		fail "no agent profiles were discovered under ${AGENT_PROFILES_DIR}"
	fi

	echo "PASS: ${PASS_COUNT}/${TOTAL_COUNT} configured agent profiles validated with tmux E2E simulation."
}

run_all_profiles_parallel() {
	local jobs="${TUI_JOBS}"
	local profiles_file log_dir script_path
	local pass fail total profile log_file rc_file rc

	script_path="${SCRIPT_DIR}/run.sh"
	TMP_ROOT="$(mktemp -d /tmp/safehouse-e2e-tui-parallel.XXXXXX)"
	profiles_file="${TMP_ROOT}/profiles.txt"
	log_dir="${TMP_ROOT}/logs"
	mkdir -p "${log_dir}"

	list_profiles >"${profiles_file}"
	total="$(wc -l <"${profiles_file}" | tr -d '[:space:]')"
	if [[ "${total}" -eq 0 ]]; then
		fail "no agent profiles were discovered under ${AGENT_PROFILES_DIR}"
	fi

	echo "Running tmux-driven TUI E2E checks in parallel across ${total} configured agent profiles..."
	echo "TUI jobs: ${jobs} (set SAFEHOUSE_E2E_TUI_JOBS or use --jobs)"
	echo "Logs: ${log_dir}"

	# Each profile runs in its own process to keep global state (tmux session, temp files) isolated.
	xargs -n 1 -P "${jobs}" -I {} bash -c '
profile="$1"
log_dir="$2"
script_path="$3"
log_file="${log_dir}/${profile}.log"
rc_file="${log_file}.rc"

SAFEHOUSE_E2E_TUI_JOBS=1 SAFEHOUSE_E2E_LIVE=0 "${script_path}" --profile "${profile}" >"${log_file}" 2>&1
rc=$?
printf "%s\n" "${rc}" >"${rc_file}"
exit "${rc}"
' _ {} "${log_dir}" "${script_path}" <"${profiles_file}" || true

	pass=0
	fail=0
	total=0
	while IFS= read -r profile; do
		[[ -n "${profile}" ]] || continue
		total=$((total + 1))
		log_file="${log_dir}/${profile}.log"
		rc_file="${log_file}.rc"
		rc="1"
		if [[ -f "${rc_file}" ]]; then
			rc="$(cat "${rc_file}" | tr -d '[:space:]')"
		fi
		if [[ "${rc}" == "0" ]]; then
			pass=$((pass + 1))
		else
			fail=$((fail + 1))
		fi

		# Print each profile log in a stable order (no interleaving).
		echo ""
		echo "===== [${profile}] ====="
		if [[ -f "${log_file}" ]]; then
			cat "${log_file}"
		else
			echo "missing log file: ${log_file}"
		fi
	done <"${profiles_file}"

	echo ""
	if [[ "${fail}" -gt 0 ]]; then
		echo "FAIL: ${fail}/${total} configured agent profiles failed tmux E2E simulation." >&2
		exit 1
	fi

	echo "PASS: ${pass}/${total} configured agent profiles validated with tmux E2E simulation."
}

parse_args "$@"

if [[ "${LIST_PROFILES}" == "1" ]]; then
	require_command fd
	list_profiles
	exit 0
fi

if [[ -n "${PROFILE_ONLY}" ]]; then
	# Single-profile mode (used by parallel runner).
	require_command sandbox-exec
	require_command tmux
	require_command rg
	require_command fd

	if [[ ! -x "${SAFEHOUSE}" ]]; then
		fail "safehouse wrapper is missing or not executable: ${SAFEHOUSE}"
	fi
	if [[ ! -f "${FIXTURE_SOURCE}" ]]; then
		fail "missing fixture script: ${FIXTURE_SOURCE}"
	fi
	if [[ ! -d "${AGENT_PROFILES_DIR}" ]]; then
		fail "missing agent profiles directory: ${AGENT_PROFILES_DIR}"
	fi

	preflight_sandbox_exec
	TMP_ROOT="$(mktemp -d /tmp/safehouse-e2e.XXXXXX)"
	run_agent_case "${PROFILE_ONLY}"

	if [[ "${SAFEHOUSE_E2E_LIVE:-0}" == "1" ]]; then
		echo ""
		echo "INFO: SAFEHOUSE_E2E_LIVE=1 set; running live LLM checks for ${PROFILE_ONLY}..."
		"${SCRIPT_DIR}/live/run.sh" --profile "${PROFILE_ONLY}"
	fi
	exit 0
fi

echo "Running tmux-driven TUI E2E checks across all configured agent profiles..."

require_command sandbox-exec
require_command tmux
require_command rg
require_command fd

if [[ ! -x "${SAFEHOUSE}" ]]; then
  fail "safehouse wrapper is missing or not executable: ${SAFEHOUSE}"
fi
if [[ ! -f "${FIXTURE_SOURCE}" ]]; then
  fail "missing fixture script: ${FIXTURE_SOURCE}"
fi
if [[ ! -d "${AGENT_PROFILES_DIR}" ]]; then
  fail "missing agent profiles directory: ${AGENT_PROFILES_DIR}"
fi

preflight_sandbox_exec

if [[ "${TUI_JOBS}" != "1" ]]; then
	run_all_profiles_parallel
else
	run_all_profiles_sequential
fi

if [[ "${SAFEHOUSE_E2E_LIVE:-0}" == "1" ]]; then
  echo ""
  echo "INFO: SAFEHOUSE_E2E_LIVE=1 set; running live LLM checks..."
  "${SCRIPT_DIR}/live/run.sh"
fi
