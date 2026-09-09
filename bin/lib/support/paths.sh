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

# Calls realpath on an absolute path.
# TODO: Report a failure exit status appropriately.
#       Exit status is currently swallowed, always returning 0 success,
#       preserving long-standing preexisting behavior.
safehouse_normalize_abs_path() {
  realpath "$1"
  return 0
}

# Calls realpath on an array of absolute paths,
# following symlinks and macOS path aliases (e.g. /etc vs /private/etc).
#
# A path that does not exist or cannot be resolved is translated to "".
#
# Example input:
#   TARGET_VAR_NAME
#     /Users/me/.codex   (a symlink to /Volumes/Data/codex)
#     /etc
#     /usr/bin
#     /Users/me/deleted  (does not exist)
# Example output, stored to TARGET_VAR_NAME:
#     /Volumes/Data/codex
#     /private/etc
#     /usr/bin
#     ""
# TODO: Rename to safehouse_normalize_abs_path_array to show similarity
#              to safehouse_normalize_abs_path
safehouse_resolve_paths_batch() {
  local _safehouse_batch_target="$1"
  shift
  local _safehouse_batch_output _safehouse_batch_path _safehouse_batch_resolved
  local _safehouse_batch_ready=0
  local -a _safehouse_batch_results=()

  safehouse_array_clear "$_safehouse_batch_target" || return 1
  [[ "$#" -gt 0 ]] || return 0

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

  if [[ "$_safehouse_batch_ready" -eq 0 ]]; then
    # Unsupported multi-operand implementations and partial failures must not
    # discard valid paths or shift later results into a hole.
    _safehouse_batch_results=()
    for _safehouse_batch_path in "$@"; do
      _safehouse_batch_resolved=""
      if [[ "$_safehouse_batch_path" == /* && -e "$_safehouse_batch_path" ]]; then
        if _safehouse_batch_resolved="$(realpath "$_safehouse_batch_path" 2>/dev/null && printf '.')"; then
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
