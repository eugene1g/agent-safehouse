#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

output_dir="${ROOT_DIR}/dist"
output_path="${output_dir}/safehouse.sh"
policy_output_dir="${output_dir}/profiles"
default_policy_path="${policy_output_dir}/safehouse.generated.sb"
apps_policy_path="${policy_output_dir}/safehouse-for-apps.generated.sb"
launcher_path="${output_dir}/Claude.app.sandboxed.command"
launcher_offline_path="${output_dir}/Claude.app.sandboxed-offline.command"
output_path_explicit=0
output_dir_explicit=0

GENERATOR="${ROOT_DIR}/bin/safehouse.sh"
template_root=""
template_home=""
template_workdir=""
static_home_placeholder="/__SAFEHOUSE_TEMPLATE_HOME__"
static_workdir_placeholder="/__SAFEHOUSE_TEMPLATE_WORKDIR__"

profile_files=()

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--output PATH] [--output-dir PATH]

Description:
  Generate all committed dist artifacts:
    - safehouse.sh (single-file executable with embedded profiles/runtime)
    - Claude.app.sandboxed.command (single-file launcher for Claude Desktop)
    - Claude.app.sandboxed-offline.command (single-file offline launcher for Claude Desktop)
    - profiles/safehouse.generated.sb (default static policy)
    - profiles/safehouse-for-apps.generated.sb (--enable=macos-gui,electron,all-agents,all-apps)

Options:
  --output PATH
      Dist executable output file path (default: ${output_path})

  --output-dir PATH
      Directory for launcher and static policy outputs (default: ${output_dir})

  -h, --help
      Show this help
USAGE
}

to_abs_path() {
  local path="$1"

  if [[ "$path" == /* ]]; then
    printf '%s\n' "$path"
  else
    printf '%s/%s\n' "$ROOT_DIR" "$path"
  fi
}

collect_profiles() {
  local rel_path

  while IFS= read -r rel_path; do
    profile_files+=("$rel_path")
  done < <(
    cd "$ROOT_DIR"
    find profiles -type f -name '*.sb' | LC_ALL=C sort
  )
}

count_profiles_with_prefix() {
  local prefix="$1"
  local count=0
  local profile

  for profile in "${profile_files[@]}"; do
    if [[ "$profile" == "${prefix}"* ]]; then
      count=$((count + 1))
    fi
  done

  printf '%s\n' "$count"
}

validate_profiles() {
  local required_path listed_path found
  local -a required=(
    "profiles/00-base.sb"
    "profiles/10-system-runtime.sb"
    "profiles/20-network.sb"
  )

  for required_path in "${required[@]}"; do
    found=0
    for listed_path in "${profile_files[@]}"; do
      if [[ "$listed_path" == "$required_path" ]]; then
        found=1
        break
      fi
    done

    if [[ "$found" -ne 1 ]]; then
      echo "Missing required profile file: ${required_path}" >&2
      exit 1
    fi
  done

  if [[ "$(count_profiles_with_prefix "profiles/30-toolchains/")" -eq 0 ]]; then
    echo "No toolchain profiles found under profiles/30-toolchains" >&2
    exit 1
  fi

  if [[ "$(count_profiles_with_prefix "profiles/40-shared/")" -eq 0 ]]; then
    echo "No shared profiles found under profiles/40-shared" >&2
    exit 1
  fi

  if [[ "$(count_profiles_with_prefix "profiles/60-agents/")" -eq 0 ]]; then
    echo "No agent profiles found under profiles/60-agents" >&2
    exit 1
  fi

  if [[ "$(count_profiles_with_prefix "profiles/65-apps/")" -eq 0 ]]; then
    echo "No app profiles found under profiles/65-apps" >&2
    exit 1
  fi

  if [[ "$(count_profiles_with_prefix "profiles/50-integrations-core/")" -eq 0 ]]; then
    echo "No core integration profiles found under profiles/50-integrations-core" >&2
    exit 1
  fi

  if [[ "$(count_profiles_with_prefix "profiles/55-integrations-optional/")" -eq 0 ]]; then
    echo "No optional integration profiles found under profiles/55-integrations-optional" >&2
    exit 1
  fi
}

marker_for_path() {
  local rel_path="$1"
  local marker="${rel_path//\//_}"
  marker="${marker//./_}"
  marker="${marker//-/_}"
  printf '__SAFEHOUSE_EMBEDDED_%s__' "$marker"
}

resolve_output_paths() {
  if [[ "$output_path_explicit" -eq 1 ]]; then
    output_path="$(to_abs_path "$output_path")"
  fi

  if [[ "$output_dir_explicit" -eq 1 ]]; then
    output_dir="$(to_abs_path "$output_dir")"
  fi

  if [[ "$output_path_explicit" -eq 0 && "$output_dir_explicit" -eq 1 ]]; then
    output_path="${output_dir%/}/safehouse.sh"
  fi

  output_path="$(to_abs_path "$output_path")"
  output_dir="$(to_abs_path "$output_dir")"
  policy_output_dir="${output_dir%/}/profiles"
  launcher_path="${output_dir%/}/Claude.app.sandboxed.command"
  launcher_offline_path="${output_dir%/}/Claude.app.sandboxed-offline.command"
  default_policy_path="${policy_output_dir}/safehouse.generated.sb"
  apps_policy_path="${policy_output_dir}/safehouse-for-apps.generated.sb"
  template_root="${output_dir%/}/agent-safehouse-static-template"
  template_home="${template_root}/home"
  template_workdir="${template_root}/workspace"
}

cleanup_template_root() {
  [[ -z "${template_root:-}" ]] || rm -rf "$template_root"
}

format_epoch_utc() {
  local epoch="$1"

  if date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ' >/dev/null 2>&1; then
    date -u -r "$epoch" '+%Y-%m-%dT%H:%M:%SZ'
    return
  fi

  date -u -d "@${epoch}" '+%Y-%m-%dT%H:%M:%SZ'
}

file_mtime_epoch() {
  local path="$1"

  if stat -f '%m' "$path" >/dev/null 2>&1; then
    stat -f '%m' "$path"
    return
  fi

  stat -c '%Y' "$path"
}

latest_embedded_profile_epoch_from_fs() {
  local rel_path profile_path epoch
  local latest_epoch=0

  for rel_path in "${profile_files[@]}"; do
    profile_path="${ROOT_DIR}/${rel_path}"
    epoch="$(file_mtime_epoch "$profile_path")" || continue

    if [[ "$epoch" =~ ^[0-9]+$ ]] && (( epoch > latest_epoch )); then
      latest_epoch="$epoch"
    fi
  done

  printf '%s\n' "$latest_epoch"
}

resolve_embedded_profiles_last_modified_utc() {
  local epoch

  # Prefer git commit metadata for deterministic output across machines/CI.
  epoch="$(git -C "$ROOT_DIR" log -1 --format=%ct -- "${profile_files[@]}" 2>/dev/null || true)"

  if [[ ! "$epoch" =~ ^[0-9]+$ ]] || (( epoch <= 0 )); then
    epoch="$(latest_embedded_profile_epoch_from_fs)"
  fi

  if [[ ! "$epoch" =~ ^[0-9]+$ ]] || (( epoch <= 0 )); then
    printf 'unknown\n'
    return
  fi

  format_epoch_utc "$epoch"
}

emit_banner() {
  local embedded_profiles_last_modified_utc="$1"

  cat <<SCRIPT
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Agent Safehouse Dist Binary (generated file)
# Project: https://agent-safehouse.dev
# Embedded Profiles Last Modified (UTC): ${embedded_profiles_last_modified_utc}
# Generated by: scripts/generate-dist.sh
# ---------------------------------------------------------------------------
set -euo pipefail

SCRIPT
}

validate_sb_string() {
  local value="$1"
  local label="${2:-SBPL string}"

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    echo "Invalid ${label}: contains control characters and cannot be emitted into SBPL." >&2
    return 1
  fi
}

escape_for_static_sb_literal() {
  local value="$1"

  validate_sb_string "$value" "policy token" || exit 1
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

rewrite_static_policy_home_dir_literal() {
  local policy_path="$1"
  local tmp_policy

  tmp_policy="$(mktemp "${policy_path}.XXXXXX")"
  awk -v static_home_placeholder="$static_home_placeholder" '
    BEGIN { replaced = 0 }
    /^\(define HOME_DIR "/ {
      if (replaced == 0) {
        print "(define HOME_DIR \"" static_home_placeholder "\")"
        replaced = 1
        next
      }
    }
    { print }
    END {
      if (replaced == 0) {
        exit 64
      }
    }
  ' "$policy_path" >"$tmp_policy" || {
    rm -f "$tmp_policy"
    echo "Failed to rewrite HOME_DIR in generated static policy: ${policy_path}" >&2
    exit 1
  }

  mv "$tmp_policy" "$policy_path"
}

emit_static_policy_path_ancestor_literals() {
  local path="$1"
  local label="$2"

  local trimmed cur IFS part escaped_cur
  local -a parts=()

  {
    echo ";; Generated ancestor directory literals for ${label}: ${path}"
    echo ";;"
    echo ";; Why file-read* (not file-read-metadata) with literal (not subpath):"
    echo ";; Agents (notably Claude Code) call readdir() on every ancestor of the working"
    echo ";; directory during startup. If only file-read-metadata (stat) is granted, the"
    echo ";; agent cannot list directory contents, which causes it to blank PATH and break."
    echo ";; Using 'literal' (not 'subpath') keeps this safe: it grants read access to the"
    echo ";; directory entry itself (i.e. listing its immediate children), but does NOT"
    echo ";; grant recursive read access to files or subdirectories under it."
    echo "(allow file-read*"
    echo "    (literal \"/\")"

    trimmed="${path#/}"
    if [[ -n "$trimmed" ]]; then
      cur=""
      IFS='/'
      read -r -a parts <<< "$trimmed"
      for part in "${parts[@]}"; do
        [[ -z "$part" ]] && continue
        cur+="/${part}"
        escaped_cur="$(escape_for_static_sb_literal "$cur")"
        echo "    (literal \"${escaped_cur}\")"
      done
    fi

    echo ")"
    echo ""
  }
}

append_static_policy_workdir_grant() {
  local policy_path="$1"
  local escaped_workdir

  escaped_workdir="$(escape_for_static_sb_literal "$static_workdir_placeholder")"

  {
    echo ";; #safehouse-test-id:workdir-grant# Allow read/write access to the selected workdir."
    emit_static_policy_path_ancestor_literals "$static_workdir_placeholder" "selected workdir"
    echo "(allow file-read* file-write* (subpath \"${escaped_workdir}\"))"
    echo ""
  } >>"$policy_path"
}

emit_array_declaration() {
  local name="$1"
  shift

  printf '%s=(\n' "$name"
  local item
  for item in "$@"; do
    printf '  "%s"\n' "$item"
  done
  printf ')\n\n'
}

emit_embedded_profiles_function() {
  local rel_path marker

  cat <<'SCRIPT'
embedded_profile_body() {
  case "$1" in
SCRIPT

  for rel_path in "${profile_files[@]}"; do
    marker="$(marker_for_path "$rel_path")"
    printf '    "%s")\n' "$rel_path"
    printf "      cat <<'%s'\n" "$marker"
    cat "${ROOT_DIR}/${rel_path}"
    if [[ -n "$(tail -c 1 "${ROOT_DIR}/${rel_path}" 2>/dev/null || true)" ]]; then
      echo ""
    fi
    printf '%s\n' "$marker"
    printf '      ;;\n'
  done

  cat <<'SCRIPT'
    *)
      return 1
      ;;
  esac
}

SCRIPT
}

emit_safehouse_globals() {
  awk '
    NR <= 2 { next }
    /^# shellcheck source=bin\/lib\/common.sh$/ { exit }
    { print }
  ' "${ROOT_DIR}/bin/safehouse.sh"

  echo ""
}

emit_inlined_runtime_sources() {
  cat "${ROOT_DIR}/bin/lib/common.sh"
  echo ""
  cat "${ROOT_DIR}/bin/lib/policy/10-options.sh"
  echo ""
  cat "${ROOT_DIR}/bin/lib/policy/20-profile-selection.sh"
  echo ""
  cat "${ROOT_DIR}/bin/lib/policy/30-assembly.sh"
  echo ""
  cat "${ROOT_DIR}/bin/lib/policy/40-generate.sh"
  echo ""
  cat "${ROOT_DIR}/bin/lib/cli.sh"
  echo ""
}

emit_embedded_overrides() {
  cat <<'SCRIPT'
profile_key_from_source() {
  local source="$1"

  if [[ "$source" == profiles/* ]]; then
    printf '%s\n' "$source"
    return
  fi

  if [[ -n "${PROFILES_DIR:-}" && "$source" == "${PROFILES_DIR}/"* ]]; then
    printf 'profiles/%s\n' "${source#"${PROFILES_DIR}/"}"
    return
  fi

  printf '%s\n' "$source"
}

profile_declares_requirement() {
  local profile_path="$1"
  local required_integration="$2"
  local required_normalized line raw_requirements entry normalized_entry profile_key
  local -a requirement_entries=()

  required_normalized="$(to_lowercase "$required_integration")"
  profile_key="$(profile_key_from_source "$profile_path")"

  if embedded_profile_body "$profile_key" >/dev/null 2>&1; then
    while IFS= read -r line; do
      [[ "$line" == *'$$require='*'$$'* ]] || continue
      raw_requirements="${line#*\$\$require=}"
      raw_requirements="${raw_requirements%%\$\$*}"
      raw_requirements="$(trim_whitespace "$raw_requirements")"
      [[ -n "$raw_requirements" ]] || continue

      IFS=',' read -r -a requirement_entries <<< "$raw_requirements"
      for entry in "${requirement_entries[@]}"; do
        normalized_entry="$(to_lowercase "$(trim_whitespace "$entry")")"
        [[ -n "$normalized_entry" ]] || continue
        if [[ "$normalized_entry" == "$required_normalized" ]]; then
          return 0
        fi
      done
    done < <(embedded_profile_body "$profile_key")
    return 1
  fi

  if [[ ! -f "$profile_path" ]]; then
    return 1
  fi

  while IFS= read -r line; do
    [[ "$line" == *'$$require='*'$$'* ]] || continue
    raw_requirements="${line#*\$\$require=}"
    raw_requirements="${raw_requirements%%\$\$*}"
    raw_requirements="$(trim_whitespace "$raw_requirements")"
    [[ -n "$raw_requirements" ]] || continue

    IFS=',' read -r -a requirement_entries <<< "$raw_requirements"
    for entry in "${requirement_entries[@]}"; do
      normalized_entry="$(to_lowercase "$(trim_whitespace "$entry")")"
      [[ -n "$normalized_entry" ]] || continue
      if [[ "$normalized_entry" == "$required_normalized" ]]; then
        return 0
      fi
    done
  done < "$profile_path"

  return 1
}

selected_profiles_require_integration() {
  local integration="$1"
  local integration_normalized profile_key
  local requires_integration=0

  integration_normalized="$(to_lowercase "$integration")"

  if [[ "$integration_normalized" == "$keychain_requirement_token" && "$selected_profiles_require_keychain_resolved" -eq 1 ]]; then
    [[ "$selected_profiles_require_keychain" -eq 1 ]]
    return
  fi

  for profile_key in "${PROFILE_KEYS[@]}"; do
    case "$profile_key" in
      profiles/60-agents/*.sb|profiles/65-apps/*.sb)
        should_include_agent_profile_file "$profile_key" || continue
        if profile_declares_requirement "$profile_key" "$integration_normalized"; then
          requires_integration=1
          break
        fi
        ;;
    esac
  done

  if [[ "$integration_normalized" == "$keychain_requirement_token" ]]; then
    selected_profiles_require_keychain="$requires_integration"
    selected_profiles_require_keychain_resolved=1
  fi

  [[ "$requires_integration" -eq 1 ]]
}

append_profile() {
  local target="$1"
  local source="$2"
  local key content

  key="$(profile_key_from_source "$source")"
  if content="$(embedded_profile_body "$key" 2>/dev/null)"; then
    append_policy_chunk "$content"
    append_policy_chunk ""
    return
  fi

  # Fallback: read from disk (needed for --append-profile with external files).
  if [[ -f "$source" ]]; then
    content="$(<"$source")"
    append_policy_chunk "$content"
    append_policy_chunk ""
    return
  fi

  echo "Missing profile module: ${source}" >&2
  exit 1
}

append_resolved_base_profile() {
  local target="$1"
  local source="$2"
  local escaped_home key resolved_base
  local first_line rest

  escaped_home="$(escape_for_sb "$home_dir")"
  key="$(profile_key_from_source "$source")"
  if ! resolved_base="$(embedded_profile_body "$key" | replace_literal_stream_required "$HOME_DIR_TEMPLATE_TOKEN" "$escaped_home")"; then
    echo "Failed to resolve HOME_DIR placeholder in base profile: ${source}" >&2
    echo "Expected HOME_DIR placeholder token: ${HOME_DIR_TEMPLATE_TOKEN}" >&2
    exit 1
  fi

  first_line="${resolved_base%%$'\n'*}"
  if [[ "$resolved_base" == *$'\n'* ]]; then
    rest="${resolved_base#*$'\n'}"
  else
    rest=""
  fi

  append_policy_chunk "$first_line"
  append_policy_chunk ""
  emit_policy_origin_preamble "$target"
  append_policy_chunk "$rest"
  append_policy_chunk ""
}

append_all_module_profiles() {
  local target="$1"
  local base_dir="$2"
  local found_any=0
  local appended_any=0
  local is_scoped_profile_dir=0
  local emit_no_match_note=0
  local key profile_prefix

  case "$base_dir" in
    "${PROFILES_DIR}/30-toolchains"|"profiles/30-toolchains")
      profile_prefix="profiles/30-toolchains/"
      ;;
    "${PROFILES_DIR}/40-shared"|"profiles/40-shared")
      profile_prefix="profiles/40-shared/"
      ;;
    "${PROFILES_DIR}/50-integrations-core"|"profiles/50-integrations-core")
      profile_prefix="profiles/50-integrations-core/"
      ;;
    "${PROFILES_DIR}/60-agents"|"profiles/60-agents")
      profile_prefix="profiles/60-agents/"
      is_scoped_profile_dir=1
      emit_no_match_note=1
      ;;
    "${PROFILES_DIR}/65-apps"|"profiles/65-apps")
      profile_prefix="profiles/65-apps/"
      is_scoped_profile_dir=1
      ;;
    *)
      echo "No module profiles found in: ${base_dir}" >&2
      exit 1
      ;;
  esac

  for key in "${PROFILE_KEYS[@]}"; do
    [[ "$key" == "${profile_prefix}"* ]] || continue
    found_any=1

    if [[ "$is_scoped_profile_dir" -eq 1 ]] && ! should_include_agent_profile_file "$key"; then
      continue
    fi
    appended_any=1
    append_profile "$target" "$key"
  done

  if [[ "$found_any" -eq 0 ]]; then
    echo "No module profiles found in: ${base_dir}" >&2
    exit 1
  fi

  if [[ "$is_scoped_profile_dir" -eq 1 ]]; then
    if [[ ( "$base_dir" == "${PROFILES_DIR}/60-agents" || "$base_dir" == "profiles/60-agents" ) && "$enable_all_agents_profiles" -eq 1 ]]; then
      return 0
    fi

    if [[ ( "$base_dir" == "${PROFILES_DIR}/65-apps" || "$base_dir" == "profiles/65-apps" ) && "$enable_all_apps_profiles" -eq 1 ]]; then
      return 0
    fi

    if [[ "$appended_any" -eq 0 && "$emit_no_match_note" -eq 1 ]]; then
      resolve_selected_agent_profiles
      if [[ "${#selected_agent_profile_basenames[@]}" -eq 0 ]]; then
        append_policy_chunk ";; No command-matched app/agent profile selected; skipping 60-agents and 65-apps modules."
        append_policy_chunk ";; Use --enable=all-agents,all-apps to restore legacy all-profile behavior."
        append_policy_chunk ""
      fi
    fi
    return 0
  fi

  if [[ "$appended_any" -eq 0 ]]; then
    echo "No module profiles selected in: ${base_dir}" >&2
    exit 1
  fi
}

append_optional_integration_profiles() {
  local target="$1"
  local base_dir="$2"
  local key base_name
  local found_any=0

  case "$base_dir" in
    "${PROFILES_DIR}/55-integrations-optional"|"profiles/55-integrations-optional")
      ;;
    *)
      echo "No optional integration profiles found in: ${base_dir}" >&2
      exit 1
      ;;
  esac

  ensure_optional_integrations_classified

  for key in "${PROFILE_KEYS[@]}"; do
    [[ "$key" == "profiles/55-integrations-optional/"* ]] || continue
    found_any=1

    base_name="${key##*/}"
    optional_integration_classified_included "$base_name" || continue

    append_profile "$target" "$key"
  done

  if [[ "$found_any" -eq 0 ]]; then
    echo "No optional integration profiles found in: ${base_dir}" >&2
    exit 1
  fi
}

SCRIPT
}

emit_dist_script_body() {
  local embedded_profiles_last_modified_utc="$1"

  emit_banner "$embedded_profiles_last_modified_utc"
  emit_array_declaration "PROFILE_KEYS" "${profile_files[@]}"
  emit_embedded_profiles_function
  emit_safehouse_globals
  emit_inlined_runtime_sources
  emit_embedded_overrides
}

write_dist_script() {
  local target_path="$1"
  local embedded_profiles_last_modified_utc="$2"
  local tmp_output

  mkdir -p "$(dirname "$target_path")"
  tmp_output="$(mktemp "${target_path}.XXXXXX")"

  {
    emit_dist_script_body "$embedded_profiles_last_modified_utc"
    echo 'main "$@"'
  } >"$tmp_output"

  chmod 0755 "$tmp_output"
  mv "$tmp_output" "$target_path"
}

write_claude_launcher() {
  local target_path="$1"
  local tmp_output

  mkdir -p "$(dirname "$target_path")"
  tmp_output="$(mktemp "${target_path}.XXXXXX")"

  {
    cat <<'SCRIPT'
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Agent Safehouse Claude Desktop Launcher (generated file)
# Purpose: Launch Claude Desktop sandboxed to this file's directory.
#          Fetch latest apps policy from GitHub at runtime.
# Project: https://agent-safehouse.dev
# Generated by: scripts/generate-dist.sh
# ---------------------------------------------------------------------------
set -euo pipefail

claude_desktop_binary="/Applications/Claude.app/Contents/MacOS/Claude"
default_policy_url="https://raw.githubusercontent.com/eugene1g/agent-safehouse/main/dist/profiles/safehouse-for-apps.generated.sb"
project_url="https://agent-safehouse.dev"

validate_sb_string() {
  local value="$1"
  local label="${2:-SBPL string}"

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    echo "Invalid ${label}: contains control characters and cannot be emitted into SBPL." >&2
    exit 1
  fi
}

escape_for_sb() {
  local value="$1"

  validate_sb_string "$value" "policy token" || exit 1
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

policy_checksum_256() {
  local path="$1"

  if command -v shasum >/dev/null 2>&1; then
    shasum -a 256 "$path" | awk '{print $1}'
    return 0
  fi

  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "$path" | awk '{print $1}'
    return 0
  fi

  if command -v openssl >/dev/null 2>&1; then
    openssl dgst -sha256 "$path" | awk '{print $NF}'
    return 0
  fi

  return 1
}

policy_checksum_matches() {
  local policy_path="$1"
  local expected="$2"
  local actual

  actual="$(policy_checksum_256 "$policy_path")" || return 1

  [[ "$actual" == "$expected" ]]
}

replace_literal_stream() {
  local from="$1"
  local to="$2"

  awk -v from="$from" -v to="$to" '
    {
      if (from == "") {
        print $0
        next
      }

      line = $0
      out = ""
      from_len = length(from)
      while ((idx = index(line, from)) > 0) {
        out = out substr(line, 1, idx - 1) to
        line = substr(line, idx + from_len)
      }

      print out line
    }
  '
}

fetch_remote_policy() {
  local url="$1"
  local output_path="$2"

  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL --connect-timeout 10 --retry 2 --retry-delay 1 "$url" -o "$output_path"; then
      return 0
    fi
  fi

  if command -v wget >/dev/null 2>&1; then
    if wget -q -O "$output_path" "$url"; then
      return 0
    fi
  fi

  return 1
}

policy_template_looks_valid() {
  local policy_candidate="$1"

  [[ -f "$policy_candidate" ]] || return 1
  grep -Fq "(version 1)" "$policy_candidate" || return 1
  grep -Fq "(define HOME_DIR \"" "$policy_candidate" || return 1
  grep -Fq "#safehouse-test-id:electron-integration#" "$policy_candidate" || return 1

  return 0
}

emit_path_ancestor_literals() {
  local path_value="$1"
  local current="$path_value"
  local escaped
  local -a ancestors=()

  while true; do
    ancestors+=("$current")
    [[ "$current" == "/" ]] && break
    current="$(dirname "$current")"
  done

  local idx
  for ((idx=${#ancestors[@]} - 1; idx>=0; idx--)); do
    escaped="$(escape_for_sb "${ancestors[$idx]}")"
    printf '    (literal "%s")\n' "$escaped"
  done
}

main() {
  local home_dir launcher_workdir escaped_home escaped_workdir policy_source_path policy_path
  local remote_policy_url template_home_path policy_expected_sha256

  if [[ ! -x "$claude_desktop_binary" ]]; then
    echo "Claude Desktop binary not found at ${claude_desktop_binary}" >&2
    exit 1
  fi

  if ! command -v sandbox-exec >/dev/null 2>&1; then
    echo "sandbox-exec is required but was not found in PATH" >&2
    exit 1
  fi

  home_dir="${HOME:-}"
  if [[ -z "$home_dir" || ! -d "$home_dir" ]]; then
    echo "HOME must be set to an existing directory" >&2
    exit 1
  fi

  launcher_workdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  escaped_home="$(escape_for_sb "$home_dir")"
  escaped_workdir="$(escape_for_sb "$launcher_workdir")"
  policy_source_path="$(mktemp "/tmp/claude-safehouse-source-policy.XXXXXX")"
  policy_path="$(mktemp "/tmp/claude-safehouse-policy.XXXXXX")"

  cleanup_policy() {
    rm -f "$policy_source_path" "$policy_path"
  }
  trap cleanup_policy EXIT

  remote_policy_url="${SAFEHOUSE_CLAUDE_POLICY_URL:-$default_policy_url}"
  validate_sb_string "$remote_policy_url" "policy URL" || exit 1
  policy_expected_sha256="${SAFEHOUSE_CLAUDE_POLICY_SHA256:-}"
  if [[ -n "$policy_expected_sha256" ]]; then
    validate_sb_string "$policy_expected_sha256" "policy SHA-256" || exit 1
  fi

  if ! fetch_remote_policy "$remote_policy_url" "$policy_source_path"; then
    echo "Failed to download sandbox policy from ${remote_policy_url}" >&2
    echo "Install curl or wget, or set SAFEHOUSE_CLAUDE_POLICY_URL to a reachable policy URL." >&2
    echo "Help: ${project_url}" >&2
    exit 1
  fi
  if ! policy_template_looks_valid "$policy_source_path"; then
    echo "Downloaded policy is invalid: ${remote_policy_url}" >&2
    echo "Help: ${project_url}" >&2
    exit 1
  fi

  if [[ -n "$policy_expected_sha256" ]]; then
    if ! policy_checksum_matches "$policy_source_path" "$policy_expected_sha256"; then
      echo "Downloaded policy SHA-256 does not match SAFEHOUSE_CLAUDE_POLICY_SHA256." >&2
      echo "Expected: ${policy_expected_sha256}" >&2
      echo "Could not verify: install one of shasum/sha256sum/openssl." >&2
      exit 1
    fi
  fi

  template_home_path="$(awk -F'"' '/^\(define HOME_DIR "/ { print $2; exit }' "$policy_source_path")"
  if [[ -z "${template_home_path:-}" ]]; then
    echo "Failed to parse HOME_DIR from launcher policy source (${remote_policy_url})" >&2
    exit 1
  fi

  {
    replace_literal_stream "$template_home_path" "$escaped_home" < "$policy_source_path"
    cat <<POLICY

;; #safehouse-test-id:workdir-grant# Allow read/write access to the selected workdir.
;; Generated ancestor directory literals for selected workdir: ${launcher_workdir}
;; Why file-read* (not file-read-metadata) with literal (not subpath):
;; Agents (notably Claude Code) call readdir() on every ancestor of the working
;; directory to discover project structure. file-read-metadata on the leaf is not
;; enough; each ancestor directory itself must be traversable. literal confines
;; access to the directory entry only (no recursion), so this does not grant
;; recursive read access to files or subdirectories under it.
(allow file-read*
$(emit_path_ancestor_literals "$launcher_workdir")
)

(allow file-read* file-write* (subpath "$escaped_workdir"))
POLICY
  } > "$policy_path"

  cd "$launcher_workdir"
  sandbox-exec -f "$policy_path" -- "$claude_desktop_binary" --no-sandbox "$@"
}

main "$@"
SCRIPT
  } >"$tmp_output"

  chmod 0755 "$tmp_output"
  mv "$tmp_output" "$target_path"
}

write_claude_offline_launcher() {
  local target_path="$1"
  local embedded_policy_source="$2"
  local tmp_output

  if [[ ! -f "$embedded_policy_source" ]]; then
    echo "Embedded launcher policy source is missing: ${embedded_policy_source}" >&2
    exit 1
  fi

  mkdir -p "$(dirname "$target_path")"
  tmp_output="$(mktemp "${target_path}.XXXXXX")"

  {
    cat <<'SCRIPT'
#!/usr/bin/env bash
# ---------------------------------------------------------------------------
# Agent Safehouse Claude Desktop Offline Launcher (generated file)
# Purpose: Launch Claude Desktop sandboxed to this file's directory.
#          Uses an embedded apps policy (no runtime download required).
# Project: https://agent-safehouse.dev
# Generated by: scripts/generate-dist.sh
# ---------------------------------------------------------------------------
set -euo pipefail

claude_desktop_binary="/Applications/Claude.app/Contents/MacOS/Claude"
project_url="https://agent-safehouse.dev"

validate_sb_string() {
  local value="$1"
  local label="${2:-SBPL string}"

  if [[ "$value" =~ [[:cntrl:]] ]]; then
    echo "Invalid ${label}: contains control characters and cannot be emitted into SBPL." >&2
    exit 1
  fi
}

escape_for_sb() {
  local value="$1"

  validate_sb_string "$value" "policy token" || exit 1
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  printf '%s' "$value"
}

replace_literal_stream() {
  local from="$1"
  local to="$2"

  awk -v from="$from" -v to="$to" '
    {
      if (from == "") {
        print $0
        next
      }

      line = $0
      out = ""
      from_len = length(from)
      while ((idx = index(line, from)) > 0) {
        out = out substr(line, 1, idx - 1) to
        line = substr(line, idx + from_len)
      }

      print out line
    }
  '
}

policy_template_looks_valid() {
  local policy_candidate="$1"

  [[ -f "$policy_candidate" ]] || return 1
  grep -Fq "(version 1)" "$policy_candidate" || return 1
  grep -Fq "(define HOME_DIR \"" "$policy_candidate" || return 1
  grep -Fq "#safehouse-test-id:electron-integration#" "$policy_candidate" || return 1

  return 0
}

emit_embedded_policy_template() {
  cat <<'SAFEHOUSE_EMBEDDED_APPS_POLICY'
SCRIPT
    cat "$embedded_policy_source"
    if [[ -n "$(tail -c 1 "$embedded_policy_source" 2>/dev/null || true)" ]]; then
      echo ""
    fi
    cat <<'SCRIPT'
SAFEHOUSE_EMBEDDED_APPS_POLICY
}

emit_path_ancestor_literals() {
  local path_value="$1"
  local current="$path_value"
  local escaped
  local -a ancestors=()

  while true; do
    ancestors+=("$current")
    [[ "$current" == "/" ]] && break
    current="$(dirname "$current")"
  done

  local idx
  for ((idx=${#ancestors[@]} - 1; idx>=0; idx--)); do
    escaped="$(escape_for_sb "${ancestors[$idx]}")"
    printf '    (literal "%s")\n' "$escaped"
  done
}

main() {
  local home_dir launcher_workdir escaped_home escaped_workdir policy_source_path policy_path
  local template_home_path

  if [[ ! -x "$claude_desktop_binary" ]]; then
    echo "Claude Desktop binary not found at ${claude_desktop_binary}" >&2
    exit 1
  fi

  if ! command -v sandbox-exec >/dev/null 2>&1; then
    echo "sandbox-exec is required but was not found in PATH" >&2
    exit 1
  fi

  home_dir="${HOME:-}"
  if [[ -z "$home_dir" || ! -d "$home_dir" ]]; then
    echo "HOME must be set to an existing directory" >&2
    exit 1
  fi

  launcher_workdir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  escaped_home="$(escape_for_sb "$home_dir")"
  escaped_workdir="$(escape_for_sb "$launcher_workdir")"
  policy_source_path="$(mktemp "/tmp/claude-safehouse-source-policy.XXXXXX")"
  policy_path="$(mktemp "/tmp/claude-safehouse-policy.XXXXXX")"

  cleanup_policy() {
    rm -f "$policy_source_path" "$policy_path"
  }
  trap cleanup_policy EXIT

  emit_embedded_policy_template > "$policy_source_path"
  if ! policy_template_looks_valid "$policy_source_path"; then
    echo "Embedded launcher policy template is invalid." >&2
    echo "Download a fresh launcher from ${project_url}" >&2
    echo "Help: ${project_url}" >&2
    exit 1
  fi

  template_home_path="$(awk -F'"' '/^\(define HOME_DIR \"/ { print $2; exit }' "$policy_source_path")"
  if [[ -z "${template_home_path:-}" ]]; then
    echo "Failed to parse HOME_DIR from embedded launcher policy template" >&2
    echo "Help: ${project_url}" >&2
    exit 1
  fi

  {
    replace_literal_stream "$template_home_path" "$escaped_home" < "$policy_source_path"
    cat <<POLICY

;; #safehouse-test-id:workdir-grant# Allow read/write access to the selected workdir.
;; Generated ancestor directory literals for selected workdir: ${launcher_workdir}
;; Why file-read* (not file-read-metadata) with literal (not subpath):
;; Agents (notably Claude Code) call readdir() on every ancestor of the working
;; directory to discover project structure. file-read-metadata on the leaf is not
;; enough; each ancestor directory itself must be traversable. literal confines
;; access to the directory entry only (no recursion), so this does not grant
;; recursive read access to files or subdirectories under it.
(allow file-read*
$(emit_path_ancestor_literals "$launcher_workdir")
)

(allow file-read* file-write* (subpath "$escaped_workdir"))
POLICY
  } > "$policy_path"

  cd "$launcher_workdir"
  sandbox-exec -f "$policy_path" -- "$claude_desktop_binary" --no-sandbox "$@"
}

main "$@"
SCRIPT
  } >"$tmp_output"

  chmod 0755 "$tmp_output"
  mv "$tmp_output" "$target_path"
}

generate_static_policy_files() {
  if [[ ! -x "$GENERATOR" ]]; then
    echo "Policy generator is missing or not executable: ${GENERATOR}" >&2
    exit 1
  fi

  rm -rf "$template_root"
  mkdir -p "$output_dir" "$policy_output_dir" "$template_home" "$template_workdir"

  (
    cd "$template_workdir"
    HOME="$template_home" "$GENERATOR" --enable=all-agents --workdir="" --output "$default_policy_path" >/dev/null
    HOME="$template_home" "$GENERATOR" --enable=macos-gui,electron,all-agents,all-apps --workdir="" --output "$apps_policy_path" >/dev/null
  )

  rewrite_static_policy_home_dir_literal "$default_policy_path"
  rewrite_static_policy_home_dir_literal "$apps_policy_path"

  append_static_policy_workdir_grant "$default_policy_path"
  append_static_policy_workdir_grant "$apps_policy_path"

  chmod 0644 "$default_policy_path" "$apps_policy_path"
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --output)
      [[ $# -ge 2 ]] || {
        echo "Missing value for $1" >&2
        exit 1
      }
      output_path="$2"
      output_path_explicit=1
      shift 2
      ;;
    --output=*)
      output_path="${1#*=}"
      output_path_explicit=1
      shift
      ;;
    --output-dir)
      [[ $# -ge 2 ]] || {
        echo "Missing value for $1" >&2
        exit 1
      }
      output_dir="$2"
      output_dir_explicit=1
      shift 2
      ;;
    --output-dir=*)
      output_dir="${1#*=}"
      output_dir_explicit=1
      shift
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      echo "Unknown option: $1" >&2
      usage >&2
      exit 1
      ;;
  esac
done

resolve_output_paths
trap cleanup_template_root EXIT

collect_profiles
validate_profiles

embedded_profiles_last_modified_utc="$(resolve_embedded_profiles_last_modified_utc)"

write_dist_script "$output_path" "$embedded_profiles_last_modified_utc"
write_claude_launcher "$launcher_path"

generate_static_policy_files
write_claude_offline_launcher "$launcher_offline_path" "$apps_policy_path"

printf '%s\n' "$output_path"
printf '%s\n' "$launcher_path"
printf '%s\n' "$launcher_offline_path"
printf '%s\n' "$default_policy_path"
printf '%s\n' "$apps_policy_path"
