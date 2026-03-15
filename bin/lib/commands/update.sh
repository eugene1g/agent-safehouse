# shellcheck shell=bash
# shellcheck disable=SC2154

safehouse_self_update_validation_marker="SAFEHOUSE_SELF_UPDATE_VALIDATION_MARKER=standalone-release-asset-v1"

cmd_update_print_usage() {
  cat <<USAGE
Usage:
  $(basename "$0") update [--head]

Description:
  Replace this standalone safehouse install in place.

Options:
  --head
      Download dist/safehouse.sh from the main branch instead of the latest release

Environment:
  SAFEHOUSE_SELF_UPDATE_URL
      Override the update download source with an asset URL or local file path

Notes:
  - Standalone installs only; Homebrew installs should use brew upgrade agent-safehouse
  - Repo checkouts are not updated in place
USAGE
}

cmd_update_resolve_invocation_path() {
  local raw_path="${safehouse_invocation_path:-}"
  local resolved_dir="" resolved_path=""

  if [[ -z "$raw_path" ]]; then
    safehouse_fail "Could not resolve the current safehouse executable path."
    return 1
  fi

  if [[ "$raw_path" == */* ]]; then
    resolved_dir="$(cd "$(dirname "$raw_path")" && pwd -P)"
    resolved_path="${resolved_dir}/$(basename "$raw_path")"
  else
    resolved_path="$(command -v "$raw_path" 2>/dev/null || true)"
  fi

  if [[ -z "$resolved_path" || ! -e "$resolved_path" ]]; then
    safehouse_fail "Could not resolve the current safehouse executable path."
    return 1
  fi

  printf '%s\n' "$resolved_path"
}

cmd_update_resolve_source() {
  local update_channel="${1:-release}"

  if [[ -n "${SAFEHOUSE_SELF_UPDATE_URL:-}" ]]; then
    printf '%s\n' "${SAFEHOUSE_SELF_UPDATE_URL}"
    return 0
  fi

  case "$update_channel" in
    release)
      printf '%s\n' "${safehouse_project_release_asset_url}"
      ;;
    head)
      printf '%s\n' "${safehouse_project_head_asset_url}"
      ;;
    *)
      safehouse_fail "Unknown safehouse update channel: ${update_channel}"
      return 1
      ;;
  esac
}

cmd_update_fetch_source() {
  local source_path="$1"
  local output_path="$2"
  local local_path=""

  if [[ -f "$source_path" ]]; then
    cp "$source_path" "$output_path"
    return 0
  fi

  if [[ "$source_path" == file://* ]]; then
    local_path="${source_path#file://}"
    [[ -f "$local_path" ]] || return 1
    cp "$local_path" "$output_path"
    return 0
  fi

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 1 "$source_path" -o "$output_path"; then
      return 0
    fi
  fi

  if command -v wget >/dev/null 2>&1; then
    if wget -q -O "$output_path" "$source_path"; then
      return 0
    fi
  fi

  return 1
}

cmd_update_extract_embedded_version() {
  local script_path="$1"

  awk -F'"' '
    $0 ~ /^safehouse_project_version_embedded="/ {
      print $2
      exit
    }
  ' "$script_path"
}

cmd_update_candidate_has_explicit_validation_marker() {
  local candidate_path="$1"
  grep -Fq "$safehouse_self_update_validation_marker" "$candidate_path"
}

cmd_update_candidate_has_supported_entrypoint() {
  local candidate_path="$1"

  grep -Fq 'safehouse_main "$@"' "$candidate_path" || grep -Fq 'main "$@"' "$candidate_path"
}

cmd_update_candidate_has_legacy_release_shape() {
  local candidate_path="$1"

  grep -Fq 'PROFILE_KEYS=(' "$candidate_path" || return 1
  grep -Fq 'embedded_profile_body() {' "$candidate_path" || return 1
}

cmd_update_candidate_looks_valid() {
  local candidate_path="$1"
  local first_line=""

  [[ -f "$candidate_path" ]] || return 1

  IFS= read -r first_line < "$candidate_path" || return 1
  [[ "$first_line" == "#!/usr/bin/env bash" ]] || return 1

  grep -Fq 'safehouse_project_name="Agent Safehouse"' "$candidate_path" || return 1
  grep -Fq "safehouse_project_github_url=\"${safehouse_project_github_url}\"" "$candidate_path" || return 1
  cmd_update_candidate_has_supported_entrypoint "$candidate_path" || return 1

  if cmd_update_candidate_has_explicit_validation_marker "$candidate_path"; then
    return 0
  fi

  cmd_update_candidate_has_legacy_release_shape "$candidate_path"
}

cmd_update_running_from_repo_checkout() {
  [[ -f "${ROOT_DIR}/scripts/generate-dist.sh" ]] || return 1
  [[ -f "${ROOT_DIR}/bin/lib/bootstrap/source-manifest.sh" ]] || return 1
  [[ -f "${ROOT_DIR}/profiles/00-base.sb" ]] || return 1
}

cmd_update_run() {
  local update_channel="${1:-release}"
  local target_path target_dir update_source tmp_path candidate_version

  target_path="$(cmd_update_resolve_invocation_path)" || return 1
  target_dir="$(dirname "$target_path")"
  update_source="$(cmd_update_resolve_source "$update_channel")" || return 1

  if cmd_update_running_from_repo_checkout; then
    safehouse_fail \
      "safehouse update only supports standalone installed scripts." \
      "Current executable appears to be running from a source checkout: ${ROOT_DIR}" \
      "Update the repo checkout with git, then regenerate dist artifacts if needed."
    return 1
  fi

  if [[ -L "$target_path" ]]; then
    safehouse_fail \
      "safehouse update does not replace symlinked installs: ${target_path}" \
      "If this install is managed by Homebrew, run: brew upgrade agent-safehouse"
    return 1
  fi

  if [[ ! -f "$target_path" ]]; then
    safehouse_fail "safehouse update expected a regular file executable at: ${target_path}"
    return 1
  fi

  if [[ ! -d "$target_dir" || ! -w "$target_dir" ]]; then
    safehouse_fail "safehouse update cannot replace this install because the target directory is not writable: ${target_dir}"
    return 1
  fi

  (
    tmp_path="$(mktemp "${target_path}.XXXXXX")"
    trap 'rm -f "$tmp_path"' EXIT

    if ! cmd_update_fetch_source "$update_source" "$tmp_path"; then
      safehouse_fail \
        "Failed to download the requested safehouse update asset." \
        "Source: ${update_source}" \
        "Install curl or wget, or set SAFEHOUSE_SELF_UPDATE_URL to a reachable asset URL or local file path."
      exit 1
    fi

    chmod 0755 "$tmp_path"

    if ! cmd_update_candidate_looks_valid "$tmp_path"; then
      safehouse_fail \
        "Downloaded update candidate does not look like a valid standalone safehouse release asset." \
        "Source: ${update_source}"
      exit 1
    fi

    if cmp -s "$tmp_path" "$target_path"; then
      printf 'Already up to date: %s %s\n' "$safehouse_project_name" "$safehouse_project_version"
      exit 0
    fi

    candidate_version="$(cmd_update_extract_embedded_version "$tmp_path")"
    if [[ -z "$candidate_version" || "$candidate_version" == "__SAFEHOUSE_PROJECT_VERSION__" ]]; then
      candidate_version="unknown"
    fi

    if ! mv "$tmp_path" "$target_path"; then
      safehouse_fail \
        "Failed to replace the current safehouse install with the downloaded update." \
        "Target: ${target_path}" \
        "Source: ${update_source}"
      exit 1
    fi

    trap - EXIT
    printf 'Updated %s from %s to %s\n' "$target_path" "$safehouse_project_version" "$candidate_version"
  )
}
