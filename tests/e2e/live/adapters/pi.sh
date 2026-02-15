#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="pi"
AUTH_PATTERNS=(
	'api key'
	'authentication'
	'not logged in'
	'login'
	'unauthorized'
	'rate limit'
	'quota'
	'no provider'
	'no model'
)

detect_pi_provider() {
	if [[ -n "${SAFEHOUSE_E2E_PI_PROVIDER:-}" ]]; then
		printf '%s' "${SAFEHOUSE_E2E_PI_PROVIDER}"
		return 0
	fi

	if [[ -n "${OPENAI_API_KEY:-}" ]]; then
		printf '%s' "openai"
		return 0
	fi
	if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
		printf '%s' "anthropic"
		return 0
	fi
	if [[ -n "${GEMINI_API_KEY:-}" || -n "${GOOGLE_API_KEY:-}" ]]; then
		printf '%s' "google"
		return 0
	fi

	printf '%s' "openai"
}

detect_pi_model() {
	if [[ -n "${SAFEHOUSE_E2E_PI_MODEL:-}" ]]; then
		printf '%s' "${SAFEHOUSE_E2E_PI_MODEL}"
		return 0
	fi
}

run_prompt() {
	local prompt="$1"
	local output_file="$2"
	local provider model

	provider="$(detect_pi_provider)"
	model="$(detect_pi_model || true)"

	if [[ -n "${model}" ]]; then
		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--provider "${provider}" \
			--model "${model}" \
			--no-extensions \
			--no-session \
			--print \
			"${prompt}"
		return $?
	fi

	run_safehouse_command "${output_file}" \
		"${AGENT_BIN}" \
		--provider "${provider}" \
		--no-extensions \
		--no-session \
		--print \
		"${prompt}"
}

run_noninteractive_adapter
