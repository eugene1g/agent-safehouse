#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="aider"
AUTH_PATTERNS=(
	'api key'
	'authentication'
	'not logged in'
	'rate limit'
	'quota'
	'model .* not found'
	'provider .* not configured'
)
DENIAL_PATTERNS=(
	# When --read forces an OS-level open on the forbidden file, the sandbox blocks it.
	'operation not permitted'
	'EPERM'
	'permission denied'
	'sandbox.*deny'
)

run_prompt() {
	local prompt="$1"
	local output_file="$2"
	local extra_args=()

	# For the negative test: force aider to attempt an OS-level read of the
	# forbidden file via --read, so the sandbox (not aider's LLM) blocks it.
	if [[ "${prompt}" == *"${FORBIDDEN_FILE}"* ]]; then
		extra_args+=(--read "${FORBIDDEN_FILE}")
	fi

	if [[ ${#extra_args[@]} -gt 0 ]]; then
		# Negative test: aider may exit non-zero when the sandbox blocks --read.
		# Suppress the exit code so the common library checks the output for
		# denial evidence instead of treating it as an unexpected crash.
		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--yes-always \
			--no-pretty \
			--no-check-update \
			"${extra_args[@]}" \
			--message "${prompt}" || true
	else
		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--yes-always \
			--no-pretty \
			--no-check-update \
			--message "${prompt}"
	fi
}

run_noninteractive_adapter
