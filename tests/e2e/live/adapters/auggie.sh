#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck source=tests/e2e/live/adapters/lib/noninteractive-common.sh
source "${SCRIPT_DIR}/lib/noninteractive-common.sh"

ADAPTER_NAME="auggie"
AUTH_PATTERNS=(
	'api key'
	'authentication'
	'not logged in'
	'login'
	'unauthorized'
	'rate limit'
	'quota'
)

ensure_auggie_permissions() {
	# Auggie has no CLI flag to bypass its internal approval system.
	# Instead, configure tool permissions via settings.json so the macOS
	# sandbox (not auggie's own prompts) is the sole enforcement layer.
	local settings_dir="${HOME}/.augment"
	local settings_file="${settings_dir}/settings.json"

	if [[ -f "${settings_file}" ]]; then
		return 0
	fi

	mkdir -p "${settings_dir}"
	cat >"${settings_file}" <<-'SETTINGS'
	{
	  "toolPermissions": [
	    { "toolName": "view", "permission": { "type": "allow" } },
	    { "toolName": "str-replace-editor", "permission": { "type": "allow" } },
	    { "toolName": "save-file", "permission": { "type": "allow" } },
	    { "toolName": "launch-process", "permission": { "type": "allow" } },
	    { "toolName": "remove-files", "permission": { "type": "allow" } },
	    { "toolName": "codebase-retrieval", "permission": { "type": "allow" } },
	    { "toolName": "grep-search", "permission": { "type": "allow" } }
	  ]
	}
	SETTINGS
}

run_prompt() {
	local prompt="$1"
	local output_file="$2"

	ensure_auggie_permissions

	# When using API-token auth (common in CI), Auggie requires both:
	# - AUGMENT_API_TOKEN (provided via workflow secret)
	# - AUGMENT_API_URL (tenant/base API URL). Default to production if unset.
	AUGMENT_API_URL="${AUGMENT_API_URL:-https://api.augmentcode.com}" \
		run_safehouse_command "${output_file}" \
		"${AGENT_BIN}" \
		--print \
		--output-format text \
		--workspace-root "${WORKDIR}" \
		"${prompt}"
}

run_noninteractive_adapter
