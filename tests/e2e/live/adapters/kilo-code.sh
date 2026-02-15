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

	# Kilo defaults to a TUI; use `kilo run` for non-interactive messaging.
	# Use JSON event stream output to make token detection robust.
	# Kilo expects the Gemini key under Google's env var name.
	GOOGLE_GENERATIVE_AI_API_KEY="${GOOGLE_GENERATIVE_AI_API_KEY:-${GEMINI_API_KEY:-}}" \
		run_safehouse_command "${output_file}" \
		"${AGENT_BIN}" \
		run \
		--format json \
		--auto \
		"${prompt}"
}

run_noninteractive_adapter
