#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="amp"
AUTH_PATTERNS=(
	'api key'
	'authentication'
	'not logged in'
	'login'
	'unauthorized'
	'rate limit'
	'quota'
	'payment required'
)

run_prompt() {
	local prompt="$1"
	local output_file="$2"
	local amp_mode="${SAFEHOUSE_E2E_AMP_MODE:-}"
	local status=0

	local attempt=1
	local max_attempts="${SAFEHOUSE_E2E_AMP_RETRIES:-2}"

	while (( attempt <= max_attempts )); do
		if [[ -n "${amp_mode}" ]]; then
			set +e
			run_safehouse_command "${output_file}" \
				"${AGENT_BIN}" \
				--dangerously-allow-all \
				--mode "${amp_mode}" \
				--execute "${prompt}"
			status=$?
			set -e

			# Fallback for Amp builds that do not support --mode with --execute.
			if [[ "${status}" -ne 0 ]] && rg -qi -- 'unknown option.*mode|unrecognized option.*mode|unexpected argument.*mode|execute mode is not permitted with --mode' "${output_file}"; then
				if run_safehouse_command "${output_file}" \
					"${AGENT_BIN}" \
					--dangerously-allow-all \
					--execute "${prompt}"; then
					return 0
				fi
			elif [[ "${status}" -eq 0 ]]; then
				return 0
			fi
		elif run_safehouse_command "${output_file}" \
			"${AGENT_BIN}" \
			--dangerously-allow-all \
			--execute "${prompt}"; then
			return 0
		fi

			# Amp CLI occasionally exits after a stalled stream; retry once to reduce flakiness.
			if rg -qi -- "stream stalled|no data received|timed out|timeout" "${output_file}"; then
				attempt=$((attempt + 1))
				sleep 2
				continue
			fi

			# Some Amp builds emit the denial token but still exit non-zero on restricted paths.
			if [[ "${prompt}" == *"${FORBIDDEN_FILE}"* ]] && rg -Fq "${DENIAL_TOKEN}" "${output_file}"; then
				return 0
			fi

			return 1
		done

	return 1
}

run_noninteractive_adapter
