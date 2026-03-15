# shellcheck shell=bash
# shellcheck disable=SC2034

PROFILES_DIR="${ROOT_DIR}/profiles"
HOME_DIR_TEMPLATE_TOKEN="__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__"
WORKTREES_COMMON_DIR_STATUS_TEMPLATE_TOKEN="__SAFEHOUSE_REPLACE_ME_WITH_GIT_WORKTREE_COMMON_DIR_STATUS__"
WORKTREES_LINKED_PATHS_STATUS_TEMPLATE_TOKEN="__SAFEHOUSE_REPLACE_ME_WITH_GIT_LINKED_WORKTREE_PATHS_STATUS__"
safehouse_project_name="Agent Safehouse"
safehouse_project_version_file="${ROOT_DIR}/VERSION"
safehouse_project_version_embedded="__SAFEHOUSE_PROJECT_VERSION__"
safehouse_project_url="https://agent-safehouse.dev"
safehouse_project_github_url="https://github.com/eugene1g/agent-safehouse"
safehouse_project_release_asset_url="${safehouse_project_github_url}/releases/latest/download/safehouse.sh"
safehouse_project_head_asset_url="https://raw.githubusercontent.com/eugene1g/agent-safehouse/main/dist/safehouse.sh"
safehouse_workdir_config_filename=".safehouse"

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
