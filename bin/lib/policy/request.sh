# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# Purpose: Resolve CLI/env/workdir inputs into a normalized policy request.
# Reads globals: cli_* parse outputs plus SAFEHOUSE_* env vars.
# Writes globals: policy_req_* request state.
# Called by: commands/policy.sh before plan/render.
# Notes: Precedence is behavior-sensitive. Keep phase order aligned with policy_request_build().

policy_req_home_dir=""
policy_req_output_path=""
policy_req_output_path_set=0
policy_req_invocation_cwd=""
policy_req_optional_features_explicit=()
policy_req_enable_all_agents=0
policy_req_enable_all_apps=0
policy_req_enable_wide_read=0
policy_req_add_dirs_ro_raw_inputs=()
policy_req_add_dirs_rw_raw_inputs=()
policy_req_append_profile_paths=()
policy_req_effective_workdir=""
policy_req_effective_workdir_source=""
policy_req_effective_workdir_git_root=""
policy_req_git_worktree_common_dir=""
policy_req_git_linked_worktree_paths=()
policy_req_trust_workdir_config=0
policy_req_trust_workdir_config_source="default"
policy_req_workdir_config_path=""
policy_req_workdir_config_loaded=0
policy_req_workdir_config_found=0
policy_req_workdir_config_ignored_untrusted=0
policy_req_workdir_config_append_profile_paths=()
policy_req_invoked_command_path=""
policy_req_invoked_command_basename=""
policy_req_invoked_command_profile_path=""
policy_req_invoked_command_profile_basename=""
policy_req_invoked_command_app_bundle=""

policy_request_append_optional_feature() {
  local feature="$1"

  safehouse_array_append_unique policy_req_optional_features_explicit "$feature"
}

policy_request_parse_enable_csv() {
  local csv="$1"
  local raw_value normalized_value
  local -a raw_values=()

  [[ -n "$csv" ]] || return 0

  safehouse_csv_split_to_array raw_values "$csv"
  for raw_value in "${raw_values[@]}"; do
    normalized_value="$(policy_normalize_feature_name "$raw_value")"
    [[ -n "$normalized_value" ]] || continue

    if policy_is_known_optional_integration_feature "$normalized_value"; then
      policy_request_append_optional_feature "$normalized_value"
      continue
    fi

    case "$normalized_value" in
      all-agents)
        policy_req_enable_all_agents=1
        ;;
      all-apps)
        policy_req_enable_all_apps=1
        ;;
      wide-read)
        policy_req_enable_wide_read=1
        ;;
      *)
        safehouse_fail \
          "Unknown feature in --enable: ${normalized_value}" \
          "Supported features: ${policy_supported_enable_features}"
        return 1
        ;;
    esac
  done
}

policy_request_load_workdir_config_into_arrays() {
  local config_path="$1"
  local ro_target_name="$2"
  local rw_target_name="$3"
  local enable_target_name="$4"
  local append_profile_target_name="$5"
  local line trimmed key raw_value value
  local line_number=0
  local config_dir resolved_profile_path

  safehouse_array_clear "$ro_target_name"
  safehouse_array_clear "$rw_target_name"
  safehouse_array_clear "$enable_target_name"
  safehouse_array_clear "$append_profile_target_name"
  [[ -f "$config_path" ]] || return 0

  config_dir="$(dirname "$config_path")"

  while IFS= read -r line || [[ -n "$line" ]]; do
    line_number=$((line_number + 1))
    trimmed="$(safehouse_trim_whitespace "$line")"
    [[ -n "$trimmed" ]] || continue
    if [[ "${trimmed:0:1}" == "#" || "${trimmed:0:1}" == ";" ]]; then
      continue
    fi

    if [[ "$trimmed" != *=* ]]; then
      safehouse_fail "Invalid config line in ${config_path}:${line_number}: expected key=value"
      return 1
    fi

    key="$(safehouse_trim_whitespace "${trimmed%%=*}")"
    raw_value="${trimmed#*=}"
    value="$(safehouse_trim_whitespace "$raw_value")"
    value="$(safehouse_strip_matching_quotes "$value")"

    case "$key" in
      add-dirs-ro|add_dirs_ro|SAFEHOUSE_ADD_DIRS_RO)
        safehouse_array_append "$ro_target_name" "$value"
        ;;
      add-dirs|add_dirs|SAFEHOUSE_ADD_DIRS)
        safehouse_array_append "$rw_target_name" "$value"
        ;;
      enable)
        safehouse_array_append "$enable_target_name" "$value"
        ;;
      append-profile)
        safehouse_validate_sb_string "$value" "append-profile path in workdir config" || return 1
        if [[ "$value" != /* ]]; then
          resolved_profile_path="${config_dir%/}/${value}"
        else
          resolved_profile_path="$value"
        fi
        safehouse_array_append "$append_profile_target_name" "$resolved_profile_path"
        ;;
      *)
        safehouse_fail \
          "Unknown key in workdir config: ${key}" \
          "Supported keys: add-dirs-ro, add-dirs, enable, append-profile"
        return 1
        ;;
    esac
  done < "$config_path"
}

policy_request_resolve_profile_target_path() {
  local first_arg="$1"
  local first_basename first_lower

  first_basename="$(basename "$first_arg")"
  first_lower="$(safehouse_to_lowercase "$first_basename")"

  case "$first_lower" in
    npx|bunx|uvx|pipx|xcrun)
      if [[ $# -ge 2 && -n "$2" ]]; then
        printf '%s\n' "$2"
        return 0
      fi
      ;;
  esac

  printf '%s\n' "$first_arg"
}

policy_request_reset() {
  policy_req_home_dir=""
  policy_req_output_path=""
  policy_req_output_path_set=0
  policy_req_invocation_cwd=""
  policy_req_optional_features_explicit=()
  policy_req_enable_all_agents=0
  policy_req_enable_all_apps=0
  policy_req_enable_wide_read=0
  policy_req_add_dirs_ro_raw_inputs=()
  policy_req_add_dirs_rw_raw_inputs=()
  policy_req_append_profile_paths=()
  policy_req_effective_workdir=""
  policy_req_effective_workdir_source=""
  policy_req_effective_workdir_git_root=""
  policy_req_git_worktree_common_dir=""
  policy_req_git_linked_worktree_paths=()
  policy_req_trust_workdir_config=0
  policy_req_trust_workdir_config_source="default"
  policy_req_workdir_config_path=""
  policy_req_workdir_config_loaded=0
  policy_req_workdir_config_found=0
  policy_req_workdir_config_ignored_untrusted=0
  safehouse_array_clear policy_req_workdir_config_append_profile_paths
  policy_req_invoked_command_path=""
  policy_req_invoked_command_basename=""
  policy_req_invoked_command_profile_path=""
  policy_req_invoked_command_profile_basename=""
  policy_req_invoked_command_app_bundle=""
}

policy_request_resolve_home_and_cwd() {
  local home_dir

  home_dir="${HOME:-}"
  if [[ -z "$home_dir" ]]; then
    safehouse_fail "HOME is not set; set HOME in the environment before running this script."
    return 1
  fi
  if [[ ! -d "$home_dir" ]]; then
    safehouse_fail "HOME does not exist or is not a directory: $home_dir"
    return 1
  fi

  policy_req_home_dir="$(safehouse_normalize_abs_path "$home_dir")" || return 1
  policy_req_invocation_cwd="$(pwd -P)"
  if [[ ! -d "$policy_req_invocation_cwd" ]]; then
    safehouse_fail "Invocation CWD does not exist or is not a directory: ${policy_req_invocation_cwd}"
    return 1
  fi
}

policy_request_resolve_output_path() {
  policy_req_output_path_set="$cli_policy_output_path_set"
  if [[ "$cli_policy_output_path_set" -ne 1 ]]; then
    return 0
  fi

  safehouse_validate_sb_string "$cli_policy_output_path" "--output path" || return 1
  policy_req_output_path="$(safehouse_expand_tilde "$cli_policy_output_path" "$policy_req_home_dir")"
}

policy_request_collect_enable_inputs() {
  local enable_value

  if [[ "$(safehouse_array_length cli_policy_enable_values)" -gt 0 ]]; then
    for enable_value in "${cli_policy_enable_values[@]}"; do
      policy_request_parse_enable_csv "$enable_value" || return 1
    done
  fi
}

policy_request_collect_env_add_dir_inputs() {
  local ro_target_name="$1"
  local rw_target_name="$2"
  local env_add_dirs_ro env_add_dirs_rw

  safehouse_array_clear "$ro_target_name"
  safehouse_array_clear "$rw_target_name"

  env_add_dirs_ro="${SAFEHOUSE_ADD_DIRS_RO:-}"
  if [[ -n "$env_add_dirs_ro" ]]; then
    safehouse_validate_sb_string "$env_add_dirs_ro" "SAFEHOUSE_ADD_DIRS_RO" || return 1
    safehouse_array_append "$ro_target_name" "$env_add_dirs_ro"
  fi

  env_add_dirs_rw="${SAFEHOUSE_ADD_DIRS:-}"
  if [[ -n "$env_add_dirs_rw" ]]; then
    safehouse_validate_sb_string "$env_add_dirs_rw" "SAFEHOUSE_ADD_DIRS" || return 1
    safehouse_array_append "$rw_target_name" "$env_add_dirs_rw"
  fi
}

policy_request_resolve_trust_workdir_config() {
  local env_trust_value=""

  if [[ "$cli_policy_trust_workdir_config_set" -eq 1 ]]; then
    policy_req_trust_workdir_config="$cli_policy_trust_workdir_config_value"
    policy_req_trust_workdir_config_source="--trust-workdir-config"
    return 0
  fi

  if [[ "${SAFEHOUSE_TRUST_WORKDIR_CONFIG+x}" == "x" ]]; then
    env_trust_value="${SAFEHOUSE_TRUST_WORKDIR_CONFIG}"
    if policy_value_is_truthy "$env_trust_value"; then
      policy_req_trust_workdir_config=1
    elif policy_value_is_falsey "$env_trust_value"; then
      policy_req_trust_workdir_config=0
    else
      safehouse_fail \
        "Invalid SAFEHOUSE_TRUST_WORKDIR_CONFIG value: ${env_trust_value}" \
        "Supported values: 1/0, true/false, yes/no, on/off"
      return 1
    fi
    policy_req_trust_workdir_config_source="SAFEHOUSE_TRUST_WORKDIR_CONFIG"
    return 0
  fi

  policy_req_trust_workdir_config=0
  policy_req_trust_workdir_config_source="default"
}

policy_request_set_effective_workdir_from_value() {
  local raw_workdir_value="$1"
  local source_label="$2"
  local disabled_source_label="$3"
  local missing_message="$4"
  local resolved_workdir_path

  if [[ -n "$raw_workdir_value" ]]; then
    resolved_workdir_path="$(safehouse_expand_tilde "$raw_workdir_value" "$policy_req_home_dir")"
    if [[ ! -d "$resolved_workdir_path" ]]; then
      safehouse_fail "${missing_message}: ${raw_workdir_value}"
      return 1
    fi

    policy_req_effective_workdir="$(safehouse_normalize_abs_path "$resolved_workdir_path")" || return 1
    policy_req_effective_workdir_source="$source_label"
    return 0
  fi

  policy_req_effective_workdir=""
  policy_req_effective_workdir_source="$disabled_source_label"
}

policy_request_resolve_effective_workdir() {
  local env_workdir_value=""

  if [[ "$cli_policy_workdir_set" -eq 1 ]]; then
    policy_request_set_effective_workdir_from_value \
      "$cli_policy_workdir_value" \
      "--workdir" \
      "--workdir (disabled)" \
      "Workdir does not exist or is not a directory"
    return $?
  fi

  if [[ "${SAFEHOUSE_WORKDIR+x}" == "x" ]]; then
    env_workdir_value="${SAFEHOUSE_WORKDIR}"
    if [[ -n "$env_workdir_value" ]]; then
      safehouse_validate_sb_string "$env_workdir_value" "SAFEHOUSE_WORKDIR" || return 1
    fi
    policy_request_set_effective_workdir_from_value \
      "$env_workdir_value" \
      "SAFEHOUSE_WORKDIR" \
      "SAFEHOUSE_WORKDIR (disabled)" \
      "Workdir from SAFEHOUSE_WORKDIR does not exist or is not a directory"
    return $?
  fi

  policy_req_effective_workdir="$policy_req_invocation_cwd"
  policy_req_effective_workdir_source="auto-cwd"
}

policy_request_resolve_effective_workdir_git_root() {
  local git_root=""

  policy_req_effective_workdir_git_root=""

  if [[ -z "$policy_req_effective_workdir" ]]; then
    return 0
  fi

  git_root="$(safehouse_find_git_root "$policy_req_effective_workdir" || true)"
  if [[ -n "$git_root" && "$git_root" == "$policy_req_effective_workdir" ]]; then
    policy_req_effective_workdir_git_root="$git_root"
  fi
}

policy_request_resolve_git_worktree_common_dir_access() {
  policy_req_git_worktree_common_dir=""

  if [[ -z "$policy_req_effective_workdir_git_root" ]]; then
    return 0
  fi

  policy_req_git_worktree_common_dir="$(safehouse_find_git_worktree_common_dir "$policy_req_effective_workdir_git_root" || true)"
}

policy_request_resolve_git_linked_worktree_access() {
  local worktree_path=""

  policy_req_git_linked_worktree_paths=()

  if [[ -z "$policy_req_effective_workdir_git_root" ]]; then
    return 0
  fi

  while IFS= read -r worktree_path || [[ -n "$worktree_path" ]]; do
    [[ -n "$worktree_path" ]] || continue
    if [[ "$worktree_path" == "$policy_req_effective_workdir" ]]; then
      continue
    fi
    safehouse_array_append_unique policy_req_git_linked_worktree_paths "$worktree_path"
  done < <(safehouse_emit_git_worktree_paths "$policy_req_effective_workdir_git_root")
}

policy_request_resolve_append_profile_paths() {
  local raw_profile_path expanded_profile_path normalized_profile_path

  if [[ "$(safehouse_array_length cli_policy_append_profiles)" -gt 0 ]]; then
    for raw_profile_path in "${cli_policy_append_profiles[@]}"; do
      safehouse_validate_sb_string "$raw_profile_path" "--append-profile path" || return 1
      if [[ -z "$raw_profile_path" ]]; then
        safehouse_fail "Appended profile path cannot be empty."
        return 1
      fi

      expanded_profile_path="$(safehouse_expand_tilde "$raw_profile_path" "$policy_req_home_dir")"
      if [[ ! -e "$expanded_profile_path" ]]; then
        safehouse_fail "Appended profile path does not exist: ${raw_profile_path}"
        return 1
      fi
      if [[ ! -f "$expanded_profile_path" ]]; then
        safehouse_fail "Appended profile path is not a regular file: ${raw_profile_path}"
        return 1
      fi
      if [[ ! -r "$expanded_profile_path" ]]; then
        safehouse_fail "Appended profile file is not readable: ${raw_profile_path}"
        return 1
      fi

      normalized_profile_path="$(safehouse_normalize_abs_path "$expanded_profile_path")" || return 1
      policy_req_append_profile_paths+=("$normalized_profile_path")
    done
  fi
}

policy_request_load_effective_workdir_config() {
  local ro_target_name="$1"
  local rw_target_name="$2"
  local -a config_enable_values=()
  local -a config_append_profile_paths=()
  local enable_value profile_path

  safehouse_array_clear "$ro_target_name"
  safehouse_array_clear "$rw_target_name"

  if [[ -z "$policy_req_effective_workdir" ]]; then
    return 0
  fi

  policy_req_workdir_config_path="${policy_req_effective_workdir%/}/${safehouse_workdir_config_filename}"
  if [[ "$policy_req_trust_workdir_config" -eq 1 ]]; then
    if [[ -e "$policy_req_workdir_config_path" && ! -f "$policy_req_workdir_config_path" ]]; then
      safehouse_fail "Workdir config path exists but is not a regular file: $policy_req_workdir_config_path"
      return 1
    fi
    if [[ -f "$policy_req_workdir_config_path" ]]; then
      policy_req_workdir_config_found=1
      if [[ ! -r "$policy_req_workdir_config_path" ]]; then
        safehouse_fail "Workdir config file is not readable: $policy_req_workdir_config_path"
        return 1
      fi
      policy_request_load_workdir_config_into_arrays \
        "$policy_req_workdir_config_path" \
        "$ro_target_name" \
        "$rw_target_name" \
        config_enable_values \
        config_append_profile_paths || return 1

      for enable_value in "${config_enable_values[@]}"; do
        policy_request_parse_enable_csv "$enable_value" || return 1
      done

      for profile_path in "${config_append_profile_paths[@]}"; do
        safehouse_array_append policy_req_workdir_config_append_profile_paths "$profile_path"
      done

      policy_req_workdir_config_loaded=1
    fi
    return 0
  fi

  if [[ -e "$policy_req_workdir_config_path" ]]; then
    policy_req_workdir_config_found=1
    policy_req_workdir_config_ignored_untrusted=1
  fi
}

policy_request_merge_add_dir_inputs() {
  local config_ro_name="$1"
  local env_ro_name="$2"
  local cli_ro_name="$3"
  local config_rw_name="$4"
  local env_rw_name="$5"
  local cli_rw_name="$6"

  policy_req_add_dirs_ro_raw_inputs=()
  policy_req_add_dirs_rw_raw_inputs=()

  safehouse_array_append_from_array policy_req_add_dirs_ro_raw_inputs "$config_ro_name"
  safehouse_array_append_from_array policy_req_add_dirs_ro_raw_inputs "$env_ro_name"
  safehouse_array_append_from_array policy_req_add_dirs_ro_raw_inputs "$cli_ro_name"
  if [[ -n "${cli_detected_app_bundle:-}" ]]; then
    policy_req_add_dirs_ro_raw_inputs+=("$cli_detected_app_bundle")
  fi

  safehouse_array_append_from_array policy_req_add_dirs_rw_raw_inputs "$config_rw_name"
  safehouse_array_append_from_array policy_req_add_dirs_rw_raw_inputs "$env_rw_name"
  safehouse_array_append_from_array policy_req_add_dirs_rw_raw_inputs "$cli_rw_name"
}

policy_request_resolve_invoked_command_context() {
  if [[ "${#cli_command_exec_args[@]}" -eq 0 ]]; then
    return 0
  fi

  policy_req_invoked_command_path="${cli_command_exec_args[0]}"
  policy_req_invoked_command_basename="$(basename "${cli_command_exec_args[0]}")"
  policy_req_invoked_command_profile_path="$(policy_request_resolve_profile_target_path "${cli_command_exec_args[@]}")"
  policy_req_invoked_command_profile_basename="$(basename "$policy_req_invoked_command_profile_path")"
  policy_req_invoked_command_app_bundle="${cli_detected_app_bundle:-}"
}

policy_request_build() {
  local -a config_add_dirs_ro_inputs=()
  local -a config_add_dirs_rw_inputs=()
  local -a env_add_dirs_ro_inputs=()
  local -a env_add_dirs_rw_inputs=()
  local -a cli_add_dirs_ro_inputs=()
  local -a cli_add_dirs_rw_inputs=()

  policy_request_reset
  policy_ensure_feature_catalog_initialized || return 1

  policy_request_resolve_home_and_cwd || return 1
  policy_request_resolve_output_path || return 1
  policy_request_collect_enable_inputs || return 1
  policy_request_collect_env_add_dir_inputs env_add_dirs_ro_inputs env_add_dirs_rw_inputs || return 1
  safehouse_array_copy cli_add_dirs_ro_inputs cli_policy_add_dirs_ro_values
  safehouse_array_copy cli_add_dirs_rw_inputs cli_policy_add_dirs_rw_values
  policy_request_resolve_trust_workdir_config || return 1
  policy_request_resolve_effective_workdir || return 1
  policy_request_resolve_effective_workdir_git_root || return 1
  policy_request_resolve_git_worktree_common_dir_access || return 1
  policy_request_resolve_git_linked_worktree_access || return 1
  policy_request_resolve_append_profile_paths || return 1
  policy_request_load_effective_workdir_config config_add_dirs_ro_inputs config_add_dirs_rw_inputs || return 1
  policy_request_merge_add_dir_inputs \
    config_add_dirs_ro_inputs \
    env_add_dirs_ro_inputs \
    cli_add_dirs_ro_inputs \
    config_add_dirs_rw_inputs \
    env_add_dirs_rw_inputs \
    cli_add_dirs_rw_inputs
  policy_request_resolve_invoked_command_context
}
