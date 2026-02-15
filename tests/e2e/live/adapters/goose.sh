#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="goose"
AUTH_PATTERNS=(
	'api key'
	'authentication'
	'not logged in'
	'login'
	'unauthorized'
	'rate limit'
	'quota'
	'no provider configured'
	'no model configured'
	'run .?goose configure.? first'
	'panicked at'
)

detect_goose_provider() {
	if [[ -n "${SAFEHOUSE_E2E_GOOSE_PROVIDER:-}" ]]; then
		printf '%s' "${SAFEHOUSE_E2E_GOOSE_PROVIDER}"
		return 0
	fi
	if [[ -n "${GOOSE_PROVIDER:-}" ]]; then
		printf '%s' "${GOOSE_PROVIDER}"
		return 0
	fi

	# Prefer env keys already present in the developer shell (do not print them).
	if [[ -n "${OPENAI_API_KEY:-}" ]]; then
		printf '%s' "openai"
		return 0
	fi
	if [[ -n "${ANTHROPIC_API_KEY:-}" ]]; then
		printf '%s' "anthropic"
		return 0
	fi
	if [[ -n "${GOOGLE_API_KEY:-}" || -n "${GEMINI_API_KEY:-}" ]]; then
		printf '%s' "gemini-cli"
		return 0
	fi

	# Fallback: keep openai as the default, since it's the most common setup.
	printf '%s' "openai"
}

detect_goose_model() {
	if [[ -n "${SAFEHOUSE_E2E_GOOSE_MODEL:-}" ]]; then
		printf '%s' "${SAFEHOUSE_E2E_GOOSE_MODEL}"
		return 0
	fi
	if [[ -n "${GOOSE_MODEL:-}" ]]; then
		printf '%s' "${GOOSE_MODEL}"
	fi
}

run_prompt() {
	local prompt="$1"
	local output_file="$2"
	local provider model

	provider="$(detect_goose_provider)"
	model="$(detect_goose_model || true)"

	# GOOSE_MODE=auto bypasses goose's internal approval prompts so the
	# macOS sandbox is the sole enforcement layer.
	if [[ -n "${model}" ]]; then
		GOOSE_MODE=auto \
			run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			run \
			--provider "${provider}" \
			--model "${model}" \
			--text "${prompt}" \
			--no-session \
			--quiet \
			--output-format text
		return $?
	fi

	GOOSE_MODE=auto \
		run_safehouse_command "${output_file}" \
		"${AGENT_BIN}" \
		run \
		--provider "${provider}" \
		--text "${prompt}" \
		--no-session \
		--quiet \
		--output-format text
}

run_noninteractive_adapter
