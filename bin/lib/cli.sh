usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [policy options]
  $(basename "$0") [policy options] [--] <command> [args...]

Summary:
  Agent Safehouse is a macOS sandbox toolkit for coding agents and CLIs.
  It composes a deny-by-default sandbox-exec policy with scoped allows.

How to use this CLI:
  1) Policy mode (no command):
     Generates a policy file and prints the filename.
     Use --stdout to print the policy text instead.
     You can pass that file to your own sandbox-exec invocation.
  2) Execute mode (command provided):
     Generates a policy and runs the command inside that policy.

Common examples:
  # Generate policy file path
  $(basename "$0")

  # Print policy text to stdout
  $(basename "$0") --stdout

  # Generate policy path and run your own sandbox-exec command
  sandbox-exec -f "\$($(basename "$0"))" -- /usr/bin/true

  # Run a command under Safehouse policy
  $(basename "$0") -- claude --dangerously-skip-permissions
  $(basename "$0") --enable=docker -- docker ps

Policy scope options:
  --enable FEATURES
  --enable=FEATURES
      Comma-separated optional features to enable
      Supported values: ${supported_enable_features}
      Note: electron implies macos-gui
      Note: shell-init enables shell startup file reads
      Note: all-agents loads every 60-agents profile
      Note: all-apps loads every 65-apps profile
      Note: wide-read grants read-only visibility across / (broad; use cautiously)

  --env
      Execute wrapped command with full inherited environment variables

  --env=FILE
      Execute wrapped command with sanitized env allowlist plus vars loaded
      by sourcing FILE (FILE values override sanitized defaults)
      FILE is sourced by /bin/bash (trusted shell input, not dotenv parsing)

  --env-pass NAMES
  --env-pass=NAMES
      Comma-separated env variable names to pass through from host env
      on top of sanitized defaults (repeatable; names are deduplicated)
      Compatible with default mode and --env=FILE; incompatible with --env

  --add-dirs-ro PATHS
  --add-dirs-ro=PATHS
      Colon-separated paths to grant read-only access

  --add-dirs PATHS
  --add-dirs=PATHS
      Colon-separated paths to grant read/write access

  --workdir DIR
  --workdir=DIR
      Main directory to grant read/write access
      Empty string disables automatic workdir grants

  --trust-workdir-config
  --trust-workdir-config=BOOL
      Trust and load <workdir>/.safehouse (default: disabled)

  --append-profile PATH
  --append-profile=PATH
      Append an additional sandbox profile file after generated rules
      Repeatable; files are appended in argument order

  --output PATH
  --output=PATH
      Write policy to a specific file path

Output options:
  --stdout
      Print policy text to stdout (do not execute command)

  --explain
      Print effective workdir/grants/profile selection summary to stderr

General:
  -h, --help
      Show this help

Environment:
  SAFEHOUSE_ADD_DIRS_RO
      Colon-separated read-only paths (same format as --add-dirs-ro)

  SAFEHOUSE_ADD_DIRS
      Colon-separated read/write paths (same format as --add-dirs)

  SAFEHOUSE_WORKDIR
      Workdir override (same behavior as --workdir, including empty string)

  SAFEHOUSE_TRUST_WORKDIR_CONFIG
      Trust and load <workdir>/.safehouse (1/0, true/false, yes/no, on/off)

  SAFEHOUSE_ENV_PASS
      Comma-separated env var names to pass through (same format as --env-pass)

Config file:
  <workdir>/.safehouse (optional, loaded only when trusted)
      Supports keys:
        add-dirs-ro=PATHS
        add-dirs=PATHS
USAGE
}

policy_args_include_output() {
  local arg
  for arg in "$@"; do
    case "$arg" in
      --output|--output=*)
        return 0
        ;;
    esac
  done
  return 1
}

resolve_profile_target_path() {
  local first_arg="$1"
  local first_basename first_lower

  first_basename="$(basename "$first_arg")"
  first_lower="$(to_lowercase "$first_basename")"

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

consume_runtime_env_option() {
  local current_arg="$1"
  local remaining_arg_count="$2"
  local next_arg="${3-}"
  local runtime_env_pass_csv_value=""

  runtime_env_args_consumed=0

  case "$current_arg" in
    --env)
      if [[ "${#runtime_env_pass_names[@]}" -gt 0 ]]; then
        echo "--env cannot be combined with --env-pass or SAFEHOUSE_ENV_PASS." >&2
        exit 1
      fi
      if [[ "$execution_env_mode" == "file" ]]; then
        echo "--env cannot be combined with --env=FILE." >&2
        exit 1
      fi
      execution_env_mode="passthrough"
      execution_env_file=""
      runtime_env_args_consumed=1
      ;;
    --env=*)
      execution_env_file="${current_arg#*=}"
      [[ -n "$execution_env_file" ]] || { echo "Missing value for --env=FILE" >&2; exit 1; }
      if [[ "$execution_env_mode" == "passthrough" ]]; then
        echo "--env=FILE cannot be combined with --env." >&2
        exit 1
      fi
      execution_env_mode="file"
      runtime_env_args_consumed=1
      ;;
    --env-pass)
      [[ "$remaining_arg_count" -ge 2 ]] || { echo "Missing value for --env-pass" >&2; exit 1; }
      if [[ "$execution_env_mode" == "passthrough" ]]; then
        echo "--env-pass cannot be combined with --env." >&2
        exit 1
      fi
      append_runtime_env_pass_names_from_csv "$next_arg" "--env-pass"
      runtime_env_args_consumed=2
      ;;
    --env-pass=*)
      runtime_env_pass_csv_value="${current_arg#*=}"
      [[ -n "$runtime_env_pass_csv_value" ]] || { echo "Missing value for --env-pass=LIST" >&2; exit 1; }
      if [[ "$execution_env_mode" == "passthrough" ]]; then
        echo "--env-pass cannot be combined with --env." >&2
        exit 1
      fi
      append_runtime_env_pass_names_from_csv "$runtime_env_pass_csv_value" "--env-pass"
      runtime_env_args_consumed=1
      ;;
    *)
      return 1
      ;;
  esac

  return 0
}

main() {
  local -a policy_args=()
  local -a command_args=()
  local policy_path=""
  local keep_policy_file=0
  local detected_app_bundle=""
  local execution_env_mode="sanitized"
  local execution_env_file=""
  local -a execution_environment=()
  local runtime_env_args_consumed=0
  local command_started=0
  local status=0

  runtime_env_pass_names=()
  if [[ "${SAFEHOUSE_ENV_PASS+x}" == "x" && -n "${SAFEHOUSE_ENV_PASS}" ]]; then
    append_runtime_env_pass_names_from_csv "${SAFEHOUSE_ENV_PASS}" "SAFEHOUSE_ENV_PASS"
  fi

  while [[ $# -gt 0 ]]; do
    if consume_runtime_env_option "$1" "$#" "${2-}"; then
      shift "$runtime_env_args_consumed"
      continue
    fi

    if [[ "$command_started" -eq 1 ]]; then
      case "$1" in
        --)
          shift
          command_args+=("$@")
          break
          ;;
        *)
          command_args+=("$1")
          shift
          ;;
      esac
      continue
    fi

    case "$1" in
      -h|--help)
        usage
        exit 0
        ;;
      --stdout)
        stdout_policy=1
        shift
        ;;
      --explain)
        policy_args+=("$1")
        shift
        ;;
      --trust-workdir-config|--trust-workdir-config=*)
        policy_args+=("$1")
        shift
        ;;
      --)
        shift
        command_args=("$@")
        break
        ;;
      --enable|--add-dirs-ro|--add-dirs|--workdir|--append-profile|--output)
        [[ $# -ge 2 ]] || { echo "Missing value for $1" >&2; exit 1; }
        policy_args+=("$1" "$2")
        shift 2
        ;;
      --enable=*|--add-dirs-ro=*|--add-dirs=*|--workdir=*|--append-profile=*|--output=*)
        policy_args+=("$1")
        shift
        ;;
      --*)
        echo "Unknown option: $1" >&2
        echo "If this is a command argument, pass it after --" >&2
        exit 1
        ;;
      *)
        command_started=1
        command_args+=("$1")
        shift
        ;;
    esac
  done

  runtime_env_mode="$execution_env_mode"
  runtime_env_file="$execution_env_file"
  runtime_env_file_resolved=""
  if [[ "$runtime_env_mode" == "file" ]]; then
    validate_sb_string "$runtime_env_file" "--env file path" || exit 1
    runtime_env_file="$(expand_tilde "$runtime_env_file")"
    if [[ ! -f "$runtime_env_file" ]]; then
      echo "Env file does not exist or is not a regular file: ${runtime_env_file}" >&2
      exit 1
    fi
    runtime_env_file_resolved="$(normalize_abs_path "$runtime_env_file")"
  fi

  if [[ "$stdout_policy" -eq 0 && "${#command_args[@]}" -gt 0 ]]; then
    preflight_runtime
  fi

  # Auto-detect .app bundle from the command and grant read-only access to the bundle.
  if [[ "${#command_args[@]}" -gt 0 ]]; then
    detected_app_bundle="$(detect_app_bundle "${command_args[0]}")" || true
    if [[ -n "${detected_app_bundle:-}" ]]; then
      policy_args+=("--add-dirs-ro=${detected_app_bundle}")
    fi
  fi

  invoked_command_path=""
  invoked_command_basename=""
  invoked_command_profile_path=""
  invoked_command_profile_basename=""
  invoked_command_app_bundle=""
  selected_agent_profile_basenames=()
  selected_agent_profile_reasons=()
  selected_agent_profiles_resolved=0
  if [[ "${#command_args[@]}" -gt 0 ]]; then
    invoked_command_path="${command_args[0]}"
    invoked_command_basename="$(basename "${command_args[0]}")"
    invoked_command_profile_path="$(resolve_profile_target_path "${command_args[@]}")"
    invoked_command_profile_basename="$(basename "$invoked_command_profile_path")"
    invoked_command_app_bundle="${detected_app_bundle:-}"
  fi

  if [[ "${#policy_args[@]}" -gt 0 ]]; then
    policy_path="$(generate_policy_file "${policy_args[@]}")"
  else
    policy_path="$(generate_policy_file)"
  fi
  if [[ ! -f "$policy_path" ]]; then
    echo "Generator returned non-existent policy file: ${policy_path}" >&2
    exit 1
  fi

  if [[ "${#policy_args[@]}" -gt 0 ]] && policy_args_include_output "${policy_args[@]}"; then
    keep_policy_file=1
  fi

  if [[ "$stdout_policy" -eq 1 ]]; then
    emit_explain_policy_outcome "$policy_path" "policy-stdout"
    cat "$policy_path"
    if [[ "$keep_policy_file" -ne 1 ]]; then
      rm -f "$policy_path"
    fi
    exit 0
  fi

  if [[ "${#command_args[@]}" -eq 0 ]]; then
    emit_explain_policy_outcome "$policy_path" "policy-path"
    printf '%s\n' "$policy_path"
    exit 0
  fi

  emit_explain_policy_outcome "$policy_path" "execute"

  set +e
  if [[ "$runtime_env_mode" == "passthrough" ]]; then
    build_full_exec_environment
    execution_environment=("${full_exec_environment[@]}")
  elif [[ "$runtime_env_mode" == "file" ]]; then
    build_sanitized_exec_environment
    load_env_file_environment "$runtime_env_file_resolved"
    merge_exec_environment_with_env_file
    execution_environment=("${merged_exec_environment[@]}")
  else
    build_sanitized_exec_environment
    execution_environment=("${sanitized_exec_environment[@]}")
  fi

  if [[ "$runtime_env_mode" != "passthrough" ]] && [[ "${#runtime_env_pass_names[@]}" -gt 0 ]]; then
    merge_exec_environment_with_env_pass "${execution_environment[@]}"
    execution_environment=("${env_pass_merged_exec_environment[@]}")
  fi

  sandbox-exec -f "$policy_path" -- /usr/bin/env -i "${execution_environment[@]}" "${command_args[@]}"
  status=$?
  set -e

  if [[ "$keep_policy_file" -ne 1 ]]; then
    rm -f "$policy_path"
  fi

  exit "$status"
}
