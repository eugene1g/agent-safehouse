# shellcheck shell=bash
# shellcheck disable=SC2154

policy_explain_env_array_value() {
  local array_name="$1"
  local key="$2"
  local entry idx array_length

  eval "array_length=\${#${array_name}[@]}"
  for ((idx = 0; idx < array_length; idx++)); do
    eval "entry=\${${array_name}[${idx}]}"
    if [[ "${entry%%=*}" == "$key" ]]; then
      printf '%s\n' "${entry#*=}"
      return 0
    fi
  done

  return 1
}

policy_explain_path_matches() {
  local command_name="$1"
  local path_value="$2"
  local candidate normalized dir
  local IFS=':'
  local -a path_entries=()
  local -a matches=()

  if [[ -z "$command_name" ]]; then
    printf '%s\n' "$(safehouse_join_by_space)"
    return 0
  fi

  if [[ "$command_name" == */* ]]; then
    candidate="$command_name"
    if [[ "$candidate" != /* ]]; then
      candidate="${policy_req_invocation_cwd}/${candidate}"
    fi
    if [[ -e "$candidate" ]]; then
      normalized="$(safehouse_normalize_abs_path "$candidate" 2>/dev/null || printf '%s' "$candidate")"
      matches+=("$normalized")
    fi
  else
    read -r -a path_entries <<< "$path_value"
    for dir in "${path_entries[@]}"; do
      [[ -n "$dir" ]] || continue
      candidate="${dir%/}/${command_name}"
      if [[ -e "$candidate" && -x "$candidate" ]]; then
        normalized="$(safehouse_normalize_abs_path "$candidate" 2>/dev/null || printf '%s' "$candidate")"
        safehouse_array_append_unique matches "$normalized"
      fi
    done
  fi

  if [[ "${#matches[@]}" -gt 0 ]]; then
    printf '%s\n' "$(safehouse_join_by_space "${matches[@]}")"
    return 0
  fi

  printf '%s\n' "$(safehouse_join_by_space)"
}

policy_explain_prepare_runtime_debug_environment() {
  if ! declare -F cmd_execute_build_environment >/dev/null 2>&1; then
    return 1
  fi

  cmd_execute_build_environment >/dev/null 2>&1
}

policy_explain_print_summary() {
  local workdir_status config_status keychain_status exec_env_status env_pass_names_status profile_env_defaults_status
  local git_worktree_common_dir_status git_worktree_paths_status
  local idx profile reason
  local host_command_matches execution_command_matches execution_path shell_wrapper_note runtime_debug_env_available=0

  if [[ -n "$policy_req_effective_workdir" ]]; then
    workdir_status="${policy_req_effective_workdir}"
  else
    workdir_status="(disabled)"
  fi

  if [[ -n "${policy_req_git_worktree_common_dir:-}" ]]; then
    git_worktree_common_dir_status="${policy_req_git_worktree_common_dir}"
  else
    git_worktree_common_dir_status="(none)"
  fi

  if [[ "${#policy_req_git_linked_worktree_paths[@]}" -gt 0 ]]; then
    git_worktree_paths_status="$(safehouse_join_by_space "${policy_req_git_linked_worktree_paths[@]}")"
  else
    git_worktree_paths_status="$(safehouse_join_by_space)"
  fi

  if [[ "$policy_plan_keychain_included" -eq 1 ]]; then
    keychain_status="included"
  else
    keychain_status="not included"
  fi

  if [[ "${#cli_runtime_env_pass_names[@]}" -gt 0 ]]; then
    env_pass_names_status="${cli_runtime_env_pass_names[*]}"
  else
    env_pass_names_status=""
  fi

  if [[ "${#policy_plan_profile_runtime_env_defaults[@]}" -gt 0 ]]; then
    profile_env_defaults_status="$(safehouse_join_by_space "${policy_plan_profile_runtime_env_defaults[@]}")"
  else
    profile_env_defaults_status="$(safehouse_join_by_space)"
  fi

  case "${cli_runtime_env_mode:-sanitized}" in
    passthrough)
      exec_env_status="pass-through (enabled via --env)"
      ;;
    file)
      if [[ -n "${cli_runtime_env_file_resolved:-}" ]]; then
        exec_env_status="sanitized allowlist + file overrides (${cli_runtime_env_file_resolved})"
      elif [[ -n "${cli_runtime_env_file:-}" ]]; then
        exec_env_status="sanitized allowlist + file overrides (${cli_runtime_env_file})"
      else
        exec_env_status="sanitized allowlist + file overrides (--env=FILE)"
      fi
      if [[ -n "$env_pass_names_status" ]]; then
        exec_env_status="${exec_env_status} + named host vars (${env_pass_names_status})"
      fi
      ;;
    *)
      if [[ -n "$env_pass_names_status" ]]; then
        exec_env_status="sanitized allowlist + named host vars (${env_pass_names_status})"
      else
        exec_env_status="sanitized allowlist (default)"
      fi
      ;;
  esac

  if [[ -z "$policy_req_effective_workdir" ]]; then
    config_status="skipped (workdir disabled)"
  elif [[ "$policy_req_workdir_config_loaded" -eq 1 ]]; then
    config_status="loaded from ${policy_req_workdir_config_path}"
  elif [[ "$policy_req_workdir_config_ignored_untrusted" -eq 1 ]]; then
    config_status="ignored (untrusted): ${policy_req_workdir_config_path}"
  elif [[ "$policy_req_workdir_config_found" -eq 1 ]]; then
    config_status="found but not loaded: ${policy_req_workdir_config_path}"
  else
    config_status="not found at ${policy_req_workdir_config_path}"
  fi

  host_command_matches="$(policy_explain_path_matches "${policy_req_invoked_command_path:-}" "${PATH:-}")"
  execution_path="$(safehouse_join_by_space)"
  execution_command_matches="$(safehouse_join_by_space)"
  if [[ -n "${policy_req_invoked_command_path:-}" ]] && policy_explain_prepare_runtime_debug_environment; then
    runtime_debug_env_available=1
    execution_path="$(policy_explain_env_array_value runtime_execution_environment PATH || safehouse_join_by_space)"
    execution_command_matches="$(policy_explain_path_matches "${policy_req_invoked_command_path}" "$execution_path")"
  fi

  shell_wrapper_note=""
  if [[ -n "${policy_req_invoked_command_path:-}" && "${policy_req_invoked_command_path}" != */* ]]; then
    shell_wrapper_note="interactive-shell aliases/functions are not introspected; run \`type -a ${policy_req_invoked_command_path}\` in your shell if wrapper resolution may matter"
  fi

  {
    echo "safehouse explain:"
    echo "  effective workdir: ${workdir_status} (source: ${policy_req_effective_workdir_source:-unknown})"
    echo "  workdir config trust: $([[ "$policy_req_trust_workdir_config" -eq 1 ]] && echo "enabled" || echo "disabled") (source: ${policy_req_trust_workdir_config_source})"
    echo "  workdir config: ${config_status}"
    echo "  git worktree common dir grant: ${git_worktree_common_dir_status}"
    echo "  git linked worktree read grants: ${git_worktree_paths_status}"
    if [[ "${#policy_plan_readonly_paths[@]}" -gt 0 ]]; then
      echo "  add-dirs-ro (normalized): $(safehouse_join_by_space "${policy_plan_readonly_paths[@]}")"
    else
      echo "  add-dirs-ro (normalized): $(safehouse_join_by_space)"
    fi
    if [[ "${#policy_plan_rw_paths[@]}" -gt 0 ]]; then
      echo "  add-dirs (normalized): $(safehouse_join_by_space "${policy_plan_rw_paths[@]}")"
    else
      echo "  add-dirs (normalized): $(safehouse_join_by_space)"
    fi
    if [[ "${#policy_plan_optional_integrations_explicit_included[@]}" -gt 0 ]]; then
      echo "  optional integrations explicitly enabled: $(safehouse_join_by_space "${policy_plan_optional_integrations_explicit_included[@]}")"
    else
      echo "  optional integrations explicitly enabled: $(safehouse_join_by_space)"
    fi
    if [[ "${#policy_plan_optional_integrations_implicit_included[@]}" -gt 0 ]]; then
      echo "  optional integrations implicitly injected: $(safehouse_join_by_space "${policy_plan_optional_integrations_implicit_included[@]}")"
    else
      echo "  optional integrations implicitly injected: $(safehouse_join_by_space)"
    fi
    if [[ "${#policy_plan_optional_integrations_not_included[@]}" -gt 0 ]]; then
      echo "  optional integrations not included: $(safehouse_join_by_space "${policy_plan_optional_integrations_not_included[@]}")"
    else
      echo "  optional integrations not included: $(safehouse_join_by_space)"
    fi
    echo "  keychain integration: ${keychain_status}"
    echo "  execution environment: ${exec_env_status}"
    echo "  profile env defaults: ${profile_env_defaults_status}"
    if [[ -n "${policy_req_invoked_command_path:-}" ]]; then
      echo "  invoked command: ${policy_req_invoked_command_path}"
      echo "  profile target command: ${policy_req_invoked_command_profile_path:-${policy_req_invoked_command_path}}"
      echo "  host PATH matches: ${host_command_matches}"
      if [[ "$runtime_debug_env_available" -eq 1 ]]; then
        echo "  execution PATH: ${execution_path}"
        echo "  execution PATH matches: ${execution_command_matches}"
      else
        echo "  execution PATH: (unavailable)"
        echo "  execution PATH matches: (unavailable)"
      fi
      if [[ -n "$shell_wrapper_note" ]]; then
        echo "  shell wrapper note: ${shell_wrapper_note}"
      fi
    fi
    if [[ -n "${policy_req_invoked_command_app_bundle:-}" ]]; then
      echo "  detected app bundle: ${policy_req_invoked_command_app_bundle}"
    fi
    if [[ "$policy_req_enable_all_agents" -eq 1 && "$policy_req_enable_all_apps" -eq 1 ]]; then
      echo "  selected scoped profiles: all agents + all apps (via --enable=all-agents,all-apps)"
    elif [[ "$policy_req_enable_all_agents" -eq 1 ]]; then
      echo "  selected scoped profiles: all agents (via --enable=all-agents)"
    elif [[ "$policy_req_enable_all_apps" -eq 1 ]]; then
      echo "  selected scoped profiles: all apps (via --enable=all-apps)"
    elif [[ "${#policy_plan_scoped_profile_keys[@]}" -eq 0 ]]; then
      echo "  selected scoped profiles: (none)"
    else
      for idx in "${!policy_plan_scoped_profile_keys[@]}"; do
        profile="${policy_plan_scoped_profile_keys[$idx]##*/}"
        reason="${policy_plan_scoped_profile_reasons[$idx]:-selected}"
        echo "  selected scoped profile: ${profile} (${reason})"
      done
    fi
    echo "  allow workdir config writes: $([[ "$policy_req_allow_workdir_config_writes" -eq 1 ]] && echo "enabled" || echo "disabled (default)")"
    echo "  sandbox denial log hint: /usr/bin/log show --last 2m --style compact --predicate 'eventMessage CONTAINS \"Sandbox:\" AND eventMessage CONTAINS \"deny(\"'"
  } >&2
}

policy_explain_print_outcome() {
  local policy_path="$1"
  local mode_label="$2"

  {
    echo "  policy file: ${policy_path}"
    echo "  run mode: ${mode_label}"
  } >&2
}
