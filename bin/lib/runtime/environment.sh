# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# Purpose: Build and merge the execution environment for wrapped commands.
# Reads globals: host environment, cli_runtime_env_pass_names, policy_plan_profile_runtime_env_defaults.
# Writes globals: runtime_* environment arrays.
# Called by: commands/execute.sh.
# Notes: Merge order is behavior-sensitive. Keep override/default helpers small and explicit.

runtime_default_sanitized_exec_passthrough_vars=(
  TERM
  COLORTERM
  TERM_PROGRAM
  TERM_PROGRAM_VERSION
  EDITOR
  VISUAL
  TMP
  TEMP
  LANG
  LC_ALL
  LC_CTYPE
  LC_COLLATE
  LC_NUMERIC
  LC_TIME
  LC_MESSAGES
  LC_MONETARY
  LC_PAPER
  LC_NAME
  LC_ADDRESS
  LC_TELEPHONE
  LC_MEASUREMENT
  LC_IDENTIFICATION
  TZ
  XDG_CONFIG_HOME
  XDG_CACHE_HOME
  XDG_STATE_HOME
  XDG_DATA_HOME
  HTTP_PROXY
  HTTPS_PROXY
  NO_PROXY
  http_proxy
  https_proxy
  no_proxy
  NODE_EXTRA_CA_CERTS
  NO_BROWSER
  PLAYWRIGHT_MCP_SANDBOX
  SSH_AUTH_SOCK
  SDKROOT
)

runtime_full_exec_environment=()
runtime_sanitized_exec_environment=()
runtime_env_file_exec_environment=()
runtime_merged_exec_environment=()
runtime_env_pass_merged_exec_environment=()
runtime_profile_default_merged_exec_environment=()

runtime_preflight() {
  local os_name

  os_name="$(uname -s 2>/dev/null || printf 'unknown')"
  if [[ "$os_name" != "Darwin" ]]; then
    safehouse_fail \
      "safehouse requires macOS (Darwin) to execute commands under sandbox-exec." \
      "Detected platform: ${os_name}" \
      "Tip: run with no command (or --stdout) to generate policy output only."
    return 1
  fi

  if ! command -v sandbox-exec >/dev/null 2>&1; then
    safehouse_fail \
      "safehouse could not find sandbox-exec in PATH." \
      "Expected binary on macOS: /usr/bin/sandbox-exec" \
      "Run with no command (or --stdout) to inspect policy output without execution."
    return 1
  fi

  return 0
}

runtime_default_exec_path="/usr/bin:/bin:/usr/sbin:/sbin"

# Splits a colon-separated PATH value into runtime_split_exec_path_entries,
# keeping empty entries. PATH="" yields one empty entry.
runtime_split_exec_path() {
  # -d '': read to end of input, keeping any newlines inside entries.
  # Appended ':': end every field with a colon, so read keeps a trailing empty entry.
  # || true: read returns 1 at end of input when it finds no NUL delimiter.
  IFS=: read -r -d '' -a runtime_split_exec_path_entries < <(printf '%s:' "$1") || true
}

# For each directory argument D, tries to read D/<filename>.
# Stores a result array to runtime_exec_path_probe_results with values:
# - "ok" (ENOENT)
# - "denied" (EPERM)
# - "other"
# 
# Returns 1 if the probe itself could not run, for example when safehouse
# is already running inside a sandbox.
runtime_probe_exec_path_dirs() {
  local policy_path="$1"
  local probe_output line
  shift

  runtime_exec_path_probe_results=()
  [[ "$#" -gt 0 ]] || return 0

  # NOTE: Uses shell builtins only to avoid unrelated sandbox denials.
  # NOTE: Uses /bin/bash (rather than /bin/sh) for predictable error message format.
  # NOTE: env -i leaves the locale unset to force C-locale error messages.
  # shellcheck disable=SC2016
  probe_output="$(sandbox-exec -f "$policy_path" -- /usr/bin/env -i /bin/bash -c '
    for dir do
      # Stat $dir/.safehouse-path-probe
      error="$( { true < "$dir/.safehouse-path-probe"; } 2>&1 )"
      case "$error" in
        "" | *"No such file or directory") echo ok ;;
        *"Operation not permitted") echo denied ;;
        *) echo other ;;
      esac
    done
  ' _ "$@" 2>/dev/null)" || return 1

  while IFS= read -r line; do
    runtime_exec_path_probe_results+=("$line")
  done <<< "$probe_output"
  [[ "${#runtime_exec_path_probe_results[@]}" -eq "$#" ]]
}

runtime_build_sanitized_exec_path() {
  local base_path="$1"
  local home_dir="$2"
  local policy_path="${3:-}"
  local entry i
  local -a path_entries=()
  local -a user_entries=()
  local -a probed_entries=()

  # 1. Drop non-absolute PATH entries (including empty entries)
  # 2. Drop ~ PATH entries, which aren't processed consistently by tools
  # 3. Retain absolute PATH entries
  runtime_split_exec_path "$base_path"
  for entry in "${runtime_split_exec_path_entries[@]}"; do
    case "$entry" in
      /*)
        path_entries+=("$entry")
        ;;
      "~"*)
        printf '%s\n' "safehouse: Dropped ~ path from PATH: ${entry}" >&2
        ;;
      "")
        printf '%s\n' "safehouse: Dropped empty path from PATH" >&2
        ;;
      *)
        printf '%s\n' "safehouse: Dropped relative path from PATH: ${entry}" >&2
        ;;
    esac
  done
  user_entries=(${path_entries[@]+"${path_entries[@]}"})

  if [[ "${#path_entries[@]}" -eq 0 ]]; then
    printf '%s\n' "safehouse: PATH had no usable entries; using default: ${runtime_default_exec_path}" >&2
    runtime_split_exec_path "$runtime_default_exec_path"
    path_entries=("${runtime_split_exec_path_entries[@]}")
  fi

  # Append common dev path entries
  safehouse_array_append_unique path_entries \
    "/usr/local/bin" \
    "/usr/local/sbin" \
    "/opt/homebrew/bin" \
    "/opt/homebrew/sbin" \
    "${home_dir}/.local/bin"
  
  # Drop any PATH entry P where a read of P/<filename> fails with EPERM.
  # Such PATH entries cause libuv's PATH search to stop early.
  if [[ -n "$policy_path" ]]; then
    if runtime_probe_exec_path_dirs "$policy_path" "${path_entries[@]}"; then
      i=0
      for entry in "${path_entries[@]}"; do
        if [[ "${runtime_exec_path_probe_results[$i]}" == "denied" ]]; then
          # 1. Drop the path entry
          # 2. Warn if the dropped entry was in the caller's original PATH
          if safehouse_array_contains_exact "$entry" ${user_entries[@]+"${user_entries[@]}"}; then
            printf '%s\n' "safehouse: Dropped sandbox-denied path from PATH: ${entry}" >&2
          fi
        else
          # Retain the path entry
          probed_entries+=("$entry")
        fi
        i=$((i + 1))
      done
      path_entries=(${probed_entries[@]+"${probed_entries[@]}"})
    else
      printf '%s\n' "safehouse: Could not check for unreadable PATH directories inside the sandbox" >&2
    fi
  fi

  (
    IFS=':'
    printf '%s\n' "${path_entries[*]}"
  )
}

runtime_build_sanitized_exec_environment() {
  local home_dir="$1"
  local policy_path="${2:-}"
  local resolved_pwd resolved_user resolved_logname sanitized_path var_name

  runtime_sanitized_exec_environment=()
  runtime_sanitized_exec_environment+=("HOME=${home_dir}")
  sanitized_path="$(runtime_build_sanitized_exec_path "${PATH-${runtime_default_exec_path}}" "$home_dir" "$policy_path")"
  runtime_sanitized_exec_environment+=("PATH=${sanitized_path}")
  runtime_sanitized_exec_environment+=("SHELL=${SHELL:-/bin/sh}")
  runtime_sanitized_exec_environment+=("TMPDIR=${TMPDIR:-/tmp}")

  resolved_pwd="$(pwd -P)"
  runtime_sanitized_exec_environment+=("PWD=${resolved_pwd}")

  resolved_user=""
  if [[ "${USER+x}" == "x" && -n "${USER}" ]]; then
    resolved_user="${USER}"
  elif [[ "${LOGNAME+x}" == "x" && -n "${LOGNAME}" ]]; then
    resolved_user="${LOGNAME}"
  fi
  if [[ -n "$resolved_user" ]]; then
    runtime_sanitized_exec_environment+=("USER=${resolved_user}")
  fi

  resolved_logname=""
  if [[ "${LOGNAME+x}" == "x" && -n "${LOGNAME}" ]]; then
    resolved_logname="${LOGNAME}"
  elif [[ -n "$resolved_user" ]]; then
    resolved_logname="${resolved_user}"
  fi
  if [[ -n "$resolved_logname" ]]; then
    runtime_sanitized_exec_environment+=("LOGNAME=${resolved_logname}")
  fi

  for var_name in "${runtime_default_sanitized_exec_passthrough_vars[@]}"; do
    if [[ "${!var_name+x}" == "x" ]]; then
      runtime_sanitized_exec_environment+=("${var_name}=${!var_name}")
    fi
  done
}

runtime_build_full_exec_environment() {
  local var_name

  runtime_full_exec_environment=()
  while IFS= read -r var_name; do
    [[ -n "$var_name" ]] || continue
    if [[ "${!var_name+x}" == "x" ]]; then
      runtime_full_exec_environment+=("${var_name}=${!var_name}")
    fi
  done < <(compgen -e | LC_ALL=C sort)
}

runtime_load_env_file_environment() {
  local env_file_path="$1"
  local entry env_dump_file=""
  local -a source_cmd=()

  runtime_env_file_exec_environment=()

  if [[ -z "$env_file_path" ]]; then
    safehouse_fail "Missing value for --env=FILE"
    return 1
  fi

  if [[ ! -f "$env_file_path" ]]; then
    safehouse_fail "Env file does not exist or is not a regular file: ${env_file_path}"
    return 1
  fi

  source_cmd=(/usr/bin/env -i)
  for entry in "${runtime_sanitized_exec_environment[@]}"; do
    source_cmd+=("$entry")
  done
  source_cmd+=(/bin/bash -c "set -a; source \"\$1\"; /usr/bin/env -0" -- "$env_file_path")

  env_dump_file="$(mktemp "${TMPDIR:-/tmp}/safehouse-env-file.XXXXXX")"
  if ! "${source_cmd[@]}" >"$env_dump_file"; then
    rm -f "$env_dump_file"
    safehouse_fail "Failed to load env values from file: ${env_file_path}"
    return 1
  fi

  while IFS= read -r -d '' entry; do
    [[ "$entry" == *=* ]] || continue
    runtime_env_file_exec_environment+=("$entry")
  done <"$env_dump_file"

  rm -f "$env_dump_file"
}

runtime_copy_exec_environment() {
  local target_name="$1"
  shift

  safehouse_array_clear "$target_name"
  if [[ "$#" -gt 0 ]]; then
    safehouse_array_append "$target_name" "$@"
  fi
}

runtime_merge_exec_environment_overrides() {
  local target_name="$1"
  shift

  if [[ "$#" -eq 0 ]]; then
    return 0
  fi

  safehouse_env_array_upsert_entries "$target_name" "$@"
}

runtime_merge_exec_environment_defaults_if_missing() {
  local target_name="$1"
  shift

  if [[ "$#" -eq 0 ]]; then
    return 0
  fi

  safehouse_env_array_append_entries_if_keys_missing "$target_name" "$@"
}

runtime_append_requested_host_env_entries() {
  local target_name="$1"
  local var_name host_entry

  for var_name in "${cli_runtime_env_pass_names[@]}"; do
    if [[ "${!var_name+x}" != "x" ]]; then
      continue
    fi
    host_entry="${var_name}=${!var_name}"
    safehouse_env_array_upsert_entry "$target_name" "$host_entry" || return 1
  done
}

runtime_merge_exec_environment_with_env_file() {
  runtime_copy_exec_environment runtime_merged_exec_environment "${runtime_sanitized_exec_environment[@]}"
  if [[ "${#runtime_env_file_exec_environment[@]}" -gt 0 ]]; then
    runtime_merge_exec_environment_overrides runtime_merged_exec_environment "${runtime_env_file_exec_environment[@]}"
  fi
}

runtime_merge_exec_environment_with_env_pass() {
  local source_array_name="$1"

  safehouse_array_copy runtime_env_pass_merged_exec_environment "$source_array_name"
  runtime_append_requested_host_env_entries runtime_env_pass_merged_exec_environment
}

runtime_merge_exec_environment_with_profile_defaults() {
  local source_array_name="$1"

  safehouse_array_copy runtime_profile_default_merged_exec_environment "$source_array_name"
  if [[ "${#policy_plan_profile_runtime_env_defaults[@]}" -gt 0 ]]; then
    runtime_merge_exec_environment_defaults_if_missing runtime_profile_default_merged_exec_environment "${policy_plan_profile_runtime_env_defaults[@]}"
  fi
}
