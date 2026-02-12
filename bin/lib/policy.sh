# shellcheck shell=bash

POLICY_LIB_DIR="${SCRIPT_DIR}/lib/policy"

# shellcheck source=bin/lib/policy/10-options.sh
source "${POLICY_LIB_DIR}/10-options.sh"
# shellcheck source=bin/lib/policy/20-profile-selection.sh
source "${POLICY_LIB_DIR}/20-profile-selection.sh"
# shellcheck source=bin/lib/policy/30-assembly.sh
source "${POLICY_LIB_DIR}/30-assembly.sh"
# shellcheck source=bin/lib/policy/40-generate.sh
source "${POLICY_LIB_DIR}/40-generate.sh"
