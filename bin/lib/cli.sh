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
      Note: all-agents restores legacy behavior by loading every 60-agents and 65-apps profile
      Note: wide-read grants read-only visibility across / (broad; use cautiously)

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

main() {
  local -a policy_args=()
  local -a command_args=()
  local policy_path=""
  local keep_policy_file=0
  local detected_app_bundle=""
  local status=0

  while [[ $# -gt 0 ]]; do
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
        command_args=("$@")
        break
        ;;
    esac
  done

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
  sandbox-exec -f "$policy_path" -- "${command_args[@]}"
  status=$?
  set -e

  if [[ "$keep_policy_file" -ne 1 ]]; then
    rm -f "$policy_path"
  fi

  exit "$status"
}
