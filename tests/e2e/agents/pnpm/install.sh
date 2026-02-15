#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

if ! command -v pnpm >/dev/null 2>&1; then
	# Prefer corepack when available (CI and machines without mise/global pnpm).
	if command -v corepack >/dev/null 2>&1; then
		corepack enable >/dev/null 2>&1 || true
		corepack prepare pnpm@latest --activate >/dev/null 2>&1 || true
	fi
fi

if ! command -v pnpm >/dev/null 2>&1; then
	echo "ERROR: pnpm is required to install E2E agent CLIs." >&2
	echo "Hint: install Node >=16 and run: corepack enable" >&2
	exit 1
fi

pnpm --ignore-workspace -C "${SCRIPT_DIR}" install --no-lockfile
