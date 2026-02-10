#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
PROFILES_DIR="${ROOT_DIR}/profiles"
HOME_DIR_TEMPLATE_TOKEN="__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__"

home_dir="${HOME:-}"
enable_csv_list=""
enable_docker_integration=0
enable_macos_gui_integration=0
enable_electron_integration=0
output_path=""
add_dirs_ro_list_cli=""
add_dirs_list_cli=""
config_add_dirs_ro_list=""
config_add_dirs_list=""
combined_add_dirs_ro_list=""
combined_add_dirs_list=""
append_profile_paths=()
env_add_dirs_ro_list="${SAFEHOUSE_ADD_DIRS_RO:-}"
env_add_dirs_list="${SAFEHOUSE_ADD_DIRS:-}"
workdir_value=""
workdir_flag_set=0
workdir_env_value=""
workdir_env_set=0
invocation_cwd="$(pwd -P)"
effective_workdir=""
workdir_config_filename=".safehouse"
workdir_config_path=""

readonly_paths=()
rw_paths=()
readonly_count=0
rw_count=0

stdout_policy=0

if [[ "${SAFEHOUSE_WORKDIR+x}" == "x" ]]; then
  workdir_env_set=1
  workdir_env_value="${SAFEHOUSE_WORKDIR}"
fi

# shellcheck source=bin/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=bin/lib/policy.sh
source "${SCRIPT_DIR}/lib/policy.sh"
# shellcheck source=bin/lib/cli.sh
source "${SCRIPT_DIR}/lib/cli.sh"

main "$@"
