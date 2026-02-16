preflight_runtime() {
  local os_name
  os_name="$(uname -s 2>/dev/null || printf 'unknown')"
  if [[ "$os_name" != "Darwin" ]]; then
    echo "safehouse requires macOS (Darwin) to execute commands under sandbox-exec." >&2
    echo "Detected platform: ${os_name}" >&2
    echo "Tip: run with no command (or --stdout) to generate policy output only." >&2
    exit 1
  fi

  if ! command -v sandbox-exec >/dev/null 2>&1; then
    echo "safehouse could not find sandbox-exec in PATH." >&2
    echo "Expected binary on macOS: /usr/bin/sandbox-exec" >&2
    echo "Run with no command (or --stdout) to inspect policy output without execution." >&2
    exit 1
  fi
}

build_sanitized_exec_environment() {
  local resolved_pwd resolved_user resolved_logname var

  sanitized_exec_environment=()

  # Always provide stable core runtime values.
  sanitized_exec_environment+=("HOME=${home_dir}")
  sanitized_exec_environment+=("PATH=${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}")
  sanitized_exec_environment+=("SHELL=${SHELL:-/bin/sh}")
  sanitized_exec_environment+=("TMPDIR=${TMPDIR:-/tmp}")

  resolved_pwd="$(pwd -P)"
  sanitized_exec_environment+=("PWD=${resolved_pwd}")

  resolved_user=""
  if [[ "${USER+x}" == "x" && -n "${USER}" ]]; then
    resolved_user="${USER}"
  elif [[ "${LOGNAME+x}" == "x" && -n "${LOGNAME}" ]]; then
    resolved_user="${LOGNAME}"
  fi
  if [[ -n "$resolved_user" ]]; then
    sanitized_exec_environment+=("USER=${resolved_user}")
  fi

  resolved_logname=""
  if [[ "${LOGNAME+x}" == "x" && -n "${LOGNAME}" ]]; then
    resolved_logname="${LOGNAME}"
  elif [[ -n "$resolved_user" ]]; then
    resolved_logname="${resolved_user}"
  fi
  if [[ -n "$resolved_logname" ]]; then
    sanitized_exec_environment+=("LOGNAME=${resolved_logname}")
  fi

  for var in TERM TMP TEMP LANG LC_ALL LC_CTYPE LC_COLLATE LC_NUMERIC LC_TIME LC_MESSAGES LC_MONETARY LC_PAPER LC_NAME LC_ADDRESS LC_TELEPHONE LC_MEASUREMENT LC_IDENTIFICATION TZ COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION XDG_CONFIG_HOME XDG_CACHE_HOME XDG_STATE_HOME XDG_DATA_HOME SSH_AUTH_SOCK; do
    if [[ "${!var+x}" == "x" ]]; then
      sanitized_exec_environment+=("${var}=${!var}")
    fi
  done
}

build_full_exec_environment() {
  local var

  full_exec_environment=()
  while IFS= read -r var; do
    [[ -n "$var" ]] || continue
    if [[ "${!var+x}" == "x" ]]; then
      full_exec_environment+=("${var}=${!var}")
    fi
  done < <(compgen -e | LC_ALL=C sort)
}

load_env_file_environment() {
  local env_file_path="$1"
  local entry
  local env_dump_file=""
  local -a source_cmd=()

  env_file_exec_environment=()

  if [[ -z "$env_file_path" ]]; then
    echo "Missing value for --env=FILE" >&2
    exit 1
  fi

  if [[ ! -f "$env_file_path" ]]; then
    echo "Env file does not exist or is not a regular file: ${env_file_path}" >&2
    exit 1
  fi

  source_cmd=(/usr/bin/env -i)
  for entry in "${sanitized_exec_environment[@]-}"; do
    source_cmd+=("$entry")
  done
  source_cmd+=(/bin/bash -c 'set -a; source "$1"; /usr/bin/env -0' -- "$env_file_path")

  env_dump_file="$(mktemp "${TMPDIR:-/tmp}/safehouse-env-file.XXXXXX")"
  if ! "${source_cmd[@]}" >"$env_dump_file"; then
    rm -f "$env_dump_file"
    echo "Failed to load env values from file: ${env_file_path}" >&2
    exit 1
  fi

  while IFS= read -r -d '' entry; do
    [[ "$entry" == *=* ]] || continue
    env_file_exec_environment+=("$entry")
  done <"$env_dump_file"

  rm -f "$env_dump_file"
}

merge_exec_environment_with_env_file() {
  local entry key idx replaced

  merged_exec_environment=("${sanitized_exec_environment[@]-}")

  for entry in "${env_file_exec_environment[@]-}"; do
    key="${entry%%=*}"
    [[ -n "$key" ]] || continue

    replaced=0
    for idx in "${!merged_exec_environment[@]}"; do
      if [[ "${merged_exec_environment[$idx]%%=*}" == "$key" ]]; then
        merged_exec_environment[$idx]="$entry"
        replaced=1
        break
      fi
    done

    if [[ "$replaced" -eq 0 ]]; then
      merged_exec_environment+=("$entry")
    fi
  done
}

detect_app_bundle() {
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
    check_path="$(normalize_abs_path "$check_path")"
  fi

  while [[ "$check_path" != "/" && "$check_path" != "." && -n "$check_path" ]]; do
    if [[ "$check_path" == *.app ]]; then
      if [[ -d "$check_path" ]]; then
        printf '%s\n' "$check_path"
        return 0
      fi
    fi
    check_path="$(dirname "$check_path")"
  done
  return 1
}

trim_whitespace() {
  local s="$1"
  s="${s#"${s%%[![:space:]]*}"}"
  s="${s%"${s##*[![:space:]]}"}"
  printf '%s' "$s"
}

to_lowercase() {
  local value="$1"
  printf '%s' "$value" | tr '[:upper:]' '[:lower:]'
}

expand_tilde() {
  local p="$1"

  case "$p" in
    "~")
      printf '%s\n' "$home_dir"
      ;;
    "~/"*)
      printf '%s\n' "${home_dir}${p:1}"
      ;;
    *)
      printf '%s\n' "$p"
      ;;
  esac
}

append_colon_list() {
  local existing="$1"
  local addition="$2"

  if [[ -z "$addition" ]]; then
    printf '%s\n' "$existing"
    return
  fi

  if [[ -n "$existing" ]]; then
    printf '%s:%s\n' "$existing" "$addition"
  else
    printf '%s\n' "$addition"
  fi
}

strip_matching_quotes() {
  local value="$1"
  local value_len first_char last_char

  value_len="${#value}"
  if [[ "$value_len" -lt 2 ]]; then
    printf '%s' "$value"
    return
  fi

  first_char="${value:0:1}"
  last_char="${value:value_len-1:1}"

  if [[ "$first_char" == "\"" && "$last_char" == "\"" ]]; then
    printf '%s' "${value:1:value_len-2}"
    return
  fi

  if [[ "$first_char" == "'" && "$last_char" == "'" ]]; then
    printf '%s' "${value:1:value_len-2}"
    return
  fi

  printf '%s' "$value"
}

normalize_abs_path() {
  local input="$1"
  if command -v realpath >/dev/null 2>&1; then
    realpath "$input"
    return
  fi

  if [[ -d "$input" ]]; then
    (
      cd "$input"
      pwd -P
    )
    return
  fi

  local parent base
  parent="$(dirname "$input")"
  base="$(basename "$input")"
  if [[ ! -d "$parent" ]]; then
    echo "Cannot normalize path; parent directory does not exist: ${parent} (input: ${input})" >&2
    exit 1
  fi

  local parent_resolved
  parent_resolved="$(cd "$parent" && pwd -P)" || {
    echo "Cannot normalize path; failed to resolve parent directory: ${parent} (input: ${input})" >&2
    exit 1
  }
  printf '%s/%s\n' "$parent_resolved" "$base"
}

resolve_default_workdir() {
  local cwd="$1"
  local git_root=""

  if command -v git >/dev/null 2>&1; then
    git_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
    if [[ -n "$git_root" && -d "$git_root" ]]; then
      effective_workdir_source="auto-git-root"
      normalize_abs_path "$git_root"
      return
    fi
  fi

  effective_workdir_source="auto-cwd"
  printf '%s\n' "$cwd"
}

validate_sb_string() {
  local value="$1"
  local label="${2:-SBPL string}"

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    echo "Invalid ${label}: contains control characters and cannot be emitted into SBPL." >&2
    return 1
  fi
}

escape_for_sb() {
  local val="$1"

  validate_sb_string "$val" "SBPL string" || exit 1
  val="${val//\\/\\\\}"
  val="${val//\"/\\\"}"
  printf '%s' "$val"
}
