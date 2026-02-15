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
	local provider key model_id fallback_model_id auth_out

	run_cline_auth() {
		local auth_log="$1"
		local auth_provider="$2"
		local auth_key="$3"
		local auth_model="${4:-}"
		if [[ -n "${auth_model}" ]]; then
			run_safehouse_command "${auth_log}" "${AGENT_BIN}" auth --provider "${auth_provider}" --apikey "${auth_key}" --modelid "${auth_model}"
		else
			run_safehouse_command "${auth_log}" "${AGENT_BIN}" auth --provider "${auth_provider}" --apikey "${auth_key}"
		fi
	}

	if [[ "${CLINE_AUTH_DONE}" == "1" ]]; then
		return 0
	fi

	# Prefer OpenAI for low-cost ping checks; fall back to Anthropic when needed.
	if [[ -n "${OPENAI_API_KEY:-}" ]]; then
		provider="openai-native"
		key="${OPENAI_API_KEY}"
		model_id="${SAFEHOUSE_E2E_CLINE_OPENAI_MODEL:-}"
		fallback_model_id="${SAFEHOUSE_E2E_CLINE_OPENAI_FALLBACK_MODEL:-}"
	elif [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
		provider="anthropic"
		key="${ANTHROPIC_API_KEY}"
		model_id="${SAFEHOUSE_E2E_CLINE_ANTHROPIC_MODEL:-}"
		fallback_model_id="${SAFEHOUSE_E2E_CLINE_ANTHROPIC_FALLBACK_MODEL:-}"
	else
		echo "ADAPTER[${ADAPTER_NAME}]: missing ANTHROPIC_API_KEY/OPENAI_API_KEY for cline auth" | tee -a "${TRANSCRIPT_PATH}"
		exit 2
	fi

	auth_out="${TRANSCRIPT_PATH%.log}.auth.log"
	if ! run_cline_auth "${auth_out}" "${provider}" "${key}" "${model_id}"; then
		if [[ -n "${fallback_model_id}" ]] && [[ "${fallback_model_id}" != "${model_id}" ]] && rg -qi -- 'model .* not found|unknown model|invalid model|invalid value|unsupported model' "${auth_out}"; then
			if run_cline_auth "${auth_out}" "${provider}" "${key}" "${fallback_model_id}"; then
				CLINE_AUTH_DONE=1
				return 0
			fi
		fi

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
