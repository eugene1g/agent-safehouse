#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="cursor-agent"
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

	run_safehouse_command "${output_file}" \
		"${AGENT_BIN}" \
		--print \
		--output-format text \
		--trust \
		--sandbox disabled \
		--force \
		--workspace "${WORKDIR}" \
		"${prompt}"
}

run_noninteractive_adapter
