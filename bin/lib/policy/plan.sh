# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# Purpose: Expand a normalized request into a concrete profile/render plan.
# Reads globals: policy_req_* request state and profile catalogs/metadata.
# Writes globals: policy_plan_* arrays and counters used by render/explain/runtime.
# Called by: commands/policy.sh after policy_request_build().
# Notes: Ordering is semantic. Keep policy_plan_build() as a readable phase pipeline.

policy_plan_scoped_profile_keys=()
policy_plan_scoped_profile_reasons=()
policy_plan_agent_profile_keys=()
policy_plan_app_profile_keys=()
policy_plan_optional_profile_keys=()
policy_plan_optional_integrations_explicit_included=()
policy_plan_optional_integrations_implicit_included=()
policy_plan_optional_integrations_not_included=()
policy_plan_keychain_included=0
policy_plan_selected_profile_requirement_tokens=()
policy_plan_enabled_optional_requirement_tokens=()
policy_plan_readonly_paths=()
policy_plan_rw_paths=()
policy_plan_readonly_count=0
policy_plan_rw_count=0
policy_plan_profile_runtime_env_defaults=()

policy_plan_reset() {
  policy_plan_scoped_profile_keys=()
  policy_plan_scoped_profile_reasons=()
  policy_plan_agent_profile_keys=()
  policy_plan_app_profile_keys=()
  policy_plan_optional_profile_keys=()
  policy_plan_optional_integrations_explicit_included=()
  policy_plan_optional_integrations_implicit_included=()
  policy_plan_optional_integrations_not_included=()
  policy_plan_keychain_included=0
  policy_plan_selected_profile_requirement_tokens=()
  policy_plan_enabled_optional_requirement_tokens=()
  policy_plan_readonly_paths=()
  policy_plan_rw_paths=()
  policy_plan_readonly_count=0
  policy_plan_rw_count=0
  policy_plan_profile_runtime_env_defaults=()
}

policy_plan_append_selected_requirement_token() {
  local token="$1"

  [[ -n "$token" ]] || return 0
  safehouse_array_append_unique policy_plan_selected_profile_requirement_tokens "$token"
}

policy_plan_append_enabled_optional_requirement_token() {
  local token="$1"

  [[ -n "$token" ]] || return 0
  safehouse_array_append_unique policy_plan_enabled_optional_requirement_tokens "$token"
}

policy_plan_append_scoped_profile_key() {
  local profile_key="$1"
  local reason="${2:-}"
  local idx

  for idx in "${!policy_plan_scoped_profile_keys[@]}"; do
    if [[ "${policy_plan_scoped_profile_keys[$idx]}" == "$profile_key" ]]; then
      if [[ -n "$reason" && -z "${policy_plan_scoped_profile_reasons[$idx]:-}" ]]; then
        policy_plan_scoped_profile_reasons[idx]="$reason"
      fi
      return 1
    fi
  done

  policy_plan_scoped_profile_keys+=("$profile_key")
  policy_plan_scoped_profile_reasons+=("$reason")
  return 0
}

policy_plan_append_optional_profile_key() {
  local profile_key="$1"

  if [[ "${#policy_plan_optional_profile_keys[@]}" -gt 0 ]] && safehouse_array_contains_exact "$profile_key" "${policy_plan_optional_profile_keys[@]}"; then
    return 1
  fi

  policy_plan_optional_profile_keys+=("$profile_key")
  return 0
}

policy_plan_append_optional_integration_feature_once() {
  local feature="$1"
  local target_bucket="$2"

  case "$target_bucket" in
    explicit)
      if [[ "${#policy_plan_optional_integrations_explicit_included[@]}" -gt 0 ]] && safehouse_array_contains_exact "$feature" "${policy_plan_optional_integrations_explicit_included[@]}"; then
        return 1
      fi
      policy_plan_optional_integrations_explicit_included+=("$feature")
      ;;
    implicit)
      if [[ "${#policy_plan_optional_integrations_implicit_included[@]}" -gt 0 ]] && safehouse_array_contains_exact "$feature" "${policy_plan_optional_integrations_implicit_included[@]}"; then
        return 1
      fi
      policy_plan_optional_integrations_implicit_included+=("$feature")
      ;;
    *)
      safehouse_fail "Unknown optional integration target bucket: ${target_bucket}"
      return 1
      ;;
  esac

  return 0
}

policy_plan_scoped_profile_key_from_requirement_token() {
  local requirement_token="$1"
  local profile_key

  if [[ "${#policy_plan_agent_profile_keys[@]}" -gt 0 ]]; then
    for profile_key in "${policy_plan_agent_profile_keys[@]}"; do
      if [[ "${profile_key#profiles/}" == "$requirement_token" ]]; then
        printf '%s\n' "$profile_key"
        return 0
      fi
    done
  fi

  if [[ "${#policy_plan_app_profile_keys[@]}" -gt 0 ]]; then
    for profile_key in "${policy_plan_app_profile_keys[@]}"; do
      if [[ "${profile_key#profiles/}" == "$requirement_token" ]]; then
        printf '%s\n' "$profile_key"
        return 0
      fi
    done
  fi

  return 1
}

policy_plan_append_profile_requirement_tokens_to_target() {
  local profile_key="$1"
  local target_bucket="$2"
  local requirement_token

  while IFS= read -r requirement_token || [[ -n "$requirement_token" ]]; do
    case "$target_bucket" in
      selected)
        policy_plan_append_selected_requirement_token "$requirement_token"
        ;;
      enabled-optional)
        policy_plan_append_enabled_optional_requirement_token "$requirement_token"
        ;;
      *)
        safehouse_fail "Unknown requirement token cache target: ${target_bucket}"
        return 1
        ;;
    esac
  done < <(policy_metadata_emit_profile_requirement_tokens "$profile_key")
}

policy_plan_resolve_selected_scoped_profile_requirements() {
  local idx=0 profile_key reason
  local requirement_token required_profile_key

  while [[ "$idx" -lt "${#policy_plan_scoped_profile_keys[@]}" ]]; do
    profile_key="${policy_plan_scoped_profile_keys[$idx]}"

    while IFS= read -r requirement_token || [[ -n "$requirement_token" ]]; do
      policy_plan_append_selected_requirement_token "$requirement_token"
      if required_profile_key="$(policy_plan_scoped_profile_key_from_requirement_token "$requirement_token")"; then
        reason="required by ${profile_key##*/}"
        policy_plan_append_scoped_profile_key "$required_profile_key" "$reason" || true
      fi
    done < <(policy_metadata_emit_profile_requirement_tokens "$profile_key")

    idx=$((idx + 1))
  done
}

policy_plan_should_include_scoped_profile_key() {
  local profile_key="$1"

  if [[ "$profile_key" == profiles/60-agents/* && "$policy_req_enable_all_agents" -eq 1 ]]; then
    return 0
  fi

  if [[ "$profile_key" == profiles/65-apps/* && "$policy_req_enable_all_apps" -eq 1 ]]; then
    return 0
  fi

  if [[ "${#policy_plan_scoped_profile_keys[@]}" -eq 0 ]]; then
    return 1
  fi

  safehouse_array_contains_exact "$profile_key" "${policy_plan_scoped_profile_keys[@]}"
}

policy_plan_optional_profile_selected() {
  local profile_key="$1"

  if [[ "${#policy_plan_optional_profile_keys[@]}" -eq 0 ]]; then
    return 1
  fi

  safehouse_array_contains_exact "$profile_key" "${policy_plan_optional_profile_keys[@]}"
}

policy_plan_optional_profile_required_by_selected_profiles() {
  local profile_key="$1"

  if [[ "${#policy_plan_selected_profile_requirement_tokens[@]}" -eq 0 ]]; then
    return 1
  fi

  safehouse_array_contains_exact "${profile_key#profiles/}" "${policy_plan_selected_profile_requirement_tokens[@]}"
}

policy_plan_optional_profile_required_by_enabled_optional_profiles() {
  local profile_key="$1"

  if [[ "${#policy_plan_enabled_optional_requirement_tokens[@]}" -eq 0 ]]; then
    return 1
  fi

  safehouse_array_contains_exact "${profile_key#profiles/}" "${policy_plan_enabled_optional_requirement_tokens[@]}"
}

policy_plan_append_profile_runtime_env_defaults_from_profile() {
  local profile_key="$1"
  local env_entry

  while IFS= read -r env_entry || [[ -n "$env_entry" ]]; do
    safehouse_env_array_upsert_entry policy_plan_profile_runtime_env_defaults "$env_entry" || return 1
  done < <(policy_metadata_emit_profile_exec_env_defaults "$profile_key")
}

policy_plan_append_colon_paths() {
  local path_list="$1"
  local mode="$2"
  local raw_part trimmed_path expanded_path resolved_path
  local IFS=':'
  local -a raw_parts=()

  read -r -a raw_parts <<< "$path_list"
  if [[ "${#raw_parts[@]}" -gt 0 ]]; then
    for raw_part in "${raw_parts[@]}"; do
      trimmed_path="$(safehouse_trim_whitespace "$raw_part")"
      [[ -n "$trimmed_path" ]] || continue
      safehouse_validate_sb_string "$trimmed_path" "${mode} path" || return 1

      expanded_path="$(safehouse_expand_tilde "$trimmed_path" "$policy_req_home_dir")"
      if [[ ! -e "$expanded_path" ]]; then
        safehouse_fail "Path does not exist: ${trimmed_path}"
        return 1
      fi

      resolved_path="$(safehouse_normalize_abs_path "$expanded_path")" || return 1
      if [[ "$mode" == "readonly" ]]; then
        if [[ "${#policy_plan_readonly_paths[@]}" -gt 0 ]] && safehouse_array_contains_exact "$resolved_path" "${policy_plan_readonly_paths[@]}"; then
          continue
        fi
        policy_plan_readonly_paths+=("$resolved_path")
        policy_plan_readonly_count=$((policy_plan_readonly_count + 1))
        continue
      fi

      if [[ "${#policy_plan_rw_paths[@]}" -gt 0 ]] && safehouse_array_contains_exact "$resolved_path" "${policy_plan_rw_paths[@]}"; then
        continue
      fi
      policy_plan_rw_paths+=("$resolved_path")
      policy_plan_rw_count=$((policy_plan_rw_count + 1))
    done
  fi
}

policy_plan_build_initial_selection() {
  policy_selection_build || return 1

  safehouse_array_copy policy_plan_scoped_profile_keys policy_selection_selected_scoped_profile_keys
  safehouse_array_copy policy_plan_scoped_profile_reasons policy_selection_selected_scoped_profile_reasons
  safehouse_array_copy policy_plan_agent_profile_keys policy_selection_agent_profile_keys
  safehouse_array_copy policy_plan_app_profile_keys policy_selection_app_profile_keys
}

policy_plan_feature_is_explicitly_enabled() {
  local feature="$1"

  if [[ "${#policy_req_optional_features_explicit[@]}" -eq 0 ]]; then
    return 1
  fi

  safehouse_array_contains_exact "$feature" "${policy_req_optional_features_explicit[@]}"
}

policy_plan_resolve_explicit_optional_integrations() {
  local feature optional_profile_key

  for feature in "${policy_optional_integration_features[@]}"; do
    policy_plan_feature_is_explicitly_enabled "$feature" || continue

    optional_profile_key="$(policy_optional_integration_profile_key_from_feature "$feature")" || return 1
    policy_plan_append_optional_integration_feature_once "$feature" "explicit" || true
    if policy_plan_append_optional_profile_key "$optional_profile_key"; then
      policy_plan_append_profile_requirement_tokens_to_target "$optional_profile_key" "enabled-optional" || return 1
    fi
  done
}

policy_plan_inject_implied_optional_integrations() {
  local changed=1
  local feature optional_profile_key

  while [[ "$changed" -eq 1 ]]; do
    changed=0

    for feature in "${policy_optional_integration_features[@]}"; do
      if policy_plan_feature_is_explicitly_enabled "$feature"; then
        continue
      fi

      optional_profile_key="$(policy_optional_integration_profile_key_from_feature "$feature")" || return 1
      if ! policy_plan_optional_profile_required_by_selected_profiles "$optional_profile_key" && ! policy_plan_optional_profile_required_by_enabled_optional_profiles "$optional_profile_key"; then
        continue
      fi

      policy_plan_append_optional_integration_feature_once "$feature" "implicit" || true
      if policy_plan_append_optional_profile_key "$optional_profile_key"; then
        policy_plan_append_profile_requirement_tokens_to_target "$optional_profile_key" "enabled-optional" || return 1
        changed=1
      fi
    done
  done
}

policy_plan_resolve_enabled_optional_scoped_profile_requirements() {
  local changed=1
  local requirement_token required_profile_key

  while [[ "$changed" -eq 1 ]]; do
    changed=0

    if [[ "${#policy_plan_enabled_optional_requirement_tokens[@]}" -eq 0 ]]; then
      return 0
    fi

    for requirement_token in "${policy_plan_enabled_optional_requirement_tokens[@]}"; do
      [[ -n "$requirement_token" ]] || continue
      if ! required_profile_key="$(policy_plan_scoped_profile_key_from_requirement_token "$requirement_token")"; then
        continue
      fi

      if policy_plan_append_scoped_profile_key "$required_profile_key" "required by enabled optional integration"; then
        policy_plan_append_profile_requirement_tokens_to_target "$required_profile_key" "selected" || return 1
        changed=1
      fi
    done

    if [[ "$changed" -eq 1 ]]; then
      policy_plan_resolve_selected_scoped_profile_requirements || return 1
      policy_plan_inject_implied_optional_integrations || return 1
    fi
  done
}

policy_plan_finalize_optional_integrations() {
  local feature

  for feature in "${policy_optional_integration_features[@]}"; do
    if [[ "${#policy_plan_optional_integrations_explicit_included[@]}" -gt 0 ]] && safehouse_array_contains_exact "$feature" "${policy_plan_optional_integrations_explicit_included[@]}"; then
      continue
    fi
    if [[ "${#policy_plan_optional_integrations_implicit_included[@]}" -gt 0 ]] && safehouse_array_contains_exact "$feature" "${policy_plan_optional_integrations_implicit_included[@]}"; then
      continue
    fi
    policy_plan_optional_integrations_not_included+=("$feature")
  done

  if policy_plan_optional_profile_selected "profiles/${policy_keychain_requirement_token}" || policy_plan_optional_profile_required_by_selected_profiles "profiles/${policy_keychain_requirement_token}" || policy_plan_optional_profile_required_by_enabled_optional_profiles "profiles/${policy_keychain_requirement_token}"; then
    policy_plan_keychain_included=1
    policy_plan_append_optional_profile_key "profiles/${policy_keychain_requirement_token}" || true
  fi
}

policy_plan_normalize_dynamic_path_grants() {
  local path_list

  if [[ "$(safehouse_array_length policy_req_add_dirs_ro_raw_inputs)" -gt 0 ]]; then
    for path_list in "${policy_req_add_dirs_ro_raw_inputs[@]}"; do
      policy_plan_append_colon_paths "$path_list" "readonly" || return 1
    done
  fi

  if [[ "$(safehouse_array_length policy_req_add_dirs_rw_raw_inputs)" -gt 0 ]]; then
    for path_list in "${policy_req_add_dirs_rw_raw_inputs[@]}"; do
      policy_plan_append_colon_paths "$path_list" "rw" || return 1
    done
  fi
}

policy_plan_collect_runtime_env_defaults_from_optional_profiles() {
  local profile_key
  local -a optional_profile_catalog=()

  policy_source_collect_sorted_profile_keys_in_dir optional_profile_catalog "profiles/55-integrations-optional"
  if [[ "${#optional_profile_catalog[@]}" -gt 0 ]]; then
    for profile_key in "${optional_profile_catalog[@]}"; do
      policy_plan_optional_profile_selected "$profile_key" || continue
      policy_plan_append_profile_runtime_env_defaults_from_profile "$profile_key" || return 1
    done
  fi
}

policy_plan_collect_runtime_env_defaults_from_scoped_profiles() {
  local profile_key

  if [[ "${#policy_plan_agent_profile_keys[@]}" -gt 0 ]]; then
    for profile_key in "${policy_plan_agent_profile_keys[@]}"; do
      policy_plan_should_include_scoped_profile_key "$profile_key" || continue
      policy_plan_append_profile_runtime_env_defaults_from_profile "$profile_key" || return 1
    done
  fi

  if [[ "${#policy_plan_app_profile_keys[@]}" -gt 0 ]]; then
    for profile_key in "${policy_plan_app_profile_keys[@]}"; do
      policy_plan_should_include_scoped_profile_key "$profile_key" || continue
      policy_plan_append_profile_runtime_env_defaults_from_profile "$profile_key" || return 1
    done
  fi
}

policy_plan_collect_runtime_env_defaults_from_appended_profiles() {
  local profile_path

  if [[ "$(safehouse_array_length policy_req_append_profile_paths)" -gt 0 ]]; then
    for profile_path in "${policy_req_append_profile_paths[@]}"; do
      policy_plan_append_profile_runtime_env_defaults_from_profile "$profile_path" || return 1
    done
  fi
}

policy_plan_collect_profile_runtime_env_defaults() {
  policy_plan_collect_runtime_env_defaults_from_optional_profiles || return 1
  policy_plan_collect_runtime_env_defaults_from_scoped_profiles || return 1
  policy_plan_collect_runtime_env_defaults_from_appended_profiles || return 1
}

policy_plan_build() {
  policy_plan_reset
  policy_ensure_feature_catalog_initialized || return 1
  policy_plan_build_initial_selection || return 1
  policy_plan_resolve_selected_scoped_profile_requirements || return 1
  policy_plan_resolve_explicit_optional_integrations || return 1
  policy_plan_inject_implied_optional_integrations || return 1
  policy_plan_resolve_enabled_optional_scoped_profile_requirements || return 1
  policy_plan_finalize_optional_integrations || return 1
  policy_plan_normalize_dynamic_path_grants || return 1
  policy_plan_collect_profile_runtime_env_defaults || return 1
}
