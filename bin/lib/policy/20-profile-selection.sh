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

  cmd="$(to_lowercase "${invoked_command_basename:-}")"
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

  if [[ "$enable_all_agents_profiles" -eq 1 ]]; then
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

profile_declares_requirement() {
  local profile_path="$1"
  local required_integration="$2"
  local required_normalized line raw_requirements entry normalized_entry
  local -a requirement_entries=()

  if [[ ! -f "$profile_path" ]]; then
    return 1
  fi

  required_normalized="$(to_lowercase "$required_integration")"

  while IFS= read -r line; do
    [[ "$line" == *'$$require='*'$$'* ]] || continue
    raw_requirements="${line#*\$\$require=}"
    raw_requirements="${raw_requirements%%\$\$*}"
    raw_requirements="$(trim_whitespace "$raw_requirements")"
    [[ -n "$raw_requirements" ]] || continue

    IFS=',' read -r -a requirement_entries <<< "$raw_requirements"
    for entry in "${requirement_entries[@]}"; do
      normalized_entry="$(to_lowercase "$(trim_whitespace "$entry")")"
      [[ -n "$normalized_entry" ]] || continue
      if [[ "$normalized_entry" == "$required_normalized" ]]; then
        return 0
      fi
    done
  done < "$profile_path"

  return 1
}

selected_profiles_require_integration() {
  local integration="$1"
  local integration_normalized selected_profile profile_path file
  local requires_integration=0

  integration_normalized="$(to_lowercase "$integration")"

  if [[ "$integration_normalized" == "$keychain_requirement_token" && "$selected_profiles_require_keychain_resolved" -eq 1 ]]; then
    [[ "$selected_profiles_require_keychain" -eq 1 ]]
    return
  fi

  if [[ "$enable_all_agents_profiles" -eq 1 ]]; then
    while IFS= read -r file; do
      [[ -n "$file" ]] || continue
      if profile_declares_requirement "$file" "$integration_normalized"; then
        requires_integration=1
        break
      fi
    done < <(find "${PROFILES_DIR}/60-agents" "${PROFILES_DIR}/65-apps" -maxdepth 1 -type f -name '*.sb' | LC_ALL=C sort)
  else
    resolve_selected_agent_profiles
    if [[ "${#selected_agent_profile_basenames[@]}" -gt 0 ]]; then
      for selected_profile in "${selected_agent_profile_basenames[@]}"; do
        profile_path="${PROFILES_DIR}/60-agents/${selected_profile}"
        if profile_declares_requirement "$profile_path" "$integration_normalized"; then
          requires_integration=1
          break
        fi

        profile_path="${PROFILES_DIR}/65-apps/${selected_profile}"
        if profile_declares_requirement "$profile_path" "$integration_normalized"; then
          requires_integration=1
          break
        fi
      done
    fi
  fi

  if [[ "$integration_normalized" == "$keychain_requirement_token" ]]; then
    selected_profiles_require_keychain="$requires_integration"
    selected_profiles_require_keychain_resolved=1
  fi

  [[ "$requires_integration" -eq 1 ]]
}
