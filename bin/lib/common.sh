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
