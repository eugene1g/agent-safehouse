#!/usr/bin/env bash
set -euo pipefail

# Test harness for agent-safehouse sandbox policies.
# Generates policies via generate-policy.sh, then runs canary commands under
# sandbox-exec to verify that allowed operations succeed and denied operations fail.
#
# Usage:
#   ./tests/run.sh

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
GENERATOR="${REPO_ROOT}/bin/generate-policy.sh"
SAFEHOUSE="${REPO_ROOT}/bin/safehouse"

# Quick check: bail immediately if we're already inside a sandbox.
# sandbox-exec cannot nest, so attempting a trivial child sandbox is the
# fastest reliable detection method.
_preflight="$(mktemp /tmp/safehouse-preflight.XXXXXX)"
printf '(version 1)\n(allow default)\n' > "$_preflight"
if ! sandbox-exec -f "$_preflight" -- /bin/echo ok >/dev/null 2>&1; then
  rm -f "$_preflight"
  echo "ERROR: tests cannot run inside an existing sandbox (sandbox-exec cannot nest)." >&2
  echo "Run this script from a normal (unsandboxed) terminal session." >&2
  exit 2
fi
rm -f "$_preflight"
unset _preflight

source "${SCRIPT_DIR}/lib/common.sh"
source "${SCRIPT_DIR}/lib/setup.sh"

for section_file in "${SCRIPT_DIR}/sections"/*.sh; do
  source "$section_file"
done

validate_test_args "$0" "$@"
validate_prerequisites
preflight_sandbox_exec
setup_test_environment
trap cleanup_test_environment EXIT

run_registered_sections
print_summary_and_exit
