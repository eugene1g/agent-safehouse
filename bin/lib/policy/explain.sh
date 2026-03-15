# shellcheck shell=bash
# shellcheck disable=SC2154

policy_explain_print_summary() {
  local workdir_status config_status keychain_status exec_env_status env_pass_names_status profile_env_defaults_status
  local idx profile reason

  if [[ -n "$policy_req_effective_workdir" ]]; then
    workdir_status="${policy_req_effective_workdir}"
  else
    workdir_status="(disabled)"
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

  {
    echo "safehouse explain:"
    echo "  effective workdir: ${workdir_status} (source: ${policy_req_effective_workdir_source:-unknown})"
    echo "  workdir config trust: $([[ "$policy_req_trust_workdir_config" -eq 1 ]] && echo "enabled" || echo "disabled") (source: ${policy_req_trust_workdir_config_source})"
    echo "  workdir config: ${config_status}"
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
