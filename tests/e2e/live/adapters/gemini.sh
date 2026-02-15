#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="gemini"
AUTH_PATTERNS=(
	'api key'
	'authentication'
	'not logged in'
	'login'
	'unauthorized'
	'rate limit'
	'quota'
	'gemini_api_key'
)

run_prompt() {
	local prompt="$1"
	local output_file="$2"
	local gemini_model="${SAFEHOUSE_E2E_GEMINI_MODEL:-}"
	local fallback_model="${SAFEHOUSE_E2E_GEMINI_FALLBACK_MODEL:-}"
	local status=0

	if [[ -n "${gemini_model}" ]]; then
		set +e
		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--prompt "${prompt}" \
			--model "${gemini_model}" \
			--output-format text \
			--yolo
		status=$?
		set -e
	else
		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--prompt "${prompt}" \
			--output-format text \
			--yolo
		return $?
	fi

	if [[ "${status}" -eq 0 ]]; then
		return 0
	fi

	if [[ -n "${fallback_model}" ]] && [[ "${fallback_model}" != "${gemini_model}" ]] && rg -qi -- 'model .* not found|unknown model|invalid model|invalid value|unsupported model' "${output_file}"; then
		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--prompt "${prompt}" \
			--model "${fallback_model}" \
			--output-format text \
			--yolo
		return $?
	fi

	if rg -qi -- 'unknown option.*model' "${output_file}"; then
		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--prompt "${prompt}" \
			--output-format text \
			--yolo
		return $?
	fi

	return "${status}"
}

run_noninteractive_adapter
