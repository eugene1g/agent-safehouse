#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="claude-code"
AUTH_PATTERNS=(
	'api key'
	'authentication'
	'not logged in'
	'login'
	'unauthorized'
	'rate limit'
	'quota'
	'credit balance'
	'balance is too low'
	'insufficient credits?'
	'setup-token'
)
DENIAL_PATTERNS=(
	'access files outside'
	'can.t read that file'
	'restricted file'
	'authorized working director'
	'outside my configured working directories'
	'outside the authorized working directory'
	'access restricted'
	'decline this request'
	'can.t help with that request'
	'security boundaries'
	'refuse attempts to access'
	'which i don.t do'
)

run_prompt() {
	local prompt="$1"
	local output_file="$2"
	local claude_model="${SAFEHOUSE_E2E_CLAUDE_MODEL:-}"
	local claude_fallback_model="${SAFEHOUSE_E2E_CLAUDE_FALLBACK_MODEL:-}"
	local model_error_pattern='model .* not found|unknown model|invalid model|invalid value|unsupported model|unknown option.*model|selected model|may not exist|run --model'
	local status=0

	if [[ -n "${claude_model}" ]]; then
		set +e
		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--model "${claude_model}" \
			--print \
			--output-format json \
			--permission-mode bypassPermissions \
			"${prompt}"
		status=$?
		set -e
	else
		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--print \
			--output-format json \
			--permission-mode bypassPermissions \
			"${prompt}"
		return $?
	fi

	if [[ "${status}" -eq 0 ]]; then
		return 0
	fi

	if rg -qi -- "${model_error_pattern}" "${output_file}"; then
		if [[ -n "${claude_fallback_model}" ]] && [[ "${claude_fallback_model}" != "${claude_model}" ]]; then
			set +e
			run_safehouse_command "${output_file}" \
				"${AGENT_BIN}" \
				--model "${claude_fallback_model}" \
				--print \
				--output-format json \
				--permission-mode bypassPermissions \
				"${prompt}"
			status=$?
			set -e
			if [[ "${status}" -eq 0 ]]; then
				return 0
			fi
		fi

		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--print \
			--output-format json \
			--permission-mode bypassPermissions \
			"${prompt}"
		return $?
	fi

	return "${status}"
}

run_noninteractive_adapter
