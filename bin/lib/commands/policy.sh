# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

cmd_prepare_policy_context() {
  cli_detected_app_bundle=""
  if [[ "${#cli_command_exec_args[@]}" -gt 0 ]]; then
    cli_detected_app_bundle="$(runtime_detect_app_bundle "${cli_command_exec_args[0]}" 2>/dev/null || true)"
  fi

  policy_request_build || return 1
  policy_plan_build || return 1

  if [[ "$cli_policy_explain" -eq 1 ]]; then
    policy_explain_print_summary || return 1
  fi

  if [[ "$cli_stdout_policy" -eq 1 && "${policy_req_output_path_set:-0}" -ne 1 ]]; then
    policy_render_reset_output_state
    return 0
  fi

  policy_render_to_path || return 1
}

cmd_cleanup_rendered_policy() {
  if [[ -n "${policy_render_output_path:-}" && "$policy_render_keep_output_path" -ne 1 ]]; then
    rm -f "$policy_render_output_path"
  fi
}

cmd_policy_run() {
  local mode_label policy_output_label

  cmd_prepare_policy_context || return 1

  if [[ "$cli_stdout_policy" -eq 1 ]]; then
    mode_label="policy-stdout"
  else
    mode_label="policy-path"
  fi

  if [[ "$cli_stdout_policy" -eq 1 ]]; then
    if [[ "${policy_req_output_path_set:-0}" -eq 1 ]]; then
      policy_output_label="$policy_render_output_path"
    else
      policy_output_label="(stdout)"
    fi

    if [[ "$cli_policy_explain" -eq 1 ]]; then
      policy_explain_print_outcome "$policy_output_label" "$mode_label"
    fi

    if [[ "${policy_req_output_path_set:-0}" -eq 1 ]]; then
      cat "$policy_render_output_path"
      cmd_cleanup_rendered_policy
    else
      policy_render_to_stdout || return 1
    fi
    return 0
  fi

  if [[ "$cli_policy_explain" -eq 1 ]]; then
    policy_explain_print_outcome "$policy_render_output_path" "$mode_label"
  fi

  printf '%s\n' "$policy_render_output_path"
  return 0
}
