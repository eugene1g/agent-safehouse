# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

runtime_execution_environment=()

cmd_execute_resolve_base_environment() {
  if [[ "$cli_runtime_env_mode" == "passthrough" ]]; then
    runtime_build_full_exec_environment
    safehouse_array_copy runtime_execution_environment runtime_full_exec_environment
    return 0
  fi

  runtime_build_sanitized_exec_environment "$policy_req_home_dir"
  if [[ "$cli_runtime_env_mode" == "file" ]]; then
    runtime_load_env_file_environment "$cli_runtime_env_file_resolved" || return 1
    runtime_merge_exec_environment_with_env_file
    safehouse_array_copy runtime_execution_environment runtime_merged_exec_environment
    return 0
  fi

  safehouse_array_copy runtime_execution_environment runtime_sanitized_exec_environment
}

cmd_execute_apply_profile_env_defaults() {
  runtime_merge_exec_environment_with_profile_defaults runtime_execution_environment
  safehouse_array_copy runtime_execution_environment runtime_profile_default_merged_exec_environment
}

cmd_execute_apply_named_env_pass_overrides() {
  if [[ "$cli_runtime_env_mode" == "passthrough" || "${#cli_runtime_env_pass_names[@]}" -eq 0 ]]; then
    return 0
  fi

  runtime_merge_exec_environment_with_env_pass runtime_execution_environment
  safehouse_array_copy runtime_execution_environment runtime_env_pass_merged_exec_environment
}

cmd_execute_apply_safehouse_env_defaults() {
  runtime_merge_exec_environment_defaults_if_missing runtime_execution_environment \
    "APP_SANDBOX_CONTAINER_ID=agent-safehouse"
}

cmd_execute_build_environment() {
  cmd_execute_resolve_base_environment || return 1
  cmd_execute_apply_profile_env_defaults || return 1
  cmd_execute_apply_named_env_pass_overrides || return 1
  cmd_execute_apply_safehouse_env_defaults || return 1
}

cmd_execute_run() {
  local status=0

  runtime_preflight || return 1
  cmd_prepare_policy_context || return 1

  if [[ "$cli_policy_explain" -eq 1 ]]; then
    policy_explain_print_outcome "$policy_render_output_path" "execute"
  fi

  cmd_execute_build_environment || {
    cmd_cleanup_rendered_policy
    return 1
  }

  set +e
  runtime_launch_command "$policy_render_output_path" "${cli_command_args[@]}"
  status=$?
  set -e

  cmd_cleanup_rendered_policy
  return "$status"
}
