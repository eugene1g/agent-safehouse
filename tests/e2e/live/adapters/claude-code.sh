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

run_prompt() {
	local prompt="$1"
	local output_file="$2"

	run_safehouse_command "${output_file}" \
		"${AGENT_BIN}" \
		--print \
		--output-format json \
		--permission-mode bypassPermissions \
		"${prompt}"
}

run_noninteractive_adapter
