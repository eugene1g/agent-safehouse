#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AGENTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
BIN_DIR="${AGENTS_ROOT}/bin"

if ! command -v curl >/dev/null 2>&1; then
	echo "ERROR: curl is required to install goose for E2E live tests." >&2
	exit 1
fi
if ! command -v tar >/dev/null 2>&1; then
	echo "ERROR: tar is required to install goose for E2E live tests." >&2
	exit 1
fi

mkdir -p "${BIN_DIR}"

GOOSE_INSTALL_URL="${SAFEHOUSE_E2E_GOOSE_INSTALL_URL:-https://raw.githubusercontent.com/block/goose/main/download_cli.sh}"
TMP_SCRIPT="$(mktemp /tmp/safehouse-e2e-goose-install.XXXXXX.sh)"
trap 'rm -f "${TMP_SCRIPT}"' EXIT

curl -fsSL "${GOOSE_INSTALL_URL}" -o "${TMP_SCRIPT}"
chmod +x "${TMP_SCRIPT}"

GOOSE_BIN_DIR="${BIN_DIR}" \
CONFIGURE=false \
bash "${TMP_SCRIPT}"

if [[ ! -x "${BIN_DIR}/goose" ]]; then
	echo "ERROR: goose binary was not installed at ${BIN_DIR}/goose" >&2
	exit 1
fi

echo "Installed goose to ${BIN_DIR}/goose"
"${BIN_DIR}/goose" --version || true

