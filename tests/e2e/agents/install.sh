#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
PNPM_BIN_DIR="${SCRIPT_DIR}/pnpm/node_modules/.bin"
PYTHON_VENV_DIR="${SCRIPT_DIR}/python/venv"
REUSE_EXISTING_INSTALLS="${SAFEHOUSE_E2E_REUSE_EXISTING_INSTALLS:-1}"

mkdir -p "${SCRIPT_DIR}/bin"

reuse_enabled() {
	[[ "${REUSE_EXISTING_INSTALLS}" == "1" ]]
}

have_pnpm_agents() {
	local expected_bins=(
		amp
		auggie
		claude
		cline
		codex
		droid
		gemini
		kilo
		opencode
		pi
	)
	local bin_name

	[[ -d "${PNPM_BIN_DIR}" ]] || return 1
	for bin_name in "${expected_bins[@]}"; do
		[[ -x "${PNPM_BIN_DIR}/${bin_name}" ]] || return 1
	done

	return 0
}

have_python_agent() {
	[[ -x "${PYTHON_VENV_DIR}/bin/aider" && -x "${SCRIPT_DIR}/bin/aider" ]]
}

have_goose_agent() {
	[[ -x "${SCRIPT_DIR}/bin/goose" ]]
}

have_cursor_agent() {
	[[ -x "${SCRIPT_DIR}/bin/cursor-agent" ]]
}

# ── Launch each installer in parallel ───────────────────────────────
pids=()
labels=()

if [[ "${SAFEHOUSE_E2E_INSTALL_PNPM_AGENTS:-1}" == "1" ]]; then
	if reuse_enabled && have_pnpm_agents; then
		echo "==> Reusing: node agents (pnpm)"
	else
		echo "==> Installing: node agents (pnpm)"
		"${SCRIPT_DIR}/pnpm/install.sh" &
		pids+=($!)
		labels+=("node agents (pnpm)")
	fi
fi
if [[ "${SAFEHOUSE_E2E_INSTALL_PYTHON_AGENTS:-1}" == "1" ]]; then
	if reuse_enabled && have_python_agent; then
		echo "==> Reusing: python agents (aider)"
	else
		echo "==> Installing: python agents (aider)"
		"${SCRIPT_DIR}/python/install.sh" &
		pids+=($!)
		labels+=("python agents (aider)")
	fi
fi
if [[ "${SAFEHOUSE_E2E_INSTALL_GOOSE:-1}" == "1" ]]; then
	if reuse_enabled && have_goose_agent; then
		echo "==> Reusing: goose"
	else
		echo "==> Installing: goose (github release)"
		"${SCRIPT_DIR}/goose/install.sh" &
		pids+=($!)
		labels+=("goose")
	fi
fi
if [[ "${SAFEHOUSE_E2E_INSTALL_CURSOR_AGENT:-1}" == "1" ]]; then
	if reuse_enabled && have_cursor_agent; then
		echo "==> Reusing: cursor-agent"
	else
		echo "==> Installing: cursor-agent (cursor.com installer)"
		"${SCRIPT_DIR}/cursor-agent/install.sh" &
		pids+=($!)
		labels+=("cursor-agent")
	fi
fi

# ── Wait for all installers and report failures ────────────────────
failed=0
for i in "${!pids[@]}"; do
	if ! wait "${pids[$i]}"; then
		echo "ERROR: install of '${labels[$i]}' failed" >&2
		failed=1
	fi
done

if [[ "$failed" -ne 0 ]]; then
	exit 1
fi

echo ""
echo "Installed repo-local agent binaries:"
ls -la "${SCRIPT_DIR}/bin" || true
