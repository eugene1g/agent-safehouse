#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="opencode"
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
	'external_directory'
	'outside the allowed workspace'
)

run_prompt() {
	local prompt="$1"
	local output_file="$2"

	# OpenCode's Gemini provider expects the key under Google's env var name.
	# --yolo bypasses opencode's internal approval prompts so the macOS sandbox
	# is the sole enforcement layer.
	GOOGLE_GENERATIVE_AI_API_KEY="${GOOGLE_GENERATIVE_AI_API_KEY:-${GEMINI_API_KEY:-}}" \
		run_safehouse_command "${output_file}" \
		"${AGENT_BIN}" \
		run \
		--format default \
		"${prompt}"
}

run_noninteractive_adapter
