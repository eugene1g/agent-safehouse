#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
# shellcheck disable=SC2034  # Used by sourced library files.
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
# shellcheck disable=SC2034  # Used by sourced library files.
safehouse_invocation_path="${BASH_SOURCE[0]}"

# shellcheck disable=SC1091
# shellcheck source=lib/bootstrap/source-manifest.sh
source "${SCRIPT_DIR}/lib/bootstrap/source-manifest.sh"

for safehouse_source_file in "${SAFEHOUSE_LIB_SOURCE_MANIFEST[@]}"; do
  # shellcheck source=/dev/null
  source "${SCRIPT_DIR}/lib/${safehouse_source_file}"
done

safehouse_main "$@"
