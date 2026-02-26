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
DENIAL_PATTERNS=(
	'operation not permitted'
	'EPERM'
	'permission denied'
	'access denied'
	'not allowed'
	'outside the allowed workspace'
	'outside the authorized working directory'
	'can.t access or read files'
	'cannot access'
	'retrieve system/hidden secrets'
	'will not read'
	'won.t read or disclose'
)

run_prompt() {
	local prompt="$1"
	local output_file="$2"
	local kilo_model="${SAFEHOUSE_E2E_KILO_MODEL:-}"
	local kilo_fallback_model="${SAFEHOUSE_E2E_KILO_FALLBACK_MODEL:-}"
	local runtime_root
	local state_home
	local cache_home
	local config_home
	local status=0

	runtime_root="${WORKDIR}/.kilo-runtime"
	state_home="${runtime_root}/state"
	cache_home="${runtime_root}/cache"
	config_home="${runtime_root}/config"
	mkdir -p "${state_home}" "${cache_home}" "${config_home}"

	# Kilo defaults to a TUI; use `kilo run` for non-interactive messaging.
	# Use JSON event stream output to make token detection robust.
	# Kilo expects the Gemini key under Google's env var name.
	if [[ -n "${kilo_model}" ]]; then
		set +e
		XDG_STATE_HOME="${state_home}" \
			XDG_CACHE_HOME="${cache_home}" \
			XDG_CONFIG_HOME="${config_home}" \
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
		XDG_STATE_HOME="${state_home}" \
			XDG_CACHE_HOME="${cache_home}" \
			XDG_CONFIG_HOME="${config_home}" \
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
		XDG_STATE_HOME="${state_home}" \
			XDG_CACHE_HOME="${cache_home}" \
			XDG_CONFIG_HOME="${config_home}" \
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
		XDG_STATE_HOME="${state_home}" \
			XDG_CACHE_HOME="${cache_home}" \
			XDG_CONFIG_HOME="${config_home}" \
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
