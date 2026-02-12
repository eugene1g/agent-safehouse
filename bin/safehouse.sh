#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
PROFILES_DIR="${ROOT_DIR}/profiles"
HOME_DIR_TEMPLATE_TOKEN="__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__"
safehouse_project_name="Agent Safehouse"
safehouse_project_url="https://agent-safehouse.dev"
safehouse_project_github_url="https://github.com/eugene1g/agent-safehouse"

home_dir="${HOME:-}"
enable_csv_list=""
# shellcheck disable=SC2034 # enable_*_integration vars are read/written via indirect references (${!var_name})
{
enable_docker_integration=0
enable_kubectl_integration=0
enable_macos_gui_integration=0
enable_electron_integration=0
enable_ssh_integration=0
enable_spotlight_integration=0
enable_cleanshot_integration=0
enable_onepassword_integration=0
enable_cloud_credentials_integration=0
enable_browser_native_messaging_integration=0
}
optional_integration_features=(
  docker
  kubectl
  macos-gui
  electron
  ssh
  spotlight
  cleanshot
  1password
  cloud-credentials
  browser-native-messaging
)
supported_enable_features="docker, kubectl, macos-gui, electron, ssh, spotlight, cleanshot, 1password, cloud-credentials, browser-native-messaging, all-agents, wide-read"
enable_all_agents_profiles=0
enable_wide_read_access=0
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
effective_workdir_source=""
workdir_config_filename=".safehouse"
workdir_config_path=""
workdir_config_loaded=0
workdir_config_found=0
workdir_config_ignored_untrusted=0
trust_workdir_config=0
trust_workdir_config_flag_set=0
trust_workdir_config_env_value=""
trust_workdir_config_env_set=0
trust_workdir_config_source="default"
invoked_command_path=""
invoked_command_basename=""
invoked_command_app_bundle=""
selected_agent_profile_basenames=()
selected_agent_profile_reasons=()
selected_agent_profiles_resolved=0
keychain_requirement_token="55-integrations-optional/keychain.sb"
selected_profiles_require_keychain=0
selected_profiles_require_keychain_resolved=0
optional_integrations_explicit_included=()
optional_integrations_implicit_included=()
optional_integrations_not_included=()

readonly_paths=()
rw_paths=()
readonly_count=0
rw_count=0

stdout_policy=0
explain_mode=0

if [[ "${SAFEHOUSE_WORKDIR+x}" == "x" ]]; then
  workdir_env_set=1
  workdir_env_value="${SAFEHOUSE_WORKDIR}"
fi

if [[ "${SAFEHOUSE_TRUST_WORKDIR_CONFIG+x}" == "x" ]]; then
  trust_workdir_config_env_set=1
  trust_workdir_config_env_value="${SAFEHOUSE_TRUST_WORKDIR_CONFIG}"
fi

# shellcheck source=bin/lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=bin/lib/policy.sh
source "${SCRIPT_DIR}/lib/policy.sh"
# shellcheck source=bin/lib/cli.sh
source "${SCRIPT_DIR}/lib/cli.sh"

main "$@"
