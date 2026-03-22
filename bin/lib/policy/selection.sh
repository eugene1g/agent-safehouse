# shellcheck shell=bash
# shellcheck disable=SC2154

# Purpose: Choose command/app-scoped profiles before dependency expansion.
# Reads globals: policy_req_* inputs resolved by policy/request.sh.
# Writes globals: policy_selection_* arrays.
# Called by: policy/plan.sh.
# Notes: App-bundle matching runs before command matching. --enable=all-* returns early.

policy_selection_agent_profile_keys=()
policy_selection_app_profile_keys=()
policy_selection_selected_scoped_profile_keys=()
policy_selection_selected_scoped_profile_reasons=()

policy_selection_reset() {
  policy_selection_agent_profile_keys=()
  policy_selection_app_profile_keys=()
  policy_selection_selected_scoped_profile_keys=()
  policy_selection_selected_scoped_profile_reasons=()
}

policy_selection_append_scoped_profile() {
  local profile_key="$1"
  local reason="${2:-}"
  local idx existing

  for idx in "${!policy_selection_selected_scoped_profile_keys[@]}"; do
    existing="${policy_selection_selected_scoped_profile_keys[$idx]}"
    if [[ "$existing" == "$profile_key" ]]; then
      if [[ -n "$reason" && -z "${policy_selection_selected_scoped_profile_reasons[$idx]:-}" ]]; then
        policy_selection_selected_scoped_profile_reasons[idx]="$reason"
      fi
      return 0
    fi
  done

  policy_selection_selected_scoped_profile_keys+=("$profile_key")
  policy_selection_selected_scoped_profile_reasons+=("$reason")
}

policy_selection_load_profile_catalog() {
  policy_source_collect_sorted_profile_keys_in_dir policy_selection_agent_profile_keys "profiles/60-agents"
  policy_source_collect_sorted_profile_keys_in_dir policy_selection_app_profile_keys "profiles/65-apps"
  policy_selection_validate_agent_command_alias_catalog || return 1
}

policy_selection_append_all_requested_profiles() {
  local profile_key

  if [[ "$policy_req_enable_all_agents" -eq 1 ]]; then
    if [[ "${#policy_selection_agent_profile_keys[@]}" -gt 0 ]]; then
      for profile_key in "${policy_selection_agent_profile_keys[@]}"; do
        policy_selection_append_scoped_profile "$profile_key" "enabled via --enable=all-agents"
      done
    fi
  fi

  if [[ "$policy_req_enable_all_apps" -eq 1 ]]; then
    if [[ "${#policy_selection_app_profile_keys[@]}" -gt 0 ]]; then
      for profile_key in "${policy_selection_app_profile_keys[@]}"; do
        policy_selection_append_scoped_profile "$profile_key" "enabled via --enable=all-apps"
      done
    fi
  fi
}

policy_selection_should_stop_after_all_selection() {
  [[ "$policy_req_enable_all_agents" -eq 1 || "$policy_req_enable_all_apps" -eq 1 ]]
}

policy_selection_select_matching_app_bundle() {
  local app_bundle_base="$1"

  case "$app_bundle_base" in
    claude.app)
      policy_selection_append_scoped_profile "profiles/65-apps/claude-app.sb" "app bundle match: ${app_bundle_base}"
      ;;
    codex.app)
      policy_selection_append_scoped_profile "profiles/65-apps/codex-app.sb" "app bundle match: ${app_bundle_base}"
      ;;
    "visual studio code.app"|"visual studio code - insiders.app")
      policy_selection_append_scoped_profile "profiles/65-apps/vscode-app.sb" "app bundle match: ${app_bundle_base}"
      ;;
  esac
}

policy_selection_validate_agent_command_aliases() {
  local profile_key="$1"
  local command_alias
  local alias_count=0
  local -a seen_aliases=()

  while IFS= read -r command_alias || [[ -n "$command_alias" ]]; do
    [[ -n "$command_alias" ]] || continue
    alias_count=$((alias_count + 1))

    if [[ "${#seen_aliases[@]}" -gt 0 ]] && safehouse_array_contains_exact "$command_alias" "${seen_aliases[@]}"; then
      safehouse_fail "Agent profile ${profile_key} declares duplicate \$\$command alias: ${command_alias}"
      return 1
    fi

    seen_aliases+=("$command_alias")
  done < <(policy_metadata_emit_profile_command_alias_tokens "$profile_key")

  if [[ "$alias_count" -eq 0 ]]; then
    safehouse_fail "Agent profile ${profile_key} is missing \$\$command=<alias>[,<alias>...]\$\$ metadata."
    return 1
  fi
}

policy_selection_validate_agent_command_alias_catalog() {
  local profile_key command_alias
  local idx
  local -a seen_aliases=()
  local -a seen_profile_keys=()

  for profile_key in "${policy_selection_agent_profile_keys[@]}"; do
    policy_selection_validate_agent_command_aliases "$profile_key" || return 1

    while IFS= read -r command_alias || [[ -n "$command_alias" ]]; do
      [[ -n "$command_alias" ]] || continue

      for idx in "${!seen_aliases[@]}"; do
        if [[ "${seen_aliases[$idx]}" == "$command_alias" ]]; then
          safehouse_fail "Command alias ${command_alias} is declared by multiple agent profiles: ${seen_profile_keys[$idx]}, ${profile_key}"
          return 1
        fi
      done

      seen_aliases+=("$command_alias")
      seen_profile_keys+=("$profile_key")
    done < <(policy_metadata_emit_profile_command_alias_tokens "$profile_key")
  done

  return 0
}

policy_selection_should_skip_command_alias_match() {
  local profile_key="$1"
  local command_alias="$2"
  local app_bundle_base="$3"

  if [[ "$app_bundle_base" == "claude.app" && "$profile_key" == "profiles/60-agents/claude-code.sb" && "$command_alias" == "claude" ]]; then
    return 0
  fi

  if [[ "$app_bundle_base" == "codex.app" && "$profile_key" == "profiles/60-agents/codex.sb" && "$command_alias" == "codex" ]]; then
    return 0
  fi

  return 1
}

policy_selection_select_matching_command() {
  local command_basename="$1"
  local app_bundle_base="$2"
  local profile_key command_alias

  [[ -n "$command_basename" ]] || return 0

  for profile_key in "${policy_selection_agent_profile_keys[@]}"; do
    while IFS= read -r command_alias || [[ -n "$command_alias" ]]; do
      [[ -n "$command_alias" ]] || continue
      [[ "$command_alias" == "$command_basename" ]] || continue

      if policy_selection_should_skip_command_alias_match "$profile_key" "$command_alias" "$app_bundle_base"; then
        continue
      fi

      policy_selection_append_scoped_profile "$profile_key" "command basename match: ${command_basename}"
      return 0
    done < <(policy_metadata_emit_profile_command_alias_tokens "$profile_key")
  done

  return 0
}

policy_selection_build() {
  local command_basename app_bundle_base

  policy_selection_reset
  policy_selection_load_profile_catalog
  policy_selection_append_all_requested_profiles

  if policy_selection_should_stop_after_all_selection; then
    return 0
  fi

  command_basename="$(safehouse_to_lowercase "${policy_req_invoked_command_profile_basename:-${policy_req_invoked_command_basename:-}}")"
  app_bundle_base="$(safehouse_to_lowercase "$(basename "${policy_req_invoked_command_app_bundle:-}")")"

  policy_selection_select_matching_app_bundle "$app_bundle_base"
  policy_selection_select_matching_command "$command_basename" "$app_bundle_base"
}
