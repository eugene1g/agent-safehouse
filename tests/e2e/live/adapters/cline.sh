#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="cline"
RESPONSE_TOKEN_MIN_MATCHES=2
DENIAL_TOKEN_MIN_MATCHES=2
CLINE_AUTH_DONE=0
AUTH_PATTERNS=(
	'api key'
	'authentication'
	'not authenticated'
	'not logged in'
	'login'
	'unauthorized'
	'rate limit'
	'quota'
	'cline auth'
)
DENIAL_PATTERNS=(
	'access denied'
	'permission denied'
	'operation not permitted'
	'EPERM'
	'Error executing read_file'
)

ensure_cline_auth() {
	local provider key model_id auth_out

	if [[ "${CLINE_AUTH_DONE}" == "1" ]]; then
		return 0
	fi

	# Prefer Anthropic when available since it's already used elsewhere in this suite.
	if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
		provider="anthropic"
		key="${ANTHROPIC_API_KEY}"
		model_id="claude-sonnet-4-5-20250929"
	elif [[ -n "${OPENAI_API_KEY:-}" ]]; then
		provider="openai-native"
		key="${OPENAI_API_KEY}"
		model_id="gpt-4o"
	else
		echo "ADAPTER[${ADAPTER_NAME}]: missing ANTHROPIC_API_KEY/OPENAI_API_KEY for cline auth" | tee -a "${TRANSCRIPT_PATH}"
		exit 2
	fi

	auth_out="${TRANSCRIPT_PATH%.log}.auth.log"
	if ! run_safehouse_command "${auth_out}" "${AGENT_BIN}" auth --provider "${provider}" --apikey "${key}" --modelid "${model_id}"; then
		if is_auth_or_setup_issue "${auth_out}"; then
			echo "ADAPTER[${ADAPTER_NAME}]: skip due to auth/model/setup issue in cline auth." | tee -a "${TRANSCRIPT_PATH}"
			print_excerpt "${ADAPTER_NAME} auth output" "${auth_out}"
			exit 2
		fi

		echo "ADAPTER[${ADAPTER_NAME}]: cline auth failed unexpectedly." | tee -a "${TRANSCRIPT_PATH}"
		print_excerpt "${ADAPTER_NAME} auth output" "${auth_out}"
		exit 3
	fi

	CLINE_AUTH_DONE=1
	return 0
}

run_prompt() {
	local prompt="$1"
	local output_file="$2"

	# Cline defaults to plan mode, which may block waiting for a plan/act toggle.
	# Force act + yolo to make this fully non-interactive for E2E.
	ensure_cline_auth
	if run_safehouse_command "${output_file}" "${AGENT_BIN}" --json -a -y --timeout 120 "${prompt}"; then
		return 0
	fi

	# In the forbidden-file prompt, Safehouse may cause Cline's internal read tool to error (EPERM).
	# Treat that as acceptable denial evidence so the suite can still assert "no secret leaked".
	if [[ "${prompt}" == Read\ file\ * ]] && is_expected_denial_output "${output_file}"; then
		return 0
	fi

	return 1
}

run_noninteractive_adapter
