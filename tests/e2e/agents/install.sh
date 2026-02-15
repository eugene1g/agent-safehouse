#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

install_section() {
	local label="$1"
	local path="$2"

	echo ""
	echo "==> Installing: ${label}"
	"${path}"
}

mkdir -p "${SCRIPT_DIR}/bin"

if [[ "${SAFEHOUSE_E2E_INSTALL_PNPM_AGENTS:-1}" == "1" ]]; then
	install_section "node agents (pnpm)" "${SCRIPT_DIR}/pnpm/install.sh"
fi
if [[ "${SAFEHOUSE_E2E_INSTALL_PYTHON_AGENTS:-1}" == "1" ]]; then
	install_section "python agents (aider)" "${SCRIPT_DIR}/python/install.sh"
fi
if [[ "${SAFEHOUSE_E2E_INSTALL_GOOSE:-1}" == "1" ]]; then
	install_section "goose (github release)" "${SCRIPT_DIR}/goose/install.sh"
fi
if [[ "${SAFEHOUSE_E2E_INSTALL_CURSOR_AGENT:-1}" == "1" ]]; then
	install_section "cursor-agent (cursor.com installer)" "${SCRIPT_DIR}/cursor-agent/install.sh"
fi

echo ""
echo "Installed repo-local agent binaries:"
ls -la "${SCRIPT_DIR}/bin" || true

