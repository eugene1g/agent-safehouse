safehouse_self_update_validation_marker="SAFEHOUSE_SELF_UPDATE_VALIDATION_MARKER=standalone-release-asset-v1"

print_update_usage() {
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

resolve_safehouse_invocation_path() {
  local raw_path="${safehouse_invocation_path:-}"
  local resolved_dir=""
  local resolved_path=""

  if [[ -z "$raw_path" ]]; then
    echo "Could not resolve the current safehouse executable path." >&2
    exit 1
  fi

  if [[ "$raw_path" == */* ]]; then
    resolved_dir="$(cd "$(dirname "$raw_path")" && pwd -P)"
    resolved_path="${resolved_dir}/$(basename "$raw_path")"
  else
    resolved_path="$(command -v "$raw_path" 2>/dev/null || true)"
  fi

  if [[ -z "$resolved_path" || ! -e "$resolved_path" ]]; then
    echo "Could not resolve the current safehouse executable path." >&2
    exit 1
  fi

  printf '%s\n' "$resolved_path"
}

resolve_safehouse_update_source() {
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
      echo "Unknown safehouse update channel: ${update_channel}" >&2
      exit 1
      ;;
  esac
}

fetch_safehouse_update_source() {
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

extract_safehouse_embedded_version() {
  local script_path="$1"

  awk -F'"' '
    $0 ~ /^safehouse_project_version_embedded="/ {
      print $2
      exit
    }
  ' "$script_path"
}

safehouse_update_candidate_has_explicit_validation_marker() {
  local candidate_path="$1"

  grep -Fq "$safehouse_self_update_validation_marker" "$candidate_path" || return 1
  return 0
}

safehouse_update_candidate_has_legacy_release_shape() {
  local candidate_path="$1"

  grep -Fq 'PROFILE_KEYS=(' "$candidate_path" || return 1
  grep -Fq 'embedded_profile_body() {' "$candidate_path" || return 1
  return 0
}

safehouse_update_candidate_looks_valid() {
  local candidate_path="$1"
  local first_line=""

  [[ -f "$candidate_path" ]] || return 1

  IFS= read -r first_line < "$candidate_path" || return 1
  [[ "$first_line" == "#!/usr/bin/env bash" ]] || return 1

  grep -Fq 'safehouse_project_name="Agent Safehouse"' "$candidate_path" || return 1
  grep -Fq "safehouse_project_github_url=\"${safehouse_project_github_url}\"" "$candidate_path" || return 1
  grep -Fq 'main "$@"' "$candidate_path" || return 1

  if safehouse_update_candidate_has_explicit_validation_marker "$candidate_path"; then
    return 0
  fi

  # Backward compatibility for already-published release assets that predate the
  # explicit self-update validation marker.
  safehouse_update_candidate_has_legacy_release_shape "$candidate_path" || return 1

  return 0
}

safehouse_running_from_repo_checkout() {
  [[ -f "${ROOT_DIR}/scripts/generate-dist.sh" ]] || return 1
  [[ -f "${ROOT_DIR}/bin/lib/cli.sh" ]] || return 1
  [[ -f "${ROOT_DIR}/profiles/00-base.sb" ]] || return 1
  return 0
}

run_safehouse_update() {
  local update_channel="${1:-release}"
  local target_path=""
  local target_dir=""
  local update_source=""
  local tmp_path=""
  local candidate_version=""

  target_path="$(resolve_safehouse_invocation_path)"
  target_dir="$(dirname "$target_path")"
  update_source="$(resolve_safehouse_update_source "$update_channel")"

  if safehouse_running_from_repo_checkout; then
    echo "safehouse update only supports standalone installed scripts." >&2
    echo "Current executable appears to be running from a source checkout: ${ROOT_DIR}" >&2
    echo "Update the repo checkout with git, then regenerate dist artifacts if needed." >&2
    exit 1
  fi

  if [[ -L "$target_path" ]]; then
    echo "safehouse update does not replace symlinked installs: ${target_path}" >&2
    echo "If this install is managed by Homebrew, run: brew upgrade agent-safehouse" >&2
    exit 1
  fi

  if [[ ! -f "$target_path" ]]; then
    echo "safehouse update expected a regular file executable at: ${target_path}" >&2
    exit 1
  fi

  if [[ ! -d "$target_dir" || ! -w "$target_dir" ]]; then
    echo "safehouse update cannot replace this install because the target directory is not writable: ${target_dir}" >&2
    exit 1
  fi

  tmp_path="$(mktemp "${target_path}.XXXXXX")"

  if ! fetch_safehouse_update_source "$update_source" "$tmp_path"; then
    rm -f "$tmp_path"
    echo "Failed to download the requested safehouse update asset." >&2
    echo "Source: ${update_source}" >&2
    echo "Install curl or wget, or set SAFEHOUSE_SELF_UPDATE_URL to a reachable asset URL or local file path." >&2
    exit 1
  fi

  chmod 0755 "$tmp_path"

  if ! safehouse_update_candidate_looks_valid "$tmp_path"; then
    rm -f "$tmp_path"
    echo "Downloaded update candidate does not look like a valid standalone safehouse release asset." >&2
    echo "Source: ${update_source}" >&2
    exit 1
  fi

  if cmp -s "$tmp_path" "$target_path"; then
    rm -f "$tmp_path"
    printf 'Already up to date: %s %s\n' "$safehouse_project_name" "$safehouse_project_version"
    return 0
  fi

  candidate_version="$(extract_safehouse_embedded_version "$tmp_path")"
  if [[ -z "$candidate_version" || "$candidate_version" == "__SAFEHOUSE_PROJECT_VERSION__" ]]; then
    candidate_version="unknown"
  fi

  mv "$tmp_path" "$target_path"
  printf 'Updated %s from %s to %s\n' "$target_path" "$safehouse_project_version" "$candidate_version"
}
