#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="codex"
RESPONSE_TOKEN_MIN_MATCHES=2
DENIAL_TOKEN_MIN_MATCHES=2
CODEX_LOGIN_DONE=0
AUTH_PATTERNS=(
	'not logged in'
	'login'
	'api key'
	'authentication'
	'unauthorized'
	'rate limit'
	'quota'
)
DENIAL_PATTERNS=(
	"can't help"
	'can.t help'
	'cannot help'
	'not allowed'
	'access denied'
	'can.?t access'
	'unable to access'
	'permission denied'
	'operation not permitted'
	'private file'
)

run_safehouse_command_with_stdin() {
	local stdin_content="$1"
	local output_file="$2"
	shift 2

	local status=0
	local path_with_agent_bin="${AGENT_BIN_DIR}:${PATH}"
	local timeout_secs="${SAFEHOUSE_E2E_LIVE_COMMAND_TIMEOUT_SECS:-180}"
	local allow_dirs_ro="${AGENT_ALLOW_DIRS_RO}"

	if [[ -n "${GITHUB_EVENT_PATH:-}" ]] && [[ -f "${GITHUB_EVENT_PATH}" ]]; then
		local github_event_dir
		github_event_dir="$(cd "$(dirname "${GITHUB_EVENT_PATH}")" && pwd -P)"
		allow_dirs_ro="${allow_dirs_ro}:${github_event_dir}"
	fi

	set +e
	(
		cd "${WORKDIR}"
		PATH="${path_with_agent_bin}"
		printf '%s\n' "${stdin_content}" | run_with_timeout "${timeout_secs}" "${SAFEHOUSE}" --workdir "${WORKDIR}" --add-dirs-ro "${allow_dirs_ro}" -- "$@"
	) >"${output_file}" 2>&1
	status=$?
	set -e

	return "${status}"
}

ensure_codex_login() {
	local login_out

	if [[ "${CODEX_LOGIN_DONE}" == "1" ]]; then
		return 0
	fi

	if [[ -z "${OPENAI_API_KEY:-}" ]]; then
		echo "ADAPTER[${ADAPTER_NAME}]: missing OPENAI_API_KEY" | tee -a "${TRANSCRIPT_PATH}"
		exit 2
	fi

	login_out="${TRANSCRIPT_PATH%.log}.login.log"
	if ! run_safehouse_command_with_stdin "${OPENAI_API_KEY}" "${login_out}" "${AGENT_BIN}" login --with-api-key; then
		if is_auth_or_setup_issue "${login_out}"; then
			echo "ADAPTER[${ADAPTER_NAME}]: skip due to auth/model/setup issue in login." | tee -a "${TRANSCRIPT_PATH}"
			print_excerpt "${ADAPTER_NAME} login output" "${login_out}"
			exit 2
		fi

		echo "ADAPTER[${ADAPTER_NAME}]: login failed unexpectedly." | tee -a "${TRANSCRIPT_PATH}"
		print_excerpt "${ADAPTER_NAME} login output" "${login_out}"
		exit 3
	fi

	CODEX_LOGIN_DONE=1
	return 0
}

run_prompt() {
	local prompt="$1"
	local output_file="$2"

	ensure_codex_login

	run_safehouse_command "${output_file}" \
		"${AGENT_BIN}" \
		exec \
		--skip-git-repo-check \
		--dangerously-bypass-approvals-and-sandbox \
		--color never \
		"${prompt}"
}

run_noninteractive_adapter
