#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
AGENTS_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
BIN_DIR="${AGENTS_ROOT}/bin"
VENV_DIR="${SCRIPT_DIR}/venv"

pick_python() {
	local py=""
	for py in "${SAFEHOUSE_E2E_PYTHON:-}" python3.12 python3.11 python3.10 python3; do
		[[ -n "${py}" ]] || continue
		if command -v "${py}" >/dev/null 2>&1; then
			printf '%s\n' "${py}"
			return 0
		fi
	done
	return 1
}

python_cmd="$(pick_python)" || {
	echo "ERROR: missing Python. Install Python 3.12+ (but <3.13) and retry (or set SAFEHOUSE_E2E_PYTHON)." >&2
	exit 1
}

python_version="$("${python_cmd}" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")')"
case "${python_version}" in
3.10|3.11|3.12) ;;
*)
	echo "ERROR: aider-chat requires Python >=3.10,<3.13; found ${python_cmd} (${python_version})." >&2
	echo "Hint: install python3.12 and re-run with: SAFEHOUSE_E2E_PYTHON=python3.12 ./tests/e2e/agents/python/install.sh" >&2
	exit 1
	;;
esac

if [[ -d "${VENV_DIR}" ]]; then
	venv_version="$("${VENV_DIR}/bin/python" -c 'import sys; print(f"{sys.version_info.major}.{sys.version_info.minor}")' 2>/dev/null || true)"
	if [[ "${venv_version}" != "${python_version}" ]]; then
		bak="${VENV_DIR}.bak.$(date +%s)"
		mv "${VENV_DIR}" "${bak}"
		echo "INFO: moved existing venv (${venv_version}) -> ${bak}"
	fi
fi

"${python_cmd}" -m venv "${VENV_DIR}"

VENV_PY="${VENV_DIR}/bin/python3"
if [[ ! -x "${VENV_PY}" ]]; then
	VENV_PY="${VENV_DIR}/bin/python"
fi
if [[ ! -x "${VENV_PY}" ]]; then
	echo "ERROR: venv python not found under ${VENV_DIR}/bin." >&2
	exit 1
fi

PIP_SPEC="${SAFEHOUSE_E2E_AIDER_PIP_SPEC:-aider-chat}"
"${VENV_PY}" -m pip install -U pip setuptools wheel >/dev/null
"${VENV_PY}" -m pip install -U "${PIP_SPEC}"

mkdir -p "${BIN_DIR}"

if [[ ! -x "${VENV_DIR}/bin/aider" ]]; then
	echo "ERROR: aider entrypoint not found after install: ${VENV_DIR}/bin/aider" >&2
	exit 1
fi

ln -sf "${VENV_DIR}/bin/aider" "${BIN_DIR}/aider"

echo "Installed aider to ${BIN_DIR}/aider"
"${BIN_DIR}/aider" --version || true
