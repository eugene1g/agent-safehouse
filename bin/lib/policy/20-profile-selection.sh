# Agent/app profile selection and requirement resolution.

append_selected_agent_profile() {
  local candidate="$1"
  local reason="${2:-}"
  local idx selected

  for idx in "${!selected_agent_profile_basenames[@]}"; do
    selected="${selected_agent_profile_basenames[$idx]}"
    if [[ "$selected" == "$candidate" ]]; then
      if [[ -n "$reason" && -z "${selected_agent_profile_reasons[$idx]:-}" ]]; then
        selected_agent_profile_reasons[$idx]="$reason"
      fi
      return 0
    fi
  done

  selected_agent_profile_basenames+=("$candidate")
  selected_agent_profile_reasons+=("$reason")
}

resolve_selected_agent_profiles() {
  local cmd app_bundle_base

  if [[ "$selected_agent_profiles_resolved" -eq 1 ]]; then
    return 0
  fi
  selected_agent_profiles_resolved=1
  selected_agent_profile_basenames=()
  selected_agent_profile_reasons=()

  if [[ "$enable_all_agents_profiles" -eq 1 ]]; then
    return 0
  fi

  cmd="$(to_lowercase "${invoked_command_profile_basename:-${invoked_command_basename:-}}")"
  app_bundle_base="$(to_lowercase "$(basename "${invoked_command_app_bundle:-}")")"

  case "$app_bundle_base" in
    claude.app)
      append_selected_agent_profile "claude-app.sb" "app bundle match: ${app_bundle_base}"
      ;;
    "visual studio code.app"|"visual studio code - insiders.app")
      append_selected_agent_profile "vscode-app.sb" "app bundle match: ${app_bundle_base}"
      ;;
  esac

  case "$cmd" in
    aider)
      append_selected_agent_profile "aider.sb" "command basename match: ${cmd}"
      ;;
    amp)
      append_selected_agent_profile "amp.sb" "command basename match: ${cmd}"
      ;;
    auggie)
      append_selected_agent_profile "auggie.sb" "command basename match: ${cmd}"
      ;;
    claude)
      if [[ "$app_bundle_base" != "claude.app" ]]; then
        append_selected_agent_profile "claude-code.sb" "command basename match: ${cmd}"
      fi
      ;;
    claude-code)
      append_selected_agent_profile "claude-code.sb" "command basename match: ${cmd}"
      ;;
    cline)
      append_selected_agent_profile "cline.sb" "command basename match: ${cmd}"
      ;;
    copilot)
      append_selected_agent_profile "copilot-cli.sb" "command basename match: ${cmd}"
      ;;
    codex)
      append_selected_agent_profile "codex.sb" "command basename match: ${cmd}"
      ;;
    cursor|cursor-agent|agent)
      append_selected_agent_profile "cursor-agent.sb" "command basename match: ${cmd}"
      ;;
    droid)
      append_selected_agent_profile "droid.sb" "command basename match: ${cmd}"
      ;;
    gemini)
      append_selected_agent_profile "gemini.sb" "command basename match: ${cmd}"
      ;;
    goose)
      append_selected_agent_profile "goose.sb" "command basename match: ${cmd}"
      ;;
    kilo|kilocode)
      append_selected_agent_profile "kilo-code.sb" "command basename match: ${cmd}"
      ;;
    opencode)
      append_selected_agent_profile "opencode.sb" "command basename match: ${cmd}"
      ;;
    pi)
      append_selected_agent_profile "pi.sb" "command basename match: ${cmd}"
      ;;
  esac
}

should_include_agent_profile_file() {
  local file_path="$1"
  local selected_profile base_name

  if [[ "$file_path" == *"/60-agents/"* && "$enable_all_agents_profiles" -eq 1 ]]; then
    return 0
  fi

  if [[ "$file_path" == *"/65-apps/"* && "$enable_all_apps_profiles" -eq 1 ]]; then
    return 0
  fi

  resolve_selected_agent_profiles
  base_name="${file_path##*/}"

  if [[ "${#selected_agent_profile_basenames[@]}" -gt 0 ]]; then
    for selected_profile in "${selected_agent_profile_basenames[@]}"; do
      if [[ "$selected_profile" == "$base_name" ]]; then
        return 0
      fi
    done
  fi

  return 1
}

resolve_agent_app_profile_paths() {
  local file
  local nullglob_was_set=0
  local LC_ALL=C

  if [[ "$agent_app_profile_paths_resolved" -eq 1 ]]; then
    return 0
  fi

  agent_profile_paths=()
  app_profile_paths=()
  agent_app_profile_paths_resolved=1

  if shopt -q nullglob; then
    nullglob_was_set=1
  fi
  shopt -s nullglob

  for file in "${PROFILES_DIR}/60-agents/"*.sb; do
    [[ -f "$file" ]] || continue
    agent_profile_paths+=("$file")
  done

  for file in "${PROFILES_DIR}/65-apps/"*.sb; do
    [[ -f "$file" ]] || continue
    app_profile_paths+=("$file")
  done

  if [[ "$nullglob_was_set" -ne 1 ]]; then
    shopt -u nullglob
  fi
}

resolve_optional_integration_profile_paths() {
  local file
  local nullglob_was_set=0
  local LC_ALL=C

  if [[ "$optional_integration_profile_paths_resolved" -eq 1 ]]; then
    return 0
  fi

  optional_integration_profile_paths=()
  optional_integration_profile_paths_resolved=1

  if shopt -q nullglob; then
    nullglob_was_set=1
  fi
  shopt -s nullglob

  for file in "${PROFILES_DIR}/55-integrations-optional/"*.sb; do
    [[ -f "$file" ]] || continue
    optional_integration_profile_paths+=("$file")
  done

  if [[ "$nullglob_was_set" -ne 1 ]]; then
    shopt -u nullglob
  fi
}

append_selected_profile_requirement_token() {
  local token="$1"

  [[ -n "$token" ]] || return 0
  array_contains_exact "$token" "${selected_profile_requirement_tokens[@]-}" && return 0
  selected_profile_requirement_tokens+=("$token")
}

append_enabled_optional_requirement_token() {
  local token="$1"

  [[ -n "$token" ]] || return 0
  array_contains_exact "$token" "${enabled_optional_requirement_tokens[@]-}" && return 0
  enabled_optional_requirement_tokens+=("$token")
}

append_requirement_tokens_from_csv() {
  local raw_csv="$1"
  local target="$2"
  local remainder entry normalized_entry

  remainder="$raw_csv"

  while :; do
    if [[ "$remainder" == *,* ]]; then
      entry="${remainder%%,*}"
      remainder="${remainder#*,}"
    else
      entry="$remainder"
      remainder=""
    fi

    normalized_entry="$(to_lowercase "$(trim_whitespace "$entry")")"
    if [[ -n "$normalized_entry" ]]; then
      case "$target" in
        selected)
          append_selected_profile_requirement_token "$normalized_entry"
          ;;
        enabled-optional)
          append_enabled_optional_requirement_token "$normalized_entry"
          ;;
        *)
          echo "Unknown requirement token cache target: ${target}" >&2
          exit 1
          ;;
      esac
    fi

    [[ -n "$remainder" ]] || break
  done
}

append_profile_requirement_tokens_to_cache() {
  local profile_path="$1"
  local target="$2"
  local line raw_requirements

  [[ -f "$profile_path" ]] || return 0

  while IFS= read -r line; do
    [[ "$line" == *'$$require='*'$$'* ]] || continue
    raw_requirements="${line#*\$\$require=}"
    raw_requirements="${raw_requirements%%\$\$*}"
    raw_requirements="$(trim_whitespace "$raw_requirements")"
    [[ -n "$raw_requirements" ]] || continue
    append_requirement_tokens_from_csv "$raw_requirements" "$target"
  done < "$profile_path"
}

resolve_selected_profile_requirement_tokens() {
  local file

  if [[ "$selected_profile_requirement_tokens_resolved" -eq 1 ]]; then
    return 0
  fi

  selected_profile_requirement_tokens=()
  selected_profile_requirement_tokens_resolved=1
  selected_profiles_require_keychain=0
  selected_profiles_require_keychain_resolved=1

  resolve_agent_app_profile_paths

  for file in "${agent_profile_paths[@]-}"; do
    should_include_agent_profile_file "$file" || continue
    append_profile_requirement_tokens_to_cache "$file" "selected"
  done

  for file in "${app_profile_paths[@]-}"; do
    should_include_agent_profile_file "$file" || continue
    append_profile_requirement_tokens_to_cache "$file" "selected"
  done

  if array_contains_exact "$keychain_requirement_token" "${selected_profile_requirement_tokens[@]-}"; then
    selected_profiles_require_keychain=1
  fi
}

resolve_enabled_optional_requirement_tokens() {
  local feature profile_path

  if [[ "$enabled_optional_requirement_tokens_resolved" -eq 1 ]]; then
    return 0
  fi

  enabled_optional_requirement_tokens=()
  enabled_optional_requirement_tokens_resolved=1

  for feature in "${optional_integration_features[@]-}"; do
    optional_integration_feature_enabled "$feature" || continue
    profile_path="$(optional_integration_profile_path_from_feature "$feature")" || continue
    append_profile_requirement_tokens_to_cache "$profile_path" "enabled-optional"
  done
}

selected_profiles_require_integration() {
  local integration="$1"
  local integration_normalized

  integration_normalized="$(to_lowercase "$integration")"

  if [[ "$integration_normalized" == "$keychain_requirement_token" && "$selected_profiles_require_keychain_resolved" -eq 1 ]]; then
    [[ "$selected_profiles_require_keychain" -eq 1 ]]
    return
  fi

  resolve_selected_profile_requirement_tokens
  array_contains_exact "$integration_normalized" "${selected_profile_requirement_tokens[@]-}"
}

append_profile_runtime_env_default() {
  local raw_entry="$1"
  local source_profile="$2"
  local key value idx

  if [[ "$raw_entry" != *=* ]]; then
    echo "Invalid \$\$exec-env-default metadata in ${source_profile}: expected NAME=VALUE." >&2
    exit 1
  fi

  key="$(trim_whitespace "${raw_entry%%=*}")"
  value="$(trim_whitespace "${raw_entry#*=}")"

  if ! validate_env_var_name "$key"; then
    echo "Invalid \$\$exec-env-default metadata in ${source_profile}: ${key} is not a valid environment variable name." >&2
    exit 1
  fi

  validate_sb_string "$value" "\$\$exec-env-default value in ${source_profile}" || exit 1

  for idx in "${!profile_runtime_env_defaults[@]}"; do
    if [[ "${profile_runtime_env_defaults[$idx]%%=*}" == "$key" ]]; then
      profile_runtime_env_defaults[$idx]="${key}=${value}"
      return 0
    fi
  done

  profile_runtime_env_defaults+=("${key}=${value}")
}

append_profile_runtime_env_defaults_from_file() {
  local profile_path="$1"
  local line metadata_entry

  [[ -f "$profile_path" ]] || return 0

  while IFS= read -r line; do
    [[ "$line" == *'$$exec-env-default='*'$$'* ]] || continue
    metadata_entry="${line#*\$\$exec-env-default=}"
    metadata_entry="${metadata_entry%%\$\$*}"
    metadata_entry="$(trim_whitespace "$metadata_entry")"
    [[ -n "$metadata_entry" ]] || continue
    append_profile_runtime_env_default "$metadata_entry" "$profile_path"
  done < "$profile_path"
}

resolve_profile_runtime_env_defaults() {
  local file profile_basename

  if [[ "$profile_runtime_env_defaults_resolved" -eq 1 ]]; then
    return 0
  fi

  profile_runtime_env_defaults=()
  profile_runtime_env_defaults_resolved=1

  resolve_optional_integration_profile_paths
  resolve_agent_app_profile_paths

  for file in "${optional_integration_profile_paths[@]-}"; do
    profile_basename="${file##*/}"
    should_include_optional_integration_profile "$profile_basename" || continue
    append_profile_runtime_env_defaults_from_file "$file"
  done

  for file in "${agent_profile_paths[@]-}"; do
    should_include_agent_profile_file "$file" || continue
    append_profile_runtime_env_defaults_from_file "$file"
  done

  for file in "${app_profile_paths[@]-}"; do
    should_include_agent_profile_file "$file" || continue
    append_profile_runtime_env_defaults_from_file "$file"
  done

  for file in "${append_profile_paths[@]-}"; do
    [[ -n "$file" ]] || continue
    append_profile_runtime_env_defaults_from_file "$file"
  done
}
