# shellcheck shell=bash
# shellcheck disable=SC2154

# Purpose: Detect app bundles for command selection and launch sandboxed commands.
# Reads globals: runtime_execution_environment.
# Writes globals: none.
# Called by: commands/policy.sh and commands/execute.sh.
# Notes: runtime_detect_app_bundle returns the detected bundle path on stdout.

runtime_detect_app_bundle() {
  local cmd_path="$1"
  local check_path="$cmd_path"
  local resolved_cmd=""

  [[ -n "$check_path" ]] || return 1

  if [[ "$check_path" != */* ]]; then
    resolved_cmd="$(type -P -- "$check_path" 2>/dev/null || true)"
    if [[ -n "$resolved_cmd" ]]; then
      check_path="$resolved_cmd"
    fi
  fi

  if [[ -e "$check_path" ]]; then
    check_path="$(safehouse_normalize_abs_path "$check_path")" || return 1
  fi

  while [[ "$check_path" != "/" && "$check_path" != "." && -n "$check_path" ]]; do
    if [[ "$check_path" == *.app && -d "$check_path" ]]; then
      printf '%s\n' "$check_path"
      return 0
    fi
    check_path="$(dirname "$check_path")"
  done

  return 1
}

runtime_launch_command() {
  local policy_path="$1"
  shift

  if [[ "${#runtime_execution_environment[@]}" -gt 0 ]]; then
    sandbox-exec -f "$policy_path" -- /usr/bin/env -i "${runtime_execution_environment[@]}" "$@"
  else
    sandbox-exec -f "$policy_path" -- /usr/bin/env -i "$@"
  fi
}
