#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="copilot-cli"
AUTH_PATTERNS=(
	'not logged in'
	'login'
	'authentication'
	'unauthorized'
	'rate limit'
	'quota'
	'access denied by policy settings'
	'copilot cli policy setting may be preventing access'
	'copilot settings'
	'required policies have not been enabled'
)
DENIAL_PATTERNS=(
	'operation not permitted'
	'permission denied'
	'access denied'
	'not allowed'
	'outside the allowed'
	'outside the workspace'
	'outside the current workspace'
	'can.t access'
	'cannot access'
	'unable to access'
	'tool call failed'
)

run_prompt() {
	local prompt="$1"
	local output_file="$2"

	run_safehouse_command "${output_file}" \
		"${AGENT_BIN}" \
		--no-auto-update \
		--no-color \
		--no-custom-instructions \
		--no-ask-user \
		--allow-all-tools \
		--output-format text \
		--silent \
		--prompt "${prompt}"
}

run_noninteractive_adapter
