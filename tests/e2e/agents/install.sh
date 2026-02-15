#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

mkdir -p "${SCRIPT_DIR}/bin"

# ── Launch each installer in parallel ───────────────────────────────
pids=()
labels=()

if [[ "${SAFEHOUSE_E2E_INSTALL_PNPM_AGENTS:-1}" == "1" ]]; then
	echo "==> Installing: node agents (pnpm)"
	"${SCRIPT_DIR}/pnpm/install.sh" &
	pids+=($!)
	labels+=("node agents (pnpm)")
fi
if [[ "${SAFEHOUSE_E2E_INSTALL_PYTHON_AGENTS:-1}" == "1" ]]; then
	echo "==> Installing: python agents (aider)"
	"${SCRIPT_DIR}/python/install.sh" &
	pids+=($!)
	labels+=("python agents (aider)")
fi
if [[ "${SAFEHOUSE_E2E_INSTALL_GOOSE:-1}" == "1" ]]; then
	echo "==> Installing: goose (github release)"
	"${SCRIPT_DIR}/goose/install.sh" &
	pids+=($!)
	labels+=("goose")
fi
if [[ "${SAFEHOUSE_E2E_INSTALL_CURSOR_AGENT:-1}" == "1" ]]; then
	echo "==> Installing: cursor-agent (cursor.com installer)"
	"${SCRIPT_DIR}/cursor-agent/install.sh" &
	pids+=($!)
	labels+=("cursor-agent")
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
