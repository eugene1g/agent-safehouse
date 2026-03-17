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

safehouse_normalize_abs_path_fallback() {
  local input="$1"
  local current current_parent current_base link_target hop_count=0

  if [[ -d "$input" ]]; then
    (
      cd "$input" || exit
      pwd -P
    )
    return 0
  fi

  current_parent="$(dirname "$input")"
  current_base="$(basename "$input")"
  if [[ ! -d "$current_parent" ]]; then
    safehouse_fail "Cannot normalize path; parent directory does not exist: ${current_parent} (input: ${input})"
    return 1
  fi

  current_parent="$(cd "$current_parent" && pwd -P)" || {
    safehouse_fail "Cannot normalize path; failed to resolve parent directory: ${current_parent} (input: ${input})"
    return 1
  }
  current="${current_parent}/${current_base}"

  if command -v readlink >/dev/null 2>&1; then
    while [[ -L "$current" ]]; do
      hop_count=$((hop_count + 1))
      if [[ "$hop_count" -gt 64 ]]; then
        safehouse_fail "Cannot normalize path; symlink resolution exceeded 64 hops: ${input}"
        return 1
      fi

      link_target="$(readlink "$current")" || {
        safehouse_fail "Cannot normalize path; failed to read symlink target: ${current} (input: ${input})"
        return 1
      }

      if [[ "$link_target" == /* ]]; then
        current="$link_target"
      else
        current="$(dirname "$current")/${link_target}"
      fi

      if [[ -d "$current" ]]; then
        current="$(
          cd "$current" || exit
          pwd -P
        )" || {
          safehouse_fail "Cannot normalize path; failed to resolve directory symlink target: ${current} (input: ${input})"
          return 1
        }
        continue
      fi

      current_parent="$(dirname "$current")"
      current_base="$(basename "$current")"
      if [[ ! -d "$current_parent" ]]; then
        safehouse_fail "Cannot normalize path; parent directory does not exist: ${current_parent} (input: ${input})"
        return 1
      fi

      current_parent="$(cd "$current_parent" && pwd -P)" || {
        safehouse_fail "Cannot normalize path; failed to resolve parent directory: ${current_parent} (input: ${input})"
        return 1
      }
      current="${current_parent}/${current_base}"
    done
  fi

  if [[ -d "$current" ]]; then
    (
      cd "$current" || exit
      pwd -P
    )
    return 0
  fi

  current_parent="$(dirname "$current")"
  current_base="$(basename "$current")"
  if [[ ! -d "$current_parent" ]]; then
    safehouse_fail "Cannot normalize path; parent directory does not exist: ${current_parent} (input: ${input})"
    return 1
  fi

  current_parent="$(cd "$current_parent" && pwd -P)" || {
    safehouse_fail "Cannot normalize path; failed to resolve parent directory: ${current_parent} (input: ${input})"
    return 1
  }

  printf '%s/%s\n' "$current_parent" "$current_base"
}

safehouse_normalize_abs_path() {
  local input="$1"

  if command -v realpath >/dev/null 2>&1; then
    realpath "$input"
    return 0
  fi

  safehouse_normalize_abs_path_fallback "$input"
}
