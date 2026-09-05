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

# Resolve a caller's snapshot of existing absolute paths without filtering or
# reordering it. Each input gets one output slot, empty if fallback resolution
# fails. Callers retain eligibility checks and decide whether unchanged paths
# need any action. The output array must not use the _safehouse_batch_ prefix.
safehouse_resolve_paths_batch() {
  local _safehouse_batch_target="$1"
  shift
  local _safehouse_batch_output _safehouse_batch_path _safehouse_batch_resolved
  local _safehouse_batch_ready=0
  local -a _safehouse_batch_results=()

  safehouse_array_clear "$_safehouse_batch_target" || return 1
  [[ "$#" -gt 0 ]] || return 0

  if command -v realpath >/dev/null 2>&1; then
    # A sentinel prevents command substitution from stripping newlines that
    # belong to a path. Remove only the sentinel and realpath's final separator.
    if _safehouse_batch_output="$(realpath "$@" 2>/dev/null && printf '.')"; then
      _safehouse_batch_output="${_safehouse_batch_output%.}"
      _safehouse_batch_output="${_safehouse_batch_output%$'\n'}"
      while IFS= read -r _safehouse_batch_resolved; do
        _safehouse_batch_results+=("$_safehouse_batch_resolved")
      done <<< "$_safehouse_batch_output"
      if [[ "${#_safehouse_batch_results[@]}" -eq "$#" ]]; then
        _safehouse_batch_ready=1
        for _safehouse_batch_resolved in "${_safehouse_batch_results[@]}"; do
          # Line-oriented output must not misassociate paths containing control
          # characters. Fall back to individual resolution and caller validation.
          if [[ "$_safehouse_batch_resolved" != /* || "$_safehouse_batch_resolved" =~ [[:cntrl:]] ]]; then
            _safehouse_batch_ready=0
            break
          fi
        done
      fi
    fi
  fi

  if [[ "$_safehouse_batch_ready" -eq 0 ]]; then
    # Missing realpath, unsupported multi-operand implementations, and partial
    # failures must not discard valid paths or shift later results into a hole.
    _safehouse_batch_results=()
    for _safehouse_batch_path in "$@"; do
      _safehouse_batch_resolved=""
      if [[ "$_safehouse_batch_path" == /* && -e "$_safehouse_batch_path" ]]; then
        if _safehouse_batch_resolved="$(safehouse_normalize_abs_path "$_safehouse_batch_path" 2>/dev/null && printf '.')"; then
          _safehouse_batch_resolved="${_safehouse_batch_resolved%.}"
          _safehouse_batch_resolved="${_safehouse_batch_resolved%$'\n'}"
        else
          _safehouse_batch_resolved=""
        fi
      fi
      _safehouse_batch_results+=("$_safehouse_batch_resolved")
    done
  fi

  safehouse_array_append "$_safehouse_batch_target" "${_safehouse_batch_results[@]}"
}
