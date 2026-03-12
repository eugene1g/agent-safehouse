#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
PROFILES_DIR="${ROOT_DIR}/profiles"
HOME_DIR_TEMPLATE_TOKEN="__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__"
safehouse_invocation_path="${BASH_SOURCE[0]}"
safehouse_project_name="Agent Safehouse"
safehouse_project_version_file="${ROOT_DIR}/VERSION"
safehouse_project_version_embedded="__SAFEHOUSE_PROJECT_VERSION__"
safehouse_project_url="https://agent-safehouse.dev"
safehouse_project_github_url="https://github.com/eugene1g/agent-safehouse"
safehouse_project_release_asset_url="${safehouse_project_github_url}/releases/latest/download/safehouse.sh"
safehouse_project_head_asset_url="https://raw.githubusercontent.com/eugene1g/agent-safehouse/main/dist/safehouse.sh"

resolve_safehouse_project_version() {
  local version=""

  if [[ -r "${safehouse_project_version_file:-}" ]]; then
    IFS= read -r version < "$safehouse_project_version_file" || true
    version="${version%%$'\r'}"
    if [[ -n "$version" ]]; then
      printf '%s\n' "$version"
      return 0
    fi
  fi

  if [[ -n "${safehouse_project_version_embedded:-}" && "$safehouse_project_version_embedded" != "__SAFEHOUSE_PROJECT_VERSION__" ]]; then
    printf '%s\n' "$safehouse_project_version_embedded"
    return 0
  fi

  printf 'unknown\n'
}

safehouse_project_version="$(resolve_safehouse_project_version)"
readonly safehouse_project_version

home_dir="${HOME:-}"
enable_csv_list=""
# shellcheck disable=SC2034 # enable_*_integration vars are read/written via indirect references (${!var_name})
{
enable_docker_integration=0
enable_kubectl_integration=0
enable_macos_gui_integration=0
enable_electron_integration=0
enable_chromium_headless_integration=0
enable_chromium_full_integration=0
enable_ssh_integration=0
enable_spotlight_integration=0
enable_cleanshot_integration=0
enable_clipboard_integration=0
enable_onepassword_integration=0
enable_cloud_credentials_integration=0
enable_agent_browser_integration=0
enable_browser_native_messaging_integration=0
enable_shell_init_integration=0
enable_process_control_integration=0
enable_lldb_integration=0
enable_xcode_integration=0
}
optional_integration_features=(
  docker
  kubectl
  macos-gui
  electron
  chromium-headless
  chromium-full
  ssh
  spotlight
  cleanshot
  clipboard
  1password
  cloud-credentials
  agent-browser
  browser-native-messaging
  shell-init
  process-control
  lldb
  xcode
)
supported_enable_features="docker, kubectl, macos-gui, electron, chromium-headless, chromium-full, ssh, spotlight, cleanshot, clipboard, 1password, cloud-credentials, agent-browser, browser-native-messaging, shell-init, process-control, lldb, xcode, all-agents, all-apps, wide-read"
enable_all_agents_profiles=0
enable_all_apps_profiles=0
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
invoked_command_profile_path=""
invoked_command_profile_basename=""
invoked_command_app_bundle=""
selected_agent_profile_basenames=()
selected_agent_profile_reasons=()
selected_agent_profiles_resolved=0
agent_profile_paths=()
app_profile_paths=()
agent_app_profile_paths_resolved=0
keychain_requirement_token="55-integrations-optional/keychain.sb"
selected_profiles_require_keychain=0
selected_profiles_require_keychain_resolved=0
selected_profile_requirement_tokens=()
selected_profile_requirement_tokens_resolved=0
optional_integration_profile_paths=()
optional_integration_profile_paths_resolved=0
enabled_optional_requirement_tokens=()
enabled_optional_requirement_tokens_resolved=0
optional_integrations_explicit_included=()
optional_integrations_implicit_included=()
optional_integrations_not_included=()

readonly_paths=()
rw_paths=()
readonly_count=0
rw_count=0

stdout_policy=0
explain_mode=0
runtime_env_mode="sanitized"
runtime_env_file=""
runtime_env_file_resolved=""
runtime_env_pass_names=()
profile_runtime_env_defaults=()
profile_runtime_env_defaults_resolved=0

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
# shellcheck source=bin/lib/update.sh
source "${SCRIPT_DIR}/lib/update.sh"

main "$@"
