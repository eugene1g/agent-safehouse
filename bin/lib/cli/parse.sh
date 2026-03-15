# shellcheck shell=bash
# shellcheck disable=SC2034

# Purpose: Parse CLI arguments into normalized cli_* state for policy/execute flows.
# Reads globals: SAFEHOUSE_ENV_PASS and parsing helpers from support/policy modules.
# Writes globals: cli_* parse state.
# Called by: commands/main.sh.
# Notes: cli_parse_consumed_args is the parser's shared helper scratch value.

cli_mode="run"
cli_update_action="run"
cli_update_channel="release"
cli_stdout_policy=0
cli_policy_explain=0
cli_policy_enable_values=()
cli_policy_add_dirs_ro_values=()
cli_policy_add_dirs_rw_values=()
cli_policy_workdir_set=0
cli_policy_workdir_value=""
cli_policy_trust_workdir_config_set=0
cli_policy_trust_workdir_config_value=0
cli_policy_append_profiles=()
cli_policy_output_path=""
cli_policy_output_path_set=0
cli_command_args=()
cli_command_env_assignments=()
cli_command_exec_args=()
cli_has_command=0
cli_runtime_env_mode="sanitized"
cli_runtime_env_file=""
cli_runtime_env_file_resolved=""
cli_runtime_env_pass_names=()
cli_detected_app_bundle=""
cli_parse_consumed_args=0

cli_parse_reset() {
  cli_mode="run"
  cli_update_action="run"
  cli_update_channel="release"
  cli_stdout_policy=0
  cli_policy_explain=0
  cli_policy_enable_values=()
  cli_policy_add_dirs_ro_values=()
  cli_policy_add_dirs_rw_values=()
  cli_policy_workdir_set=0
  cli_policy_workdir_value=""
  cli_policy_trust_workdir_config_set=0
  cli_policy_trust_workdir_config_value=0
  cli_policy_append_profiles=()
  cli_policy_output_path=""
  cli_policy_output_path_set=0
  cli_command_args=()
  cli_command_env_assignments=()
  cli_command_exec_args=()
  cli_has_command=0
  cli_runtime_env_mode="sanitized"
  cli_runtime_env_file=""
  cli_runtime_env_file_resolved=""
  cli_runtime_env_pass_names=()
  cli_detected_app_bundle=""
  cli_parse_consumed_args=0
}

cli_append_runtime_env_pass_names_from_csv() {
  local csv="$1"
  local source_label="$2"
  local raw_token trimmed_token
  local -a raw_tokens=()

  if [[ -z "$csv" ]]; then
    safehouse_fail "Missing value for ${source_label}"
    return 1
  fi

  safehouse_csv_split_to_array raw_tokens "$csv"
  for raw_token in "${raw_tokens[@]}"; do
    trimmed_token="$(safehouse_trim_whitespace "$raw_token")"
    if [[ -z "$trimmed_token" ]]; then
      safehouse_fail "Invalid ${source_label} value: empty environment variable name in list."
      return 1
    fi

    if ! safehouse_validate_env_var_name "$trimmed_token"; then
      safehouse_fail "Invalid ${source_label} value: ${trimmed_token} is not a valid environment variable name."
      return 1
    fi

    safehouse_array_append_unique cli_runtime_env_pass_names "$trimmed_token"
  done
}

cli_parse_runtime_env_option() {
  local current_arg="$1"
  local remaining_arg_count="$2"
  local next_arg="${3-}"
  local env_pass_csv=""

  cli_parse_consumed_args=0

  case "$current_arg" in
    --env)
      if [[ "${#cli_runtime_env_pass_names[@]}" -gt 0 ]]; then
        safehouse_fail "--env cannot be combined with --env-pass or SAFEHOUSE_ENV_PASS."
        return 1
      fi
      if [[ "$cli_runtime_env_mode" == "file" ]]; then
        safehouse_fail "--env cannot be combined with --env=FILE."
        return 1
      fi
      cli_runtime_env_mode="passthrough"
      cli_runtime_env_file=""
      cli_parse_consumed_args=1
      return 0
      ;;
    --env=*)
      cli_runtime_env_file="${current_arg#*=}"
      if [[ -z "$cli_runtime_env_file" ]]; then
        safehouse_fail "Missing value for --env=FILE"
        return 1
      fi
      if [[ "$cli_runtime_env_mode" == "passthrough" ]]; then
        safehouse_fail "--env=FILE cannot be combined with --env."
        return 1
      fi
      cli_runtime_env_mode="file"
      cli_parse_consumed_args=1
      return 0
      ;;
    --env-pass)
      if [[ "$remaining_arg_count" -lt 2 ]]; then
        safehouse_fail "Missing value for --env-pass"
        return 1
      fi
      if [[ "$cli_runtime_env_mode" == "passthrough" ]]; then
        safehouse_fail "--env-pass cannot be combined with --env."
        return 1
      fi
      cli_append_runtime_env_pass_names_from_csv "$next_arg" "--env-pass" || return 1
      cli_parse_consumed_args=2
      return 0
      ;;
    --env-pass=*)
      env_pass_csv="${current_arg#*=}"
      if [[ -z "$env_pass_csv" ]]; then
        safehouse_fail "Missing value for --env-pass=LIST"
        return 1
      fi
      if [[ "$cli_runtime_env_mode" == "passthrough" ]]; then
        safehouse_fail "--env-pass cannot be combined with --env."
        return 1
      fi
      cli_append_runtime_env_pass_names_from_csv "$env_pass_csv" "--env-pass" || return 1
      cli_parse_consumed_args=1
      return 0
      ;;
  esac

  return 2
}

cli_finalize_runtime_env_inputs() {
  local resolved_home

  cli_runtime_env_file_resolved=""
  if [[ "$cli_runtime_env_mode" != "file" ]]; then
    return 0
  fi

  safehouse_validate_sb_string "$cli_runtime_env_file" "--env file path" || return 1
  resolved_home="${HOME:-}"
  cli_runtime_env_file="$(safehouse_expand_tilde "$cli_runtime_env_file" "$resolved_home")"
  if [[ ! -f "$cli_runtime_env_file" ]]; then
    safehouse_fail "Env file does not exist or is not a regular file: ${cli_runtime_env_file}"
    return 1
  fi

  cli_runtime_env_file_resolved="$(safehouse_normalize_abs_path "$cli_runtime_env_file")" || return 1
}

cli_finalize_wrapped_command_inputs() {
  local token var_name
  local command_started=0

  cli_command_env_assignments=()
  cli_command_exec_args=()

  if [[ "${#cli_command_args[@]}" -eq 0 ]]; then
    return 0
  fi

  for token in "${cli_command_args[@]}"; do
    if [[ "$command_started" -eq 0 && "$token" == *=* ]]; then
      var_name="${token%%=*}"
      if safehouse_validate_env_var_name "$var_name"; then
        cli_command_env_assignments+=("$token")
        continue
      fi
    fi

    command_started=1
    cli_command_exec_args+=("$token")
  done

  if [[ "${#cli_command_env_assignments[@]}" -gt 0 && "${#cli_command_exec_args[@]}" -eq 0 ]]; then
    safehouse_fail "Wrapped command env assignments require a command after NAME=VALUE tokens."
    return 1
  fi
}

cli_finalize_post_parse_state() {
  cli_finalize_runtime_env_inputs || return 1
  cli_finalize_wrapped_command_inputs || return 1

  if [[ "${#cli_command_exec_args[@]}" -gt 0 ]]; then
    cli_has_command=1
  else
    cli_has_command=0
  fi
}

cli_parse_try_update_subcommand() {
  local current_arg="$1"
  local remaining_arg_count="$2"
  local next_arg="${3-}"
  local safehouse_option_seen="$4"
  local update_subcommand_allowed="$5"

  if [[ "$update_subcommand_allowed" -ne 1 || "$safehouse_option_seen" -ne 0 || "${#cli_command_args[@]}" -ne 0 || "$current_arg" != "update" ]]; then
    return 2
  fi

  case "$next_arg" in
    "")
      cli_mode="update"
      cli_update_action="run"
      cli_update_channel="release"
      return 0
      ;;
    --head)
      if [[ "$remaining_arg_count" -ne 2 ]]; then
        safehouse_fail "safehouse update --head does not accept additional arguments."
        return 1
      fi
      cli_mode="update"
      cli_update_action="run"
      cli_update_channel="head"
      return 0
      ;;
    -h|--help)
      if [[ "$remaining_arg_count" -ne 2 ]]; then
        safehouse_fail "safehouse update --help does not accept additional arguments."
        return 1
      fi
      cli_mode="update"
      cli_update_action="help"
      return 0
      ;;
    *)
      safehouse_fail \
        "Unknown safehouse update option: ${next_arg}" \
        "Usage: $(basename "$0") update [--head]" \
        "To run a wrapped command literally named update, pass it after --."
      return 1
      ;;
  esac
}

cli_parse_policy_flag_option() {
  local current_arg="$1"

  cli_parse_consumed_args=0

  case "$current_arg" in
    --version)
      cli_mode="version"
      cli_parse_consumed_args=1
      return 0
      ;;
    -h|--help)
      cli_mode="help"
      cli_parse_consumed_args=1
      return 0
      ;;
    --stdout)
      cli_stdout_policy=1
      cli_parse_consumed_args=1
      return 0
      ;;
    --explain)
      cli_policy_explain=1
      cli_parse_consumed_args=1
      return 0
      ;;
    --trust-workdir-config)
      cli_policy_trust_workdir_config_set=1
      cli_policy_trust_workdir_config_value=1
      cli_parse_consumed_args=1
      return 0
      ;;
    --trust-workdir-config=*)
      if policy_value_is_truthy "${current_arg#*=}"; then
        cli_policy_trust_workdir_config_value=1
      elif policy_value_is_falsey "${current_arg#*=}"; then
        cli_policy_trust_workdir_config_value=0
      else
        safehouse_fail \
          "Invalid value for --trust-workdir-config: ${current_arg#*=}" \
          "Supported values: 1/0, true/false, yes/no, on/off"
        return 1
      fi
      cli_policy_trust_workdir_config_set=1
      cli_parse_consumed_args=1
      return 0
      ;;
  esac

  return 2
}

cli_parse_policy_option_with_separate_value() {
  local current_arg="$1"
  local remaining_arg_count="$2"
  local next_arg="${3-}"

  cli_parse_consumed_args=0

  case "$current_arg" in
    --enable|--add-dirs-ro|--add-dirs|--workdir|--append-profile|--output)
      if [[ "$remaining_arg_count" -lt 2 ]]; then
        safehouse_fail "Missing value for ${current_arg}"
        return 1
      fi
      case "$current_arg" in
        --enable)
          cli_policy_enable_values+=("$next_arg")
          ;;
        --add-dirs-ro)
          safehouse_validate_sb_string "$next_arg" "--add-dirs-ro" || return 1
          cli_policy_add_dirs_ro_values+=("$next_arg")
          ;;
        --add-dirs)
          safehouse_validate_sb_string "$next_arg" "--add-dirs" || return 1
          cli_policy_add_dirs_rw_values+=("$next_arg")
          ;;
        --workdir)
          cli_policy_workdir_set=1
          cli_policy_workdir_value="$next_arg"
          if [[ -n "$cli_policy_workdir_value" ]]; then
            safehouse_validate_sb_string "$cli_policy_workdir_value" "--workdir" || return 1
          fi
          ;;
        --append-profile)
          safehouse_validate_sb_string "$next_arg" "--append-profile" || return 1
          cli_policy_append_profiles+=("$next_arg")
          ;;
        --output)
          safehouse_validate_sb_string "$next_arg" "--output" || return 1
          cli_policy_output_path="$next_arg"
          cli_policy_output_path_set=1
          ;;
      esac
      cli_parse_consumed_args=2
      return 0
      ;;
  esac

  return 2
}

cli_parse_policy_option_with_inline_value() {
  local current_arg="$1"
  local option_value=""

  cli_parse_consumed_args=0

  case "$current_arg" in
    --enable=*|--add-dirs-ro=*|--add-dirs=*|--workdir=*|--append-profile=*|--output=*)
      option_value="${current_arg#*=}"
      case "$current_arg" in
        --enable=*)
          cli_policy_enable_values+=("$option_value")
          ;;
        --add-dirs-ro=*)
          safehouse_validate_sb_string "$option_value" "--add-dirs-ro" || return 1
          cli_policy_add_dirs_ro_values+=("$option_value")
          ;;
        --add-dirs=*)
          safehouse_validate_sb_string "$option_value" "--add-dirs" || return 1
          cli_policy_add_dirs_rw_values+=("$option_value")
          ;;
        --workdir=*)
          cli_policy_workdir_set=1
          cli_policy_workdir_value="$option_value"
          if [[ -n "$cli_policy_workdir_value" ]]; then
            safehouse_validate_sb_string "$cli_policy_workdir_value" "--workdir" || return 1
          fi
          ;;
        --append-profile=*)
          safehouse_validate_sb_string "$option_value" "--append-profile" || return 1
          cli_policy_append_profiles+=("$option_value")
          ;;
        --output=*)
          safehouse_validate_sb_string "$option_value" "--output" || return 1
          cli_policy_output_path="$option_value"
          cli_policy_output_path_set=1
          ;;
      esac
      cli_parse_consumed_args=1
      return 0
      ;;
  esac

  return 2
}

cli_parse_policy_option() {
  local current_arg="$1"
  local remaining_arg_count="$2"
  local next_arg="${3-}"

  if cli_parse_policy_flag_option "$current_arg"; then
    return 0
  else
    case $? in
      1)
        return 1
        ;;
    esac
  fi

  if cli_parse_policy_option_with_separate_value "$current_arg" "$remaining_arg_count" "$next_arg"; then
    return 0
  else
    case $? in
      1)
        return 1
        ;;
    esac
  fi

  if cli_parse_policy_option_with_inline_value "$current_arg"; then
    return 0
  else
    case $? in
      1)
        return 1
        ;;
    esac
  fi

  return 2
}

cli_parse_consume_command_token() {
  local current_arg="$1"
  shift

  cli_parse_consumed_args=1

  case "$current_arg" in
    --)
      if [[ "$#" -gt 0 ]]; then
        safehouse_array_append cli_command_args "$@"
      fi
      cli_parse_consumed_args=-1
      ;;
    --*)
      safehouse_fail \
        "Unknown option: ${current_arg}" \
        "If this is a command argument, pass it after --"
      return 1
      ;;
    *)
      cli_command_args+=("$current_arg")
      ;;
  esac

  return 0
}

cli_parse_consume_literal_command_arg() {
  cli_parse_consumed_args=1
  cli_command_args+=("$1")
}

cli_parse() {
  local command_started=0
  local update_subcommand_allowed=1
  local safehouse_option_seen=0

  cli_parse_reset

  if [[ "${SAFEHOUSE_ENV_PASS+x}" == "x" && -n "${SAFEHOUSE_ENV_PASS}" ]]; then
    cli_append_runtime_env_pass_names_from_csv "${SAFEHOUSE_ENV_PASS}" "SAFEHOUSE_ENV_PASS" || return 1
  fi

  while [[ $# -gt 0 ]]; do
    if cli_parse_runtime_env_option "$1" "$#" "${2-}"; then
      safehouse_option_seen=1
      update_subcommand_allowed=0
      shift "$cli_parse_consumed_args"
      continue
    else
      case $? in
        1)
          return 1
          ;;
      esac
    fi

    if [[ "$command_started" -eq 1 ]]; then
      cli_parse_consume_literal_command_arg "$1"
      shift "$cli_parse_consumed_args"
      continue
    fi

    if cli_parse_try_update_subcommand "$1" "$#" "${2-}" "$safehouse_option_seen" "$update_subcommand_allowed"; then
      return 0
    else
      case $? in
        1)
          return 1
          ;;
      esac
    fi

    if cli_parse_policy_option "$1" "$#" "${2-}"; then
      if [[ "$cli_mode" != "run" ]]; then
        return 0
      fi
      safehouse_option_seen=1
      update_subcommand_allowed=0
      shift "$cli_parse_consumed_args"
      continue
    else
      case $? in
        1)
          return 1
          ;;
      esac
    fi

    cli_parse_consume_command_token "$1" "${@:2}" || return 1
    if [[ "$cli_parse_consumed_args" -lt 0 ]]; then
      break
    fi
    command_started=1
    shift "$cli_parse_consumed_args"
  done

  cli_finalize_post_parse_state || return 1
  return 0
}
