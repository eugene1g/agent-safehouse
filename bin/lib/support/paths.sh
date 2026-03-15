# shellcheck shell=bash

safehouse_expand_tilde() {
  local path="$1"
  local home_dir="$2"

  case "$path" in
    "~")
      printf '%s\n' "$home_dir"
      ;;
    "~"/*)
      printf '%s\n' "${home_dir}${path:1}"
      ;;
    *)
      printf '%s\n' "$path"
      ;;
  esac
}

safehouse_normalize_abs_path() {
  local input="$1"
  local parent base parent_resolved

  if command -v realpath >/dev/null 2>&1; then
    realpath "$input"
    return 0
  fi

  if [[ -d "$input" ]]; then
    (
      cd "$input" || exit
      pwd -P
    )
    return 0
  fi

  parent="$(dirname "$input")"
  base="$(basename "$input")"
  if [[ ! -d "$parent" ]]; then
    safehouse_fail "Cannot normalize path; parent directory does not exist: ${parent} (input: ${input})"
    return 1
  fi

  parent_resolved="$(cd "$parent" && pwd -P)" || {
    safehouse_fail "Cannot normalize path; failed to resolve parent directory: ${parent} (input: ${input})"
    return 1
  }

  printf '%s/%s\n' "$parent_resolved" "$base"
}

safehouse_find_git_root() {
  local cwd="$1"
  local git_root=""

  if ! command -v git >/dev/null 2>&1; then
    return 1
  fi

  git_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_root" && -d "$git_root" ]]; then
    printf '%s\n' "$git_root"
    return 0
  fi

  return 1
}
