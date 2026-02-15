#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="kilo-code"
AUTH_PATTERNS=(
	'api key'
	'authentication'
	'not logged in'
	'login'
	'unauthorized'
	'rate limit'
	'quota'
)

run_prompt() {
	local prompt="$1"
	local output_file="$2"
	local kilo_model="${SAFEHOUSE_E2E_KILO_MODEL:-}"
	local kilo_fallback_model="${SAFEHOUSE_E2E_KILO_FALLBACK_MODEL:-}"
	local status=0

	# Kilo defaults to a TUI; use `kilo run` for non-interactive messaging.
	# Use JSON event stream output to make token detection robust.
	# Kilo expects the Gemini key under Google's env var name.
	if [[ -n "${kilo_model}" ]]; then
		set +e
		GOOGLE_GENERATIVE_AI_API_KEY="${GOOGLE_GENERATIVE_AI_API_KEY:-${GEMINI_API_KEY:-}}" \
			run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			run \
			--model "${kilo_model}" \
			--format json \
			--auto \
			"${prompt}"
		status=$?
		set -e
	else
		GOOGLE_GENERATIVE_AI_API_KEY="${GOOGLE_GENERATIVE_AI_API_KEY:-${GEMINI_API_KEY:-}}" \
			run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			run \
			--format json \
			--auto \
			"${prompt}"
		return $?
	fi

	if [[ "${status}" -eq 0 ]]; then
		return 0
	fi

	if [[ -n "${kilo_fallback_model}" ]] && [[ "${kilo_fallback_model}" != "${kilo_model}" ]] && rg -qi -- 'model .* not found|unknown model|invalid model|invalid value|unsupported model' "${output_file}"; then
		GOOGLE_GENERATIVE_AI_API_KEY="${GOOGLE_GENERATIVE_AI_API_KEY:-${GEMINI_API_KEY:-}}" \
			run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			run \
			--model "${kilo_fallback_model}" \
			--format json \
			--auto \
			"${prompt}"
		return $?
	fi

	if rg -qi -- 'unknown option.*model' "${output_file}"; then
		GOOGLE_GENERATIVE_AI_API_KEY="${GOOGLE_GENERATIVE_AI_API_KEY:-${GEMINI_API_KEY:-}}" \
			run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			run \
			--format json \
			--auto \
			"${prompt}"
		return $?
	fi

	return "${status}"
}

run_noninteractive_adapter
