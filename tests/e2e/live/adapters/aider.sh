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

detect_aider_model() {
	if [[ -n "${SAFEHOUSE_E2E_AIDER_MODEL:-}" ]]; then
		printf '%s' "${SAFEHOUSE_E2E_AIDER_MODEL}"
	fi
}

run_prompt() {
	local prompt="$1"
	local output_file="$2"
	local status=0
	local -a extra_args=()
	local -a model_args=()
	local aider_model=""
	local -a cmd_args=()

	aider_model="$(detect_aider_model || true)"
	if [[ -n "${aider_model}" ]]; then
		model_args+=(--model "${aider_model}")
	fi

	# For the negative test: force aider to attempt an OS-level read of the
	# forbidden file via --read, so the sandbox (not aider's LLM) blocks it.
	if [[ "${prompt}" == *"${FORBIDDEN_FILE}"* ]]; then
		extra_args+=(--read "${FORBIDDEN_FILE}")
	fi

	cmd_args=(--message "${prompt}")
	if [[ ${#extra_args[@]} -gt 0 ]]; then
		cmd_args=("${extra_args[@]}" "${cmd_args[@]}")
	fi
	if [[ ${#model_args[@]} -gt 0 ]]; then
		cmd_args=("${model_args[@]}" "${cmd_args[@]}")
	fi
	set +e
	run_safehouse_command "${output_file}" \
		"${AGENT_BIN}" \
		--yes-always \
		--no-pretty \
		--no-check-update \
		"${cmd_args[@]}"
	status=$?
	set -e

	# Fallback for older/newer aider model catalogs if the preferred cheap model
	# alias is unavailable in a given environment.
	if [[ "${status}" -ne 0 ]] && [[ ${#model_args[@]} -gt 0 ]] && rg -qi -- 'model .* not found|unknown model|invalid model|invalid value|unsupported model|unknown option.*model' "${output_file}"; then
		set +e
		run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--yes-always \
			--no-pretty \
			--no-check-update \
			"${extra_args[@]}" \
			--message "${prompt}"
		status=$?
		set -e
	fi

	if [[ "${status}" -eq 0 ]]; then
		return 0
	fi

	if [[ ${#extra_args[@]} -gt 0 ]]; then
		# Negative test: aider may exit non-zero when the sandbox blocks --read.
		# Suppress the exit code so the common library checks the output for
		# denial evidence instead of treating it as an unexpected crash.
		return 0
	fi

	return "${status}"
}

run_noninteractive_adapter
