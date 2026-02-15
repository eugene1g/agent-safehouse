#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AGENTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
BIN_DIR="${AGENTS_ROOT}/bin"
CURSOR_HOME="${SCRIPT_DIR}/home"

if ! command -v curl >/dev/null 2>&1; then
	echo "ERROR: curl is required to install cursor-agent for E2E live tests." >&2
	exit 1
fi
if ! command -v tar >/dev/null 2>&1; then
	echo "ERROR: tar is required to install cursor-agent for E2E live tests." >&2
	exit 1
fi

mkdir -p "${BIN_DIR}" "${CURSOR_HOME}"

INSTALL_URL="${SAFEHOUSE_E2E_CURSOR_AGENT_INSTALL_URL:-https://cursor.com/install}"
TMP_SCRIPT="$(mktemp /tmp/safehouse-e2e-cursor-agent-install.XXXXXX.sh)"
trap 'rm -f "${TMP_SCRIPT}"' EXIT

curl -fsSL "${INSTALL_URL}" -o "${TMP_SCRIPT}"
chmod +x "${TMP_SCRIPT}"

# Cursor's installer is hardcoded to $HOME/.local/* paths. Override HOME so the
# install is fully repo-local and doesn't touch the developer's real home dir.
NO_COLOR=1 HOME="${CURSOR_HOME}" bash "${TMP_SCRIPT}"

if [[ ! -e "${CURSOR_HOME}/.local/bin/cursor-agent" ]]; then
	echo "ERROR: expected cursor-agent symlink missing at ${CURSOR_HOME}/.local/bin/cursor-agent" >&2
	exit 1
fi
if [[ ! -e "${CURSOR_HOME}/.local/bin/agent" ]]; then
	echo "ERROR: expected agent symlink missing at ${CURSOR_HOME}/.local/bin/agent" >&2
	exit 1
fi

ln -sf "${CURSOR_HOME}/.local/bin/cursor-agent" "${BIN_DIR}/cursor-agent"
ln -sf "${CURSOR_HOME}/.local/bin/agent" "${BIN_DIR}/agent"

echo "Installed cursor-agent to ${BIN_DIR}/cursor-agent (repo-local HOME at ${CURSOR_HOME})"
"${BIN_DIR}/cursor-agent" --version || true

