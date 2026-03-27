#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"

output_dir="${ROOT_DIR}/dist"
output_path="${output_dir}/safehouse.sh"
output_path_explicit=0
output_dir_explicit=0

project_version_file="${ROOT_DIR}/VERSION"
project_version_placeholder="__SAFEHOUSE_PROJECT_VERSION__"
source_manifest_file="${ROOT_DIR}/bin/lib/bootstrap/source-manifest.sh"

profile_files=()
lib_source_files=()
embedded_optional_integration_features=()
embedded_supported_enable_features=""
embedded_supported_enable_synthetic_features=(
  all-agents
  all-apps
  wide-read
)
generator_metadata_helpers_loaded=0
dist_preassembled_fixed_before_home_keys=()
dist_preassembled_fixed_after_home_keys=()
dist_preassembled_core_integration_keys=()

usage() {
  cat <<USAGE
Usage:
  $(basename "$0") [--output PATH] [--output-dir PATH]

Description:
  Generate the committed dist executable:
    - safehouse.sh (single-file executable with embedded profiles/runtime)

Options:
  --output PATH
      Dist executable output file path (default: ${output_path})

  --output-dir PATH
      Directory for dist executable output (default: ${output_dir})

  -h, --help
      Show this help
USAGE
}

read_project_version() {
  local version=""

  if [[ ! -f "$project_version_file" ]]; then
    echo "Missing VERSION file: ${project_version_file}" >&2
    exit 1
  fi

  IFS= read -r version <"$project_version_file" || true
  version="${version%%$'\r'}"
  if [[ -z "$version" ]]; then
    echo "VERSION file is empty: ${project_version_file}" >&2
    exit 1
  fi

  if [[ "$version" =~ [[:cntrl:]] ]]; then
    echo "VERSION file contains control characters: ${project_version_file}" >&2
    exit 1
  fi

  printf '%s\n' "$version"
}

escape_for_shell_double_quotes() {
  local value="$1"

  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//\$/\\$}"
  value="${value//\`/\\\`}"
  printf '%s' "$value"
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

collect_lib_sources() {
  SAFEHOUSE_LIB_SOURCE_MANIFEST=()

  if [[ ! -f "$source_manifest_file" ]]; then
    echo "Missing source manifest: ${source_manifest_file}" >&2
    exit 1
  fi

  # shellcheck disable=SC1091
  # shellcheck source=bin/lib/bootstrap/source-manifest.sh
  source "$source_manifest_file"
  if [[ "${#SAFEHOUSE_LIB_SOURCE_MANIFEST[@]}" -eq 0 ]]; then
    echo "Source manifest did not declare any library files: ${source_manifest_file}" >&2
    exit 1
  fi

  lib_source_files=("${SAFEHOUSE_LIB_SOURCE_MANIFEST[@]}")
}

load_generator_metadata_helpers() {
  local rel_path
  local metadata_loaded=0

  if [[ "$generator_metadata_helpers_loaded" -eq 1 ]]; then
    return 0
  fi

  if [[ "${#lib_source_files[@]}" -eq 0 ]]; then
    collect_lib_sources
  fi

  for rel_path in "${lib_source_files[@]}"; do
    # shellcheck disable=SC1090
    source "${ROOT_DIR}/bin/lib/${rel_path}"
    if [[ "$rel_path" == "policy/metadata.sh" ]]; then
      metadata_loaded=1
      break
    fi
  done

  if [[ "$metadata_loaded" -ne 1 ]]; then
    echo "Source manifest does not include policy/metadata.sh: ${source_manifest_file}" >&2
    exit 1
  fi

  generator_metadata_helpers_loaded=1
}

validate_embedded_agent_command_alias_catalog() {
  local profile_key command_alias
  local idx
  local -a seen_aliases=()
  local -a seen_profile_keys=()
  local -a profile_aliases=()

  load_generator_metadata_helpers

  for profile_key in "${profile_files[@]}"; do
    [[ "$profile_key" == profiles/60-agents/*.sb ]] || continue

    profile_aliases=()
    while IFS= read -r command_alias || [[ -n "$command_alias" ]]; do
      [[ -n "$command_alias" ]] || continue

      if [[ "${#profile_aliases[@]}" -gt 0 ]]; then
        if safehouse_array_contains_exact "$command_alias" "${profile_aliases[@]}"; then
          safehouse_fail "Agent profile ${profile_key} declares duplicate \$\$command alias: ${command_alias}"
          return 1
        fi
      fi
      profile_aliases+=("$command_alias")

      if [[ "${#seen_aliases[@]}" -gt 0 ]]; then
        for idx in "${!seen_aliases[@]}"; do
          if [[ "${seen_aliases[$idx]}" == "$command_alias" ]]; then
            safehouse_fail "Command alias ${command_alias} is declared by multiple agent profiles: ${seen_profile_keys[$idx]}, ${profile_key}"
            return 1
          fi
        done
      fi

      seen_aliases+=("$command_alias")
      seen_profile_keys+=("$profile_key")
    done < <(policy_metadata_emit_profile_command_alias_tokens "$profile_key")
  done
}

optional_integration_feature_from_profile_path() {
  local rel_path="$1"
  local feature

  case "$rel_path" in
    profiles/55-integrations-optional/*.sb)
      feature="${rel_path##*/}"
      feature="${feature%.sb}"
      printf '%s\n' "$feature"
      return 0
      ;;
  esac

  return 1
}

build_embedded_supported_enable_features_csv() {
  local feature
  local supported_csv=""
  local need_separator=0

  for feature in "${embedded_optional_integration_features[@]}"; do
    if [[ "$need_separator" -eq 1 ]]; then
      supported_csv+=", "
    fi
    supported_csv+="$feature"
    need_separator=1
  done

  for feature in "${embedded_supported_enable_synthetic_features[@]}"; do
    if [[ "$need_separator" -eq 1 ]]; then
      supported_csv+=", "
    fi
    supported_csv+="$feature"
    need_separator=1
  done

  printf '%s\n' "$supported_csv"
}

collect_embedded_feature_catalog() {
  local rel_path feature

  embedded_optional_integration_features=()
  embedded_supported_enable_features=""

  for rel_path in "${profile_files[@]}"; do
    feature="$(optional_integration_feature_from_profile_path "$rel_path")" || continue
    embedded_optional_integration_features+=("$feature")
  done

  if [[ "${#embedded_optional_integration_features[@]}" -eq 0 ]]; then
    echo "No user-exposed optional integration profiles found under profiles/55-integrations-optional" >&2
    exit 1
  fi

  embedded_supported_enable_features="$(build_embedded_supported_enable_features_csv)"
}

collect_dist_preassembled_render_chunks() {
  local rel_path

  dist_preassembled_fixed_before_home_keys=()
  dist_preassembled_fixed_after_home_keys=()
  dist_preassembled_core_integration_keys=()

  for rel_path in "${profile_files[@]}"; do
    case "$rel_path" in
      "profiles/10-system-runtime.sb")
        dist_preassembled_fixed_before_home_keys+=("$rel_path")
        ;;
      "profiles/20-network.sb" | profiles/30-toolchains/*.sb | profiles/40-shared/*.sb)
        dist_preassembled_fixed_after_home_keys+=("$rel_path")
        ;;
      profiles/50-integrations-core/worktree-common-dir.sb | profiles/50-integrations-core/worktrees.sb)
        :
        ;;
      profiles/50-integrations-core/*.sb)
        dist_preassembled_core_integration_keys+=("$rel_path")
        ;;
    esac
  done

  if [[ "${#dist_preassembled_fixed_before_home_keys[@]}" -eq 0 ]]; then
    echo "Dist preassembled fixed-before-home chunk is empty." >&2
    exit 1
  fi

  if [[ "${#dist_preassembled_fixed_after_home_keys[@]}" -eq 0 ]]; then
    echo "Dist preassembled fixed-after-home chunk is empty." >&2
    exit 1
  fi

  if [[ "${#dist_preassembled_core_integration_keys[@]}" -eq 0 ]]; then
    echo "Dist preassembled core-integration chunk is empty." >&2
    exit 1
  fi
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
}

cleanup_committed_obsolete_dist_artifacts() {
  rm -f \
    "${ROOT_DIR}/dist/Claude.app.sandboxed.command" \
    "${ROOT_DIR}/dist/Claude.app.sandboxed-offline.command"
  rm -rf "${ROOT_DIR}/dist/profiles"
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

    if [[ "$epoch" =~ ^[0-9]+$ ]] && ((epoch > latest_epoch)); then
      latest_epoch="$epoch"
    fi
  done

  printf '%s\n' "$latest_epoch"
}

resolve_embedded_profiles_last_modified_utc() {
  local epoch

  # Prefer git commit metadata for deterministic output across machines/CI.
  epoch="$(git -C "$ROOT_DIR" log -1 --format=%ct -- "${profile_files[@]}" 2>/dev/null || true)"

  if [[ ! "$epoch" =~ ^[0-9]+$ ]] || ((epoch <= 0)); then
    epoch="$(latest_embedded_profile_epoch_from_fs)"
  fi

  if [[ ! "$epoch" =~ ^[0-9]+$ ]] || ((epoch <= 0)); then
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

emit_profile_chunk_body() {
  local rel_path

  for rel_path in "$@"; do
    cat "${ROOT_DIR}/${rel_path}"
    if [[ -n "$(tail -c 1 "${ROOT_DIR}/${rel_path}" 2>/dev/null || true)" ]]; then
      echo ""
    fi
    echo ""
  done
}

emit_embedded_metadata_case_branch() {
  local rel_path="$1"
  local emitter_name="$2"
  local values="" value

  values="$("$emitter_name" "$rel_path")"

  printf '    "%s")\n' "$rel_path"
  if [[ -n "$values" ]]; then
    printf "      printf '%%s\\\\n'"
    while IFS= read -r value || [[ -n "$value" ]]; do
      printf ' "%s"' "$(escape_for_shell_double_quotes "$value")"
    done <<<"$values"
    printf '\n'
  else
    printf '      :\n'
  fi
  printf '      ;;\n'
}

emit_profile_requirement_tokens_for_dist() {
  local profile_key="$1"

  load_generator_metadata_helpers
  policy_metadata_emit_profile_requirement_tokens "$profile_key"
}

emit_profile_command_alias_tokens_for_dist() {
  local profile_key="$1"

  load_generator_metadata_helpers
  policy_metadata_emit_profile_command_alias_tokens "$profile_key"
}

emit_profile_exec_env_defaults_for_dist() {
  local profile_key="$1"

  load_generator_metadata_helpers
  policy_metadata_emit_profile_exec_env_defaults "$profile_key"
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

emit_embedded_profile_requirements_function() {
  local rel_path

  cat <<'SCRIPT'
policy_dist_emit_embedded_profile_requirement_tokens() {
  case "$1" in
SCRIPT

  for rel_path in "${profile_files[@]}"; do
    emit_embedded_metadata_case_branch "$rel_path" "emit_profile_requirement_tokens_for_dist"
  done

  cat <<'SCRIPT'
    *)
      return 1
      ;;
  esac
}

SCRIPT
}

emit_embedded_profile_command_aliases_function() {
  local rel_path

  cat <<'SCRIPT'
policy_dist_emit_embedded_profile_command_alias_tokens() {
  case "$1" in
SCRIPT

  for rel_path in "${profile_files[@]}"; do
    emit_embedded_metadata_case_branch "$rel_path" "emit_profile_command_alias_tokens_for_dist"
  done

  cat <<'SCRIPT'
    *)
      return 1
      ;;
  esac
}

SCRIPT
}

emit_embedded_profile_exec_env_defaults_function() {
  local rel_path

  cat <<'SCRIPT'
policy_dist_emit_embedded_profile_exec_env_defaults() {
  case "$1" in
SCRIPT

  for rel_path in "${profile_files[@]}"; do
    emit_embedded_metadata_case_branch "$rel_path" "emit_profile_exec_env_defaults_for_dist"
  done

  cat <<'SCRIPT'
    *)
      return 1
      ;;
  esac
}

SCRIPT
}

emit_preassembled_profile_chunk_function() {
  local function_name="$1"
  local marker="$2"
  shift 2

  cat <<SCRIPT
${function_name}() {
  cat <<'${marker}' >&"\$policy_render_target_fd"
SCRIPT

  emit_profile_chunk_body "$@"

  cat <<SCRIPT
${marker}
}

SCRIPT
}

emit_safehouse_globals() {
  cat <<'SCRIPT'
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd -P)"
safehouse_invocation_path="${BASH_SOURCE[0]}"
SCRIPT

  echo ""
}

emit_inlined_runtime_sources() {
  local project_version="$1"
  local escaped_project_version rel_path source_path

  escaped_project_version="$(escape_for_shell_double_quotes "$project_version")"

  for rel_path in "${lib_source_files[@]}"; do
    source_path="${ROOT_DIR}/bin/lib/${rel_path}"

    if [[ ! -f "$source_path" ]]; then
      echo "Missing library source file from manifest: ${source_path}" >&2
      exit 1
    fi

    if [[ "$rel_path" == "bootstrap/constants.sh" ]]; then
      awk -v embedded_version="$escaped_project_version" -v placeholder="$project_version_placeholder" '
        $0 == "safehouse_project_version_embedded=\"" placeholder "\"" {
          print "safehouse_project_version_embedded=\"" embedded_version "\""
          replaced = 1
          next
        }
        { print }
        END {
          if (replaced != 1) {
            exit 64
          }
        }
      ' "$source_path" || {
        echo "Failed to embed project version into dist bootstrap constants." >&2
        exit 1
      }
    else
      cat "$source_path"
    fi
    echo ""
  done
}

emit_embedded_overrides() {
  local escaped_supported_enable_features

  emit_array_declaration "policy_embedded_optional_integration_features" "${embedded_optional_integration_features[@]}"
  emit_array_declaration "policy_dist_preassembled_fixed_before_home_keys" "${dist_preassembled_fixed_before_home_keys[@]}"
  emit_array_declaration "policy_dist_preassembled_fixed_after_home_keys" "${dist_preassembled_fixed_after_home_keys[@]}"
  emit_array_declaration "policy_dist_preassembled_core_integration_keys" "${dist_preassembled_core_integration_keys[@]}"
  escaped_supported_enable_features="$(escape_for_shell_double_quotes "$embedded_supported_enable_features")"
  printf 'policy_embedded_supported_enable_features="%s"\n\n' "$escaped_supported_enable_features"
  emit_embedded_profile_requirements_function
  emit_embedded_profile_command_aliases_function
  emit_embedded_profile_exec_env_defaults_function
  emit_preassembled_profile_chunk_function \
    "policy_dist_append_preassembled_fixed_before_home" \
    "__SAFEHOUSE_PREASSEMBLED_FIXED_BEFORE_HOME__" \
    "${dist_preassembled_fixed_before_home_keys[@]}"
  emit_preassembled_profile_chunk_function \
    "policy_dist_append_preassembled_fixed_after_home" \
    "__SAFEHOUSE_PREASSEMBLED_FIXED_AFTER_HOME__" \
    "${dist_preassembled_fixed_after_home_keys[@]}"
  emit_preassembled_profile_chunk_function \
    "policy_dist_append_preassembled_core_integrations" \
    "__SAFEHOUSE_PREASSEMBLED_CORE_INTEGRATIONS__" \
    "${dist_preassembled_core_integration_keys[@]}"

  cat <<'SCRIPT'
policy_source_normalize_profile_key() {
  local source="$1"

  if [[ "$source" == profiles/* ]]; then
    printf '%s\n' "$source"
    return 0
  fi

  if [[ -n "${PROFILES_DIR:-}" && "$source" == "${PROFILES_DIR}/"* ]]; then
    printf 'profiles/%s\n' "${source#"${PROFILES_DIR}/"}"
    return 0
  fi

  printf '%s\n' "$source"
}

policy_source_collect_sorted_profile_keys_in_dir() {
  local target_array_name="$1"
  local base_dir="$2"
  local profile_key_prefix=""
  local key

  safehouse_array_clear "$target_array_name"

  case "$base_dir" in
    "${PROFILES_DIR}/30-toolchains"|"profiles/30-toolchains")
      profile_key_prefix="profiles/30-toolchains/"
      ;;
    "${PROFILES_DIR}/40-shared"|"profiles/40-shared")
      profile_key_prefix="profiles/40-shared/"
      ;;
    "${PROFILES_DIR}/50-integrations-core"|"profiles/50-integrations-core")
      profile_key_prefix="profiles/50-integrations-core/"
      ;;
    "${PROFILES_DIR}/55-integrations-optional"|"profiles/55-integrations-optional")
      profile_key_prefix="profiles/55-integrations-optional/"
      ;;
    "${PROFILES_DIR}/60-agents"|"profiles/60-agents")
      profile_key_prefix="profiles/60-agents/"
      ;;
    "${PROFILES_DIR}/65-apps"|"profiles/65-apps")
      profile_key_prefix="profiles/65-apps/"
      ;;
    *)
      return 0
      ;;
  esac

  for key in "${PROFILE_KEYS[@]}"; do
    [[ "$key" == "${profile_key_prefix}"* ]] || continue
    safehouse_array_append "$target_array_name" "$key"
  done
}

policy_source_read_profile_content() {
  local profile_key="$1"
  local normalized_key profile_path

  normalized_key="$(policy_source_normalize_profile_key "$profile_key")"
  if [[ "$normalized_key" == profiles/* ]]; then
    if embedded_profile_body "$normalized_key"; then
      return 0
    fi
  fi

  profile_path="$profile_key"
  if [[ "$normalized_key" == "$profile_key" && "$profile_key" == profiles/* ]]; then
    profile_path="${ROOT_DIR}/${profile_key}"
  fi

  [[ -f "$profile_path" ]] || return 1
  cat "$profile_path"
}

policy_dist_emit_profile_requirement_tokens_from_content() {
  local profile_key="$1"
  local line raw_requirements

  while IFS= read -r line || [[ -n "$line" ]]; do
    raw_requirements="$(policy_metadata_extract_requirement_csv_from_line "$line")"
    [[ -n "$raw_requirements" ]] || continue
    policy_metadata_emit_requirement_tokens_from_csv "$raw_requirements"
  done < <(policy_source_read_profile_content "$profile_key")
}

policy_dist_emit_profile_command_alias_tokens_from_content() {
  local profile_key="$1"
  local line raw_command_aliases
  local found_metadata=0

  while IFS= read -r line || [[ -n "$line" ]]; do
    raw_command_aliases="$(policy_metadata_extract_command_alias_csv_from_line "$line")"
    [[ -n "$raw_command_aliases" ]] || continue
    found_metadata=1
    policy_metadata_emit_command_alias_tokens_from_csv "$raw_command_aliases"
  done < <(policy_source_read_profile_content "$profile_key")

  if [[ "$found_metadata" -eq 0 ]]; then
    policy_metadata_default_command_alias_from_profile_key "$profile_key"
  fi
}

policy_dist_emit_profile_exec_env_defaults_from_content() {
  local profile_key="$1"
  local line raw_entry normalized_entry

  while IFS= read -r line || [[ -n "$line" ]]; do
    raw_entry="$(policy_metadata_extract_exec_env_default_entry_from_line "$line")"
    [[ -n "$raw_entry" ]] || continue
    normalized_entry="$(policy_metadata_normalize_exec_env_default_entry "$raw_entry" "$profile_key")" || return 1
    printf '%s\n' "$normalized_entry"
  done < <(policy_source_read_profile_content "$profile_key")
}

policy_metadata_emit_profile_requirement_tokens() {
  local profile_key="$1"
  local normalized_key

  normalized_key="$(policy_source_normalize_profile_key "$profile_key")"
  if policy_dist_emit_embedded_profile_requirement_tokens "$normalized_key"; then
    return 0
  fi

  policy_dist_emit_profile_requirement_tokens_from_content "$profile_key"
}

policy_metadata_emit_profile_command_alias_tokens() {
  local profile_key="$1"
  local normalized_key

  normalized_key="$(policy_source_normalize_profile_key "$profile_key")"
  if policy_dist_emit_embedded_profile_command_alias_tokens "$normalized_key"; then
    return 0
  fi

  policy_dist_emit_profile_command_alias_tokens_from_content "$profile_key"
}

policy_metadata_emit_profile_exec_env_defaults() {
  local profile_key="$1"
  local normalized_key

  normalized_key="$(policy_source_normalize_profile_key "$profile_key")"
  if policy_dist_emit_embedded_profile_exec_env_defaults "$normalized_key"; then
    return 0
  fi

  policy_dist_emit_profile_exec_env_defaults_from_content "$profile_key"
}

policy_selection_validate_agent_command_alias_catalog() {
  return 0
}

policy_render_emit_fixed_sections() {
  policy_render_append_resolved_base_profile "profiles/00-base.sb" || return 1
  policy_dist_append_preassembled_fixed_before_home || return 1
  policy_render_emit_resolved_builtin_path_rules_for_profiles "file-read*" "file-write*" "${policy_dist_preassembled_fixed_before_home_keys[@]}" || return 1
  policy_render_emit_home_ancestor_metadata_access || return 1
  policy_dist_append_preassembled_fixed_after_home || return 1
  policy_render_emit_resolved_builtin_path_rules_for_profiles "file-read*" "file-write*" "${policy_dist_preassembled_fixed_after_home_keys[@]}" || return 1
}

policy_render_emit_integration_sections() {
  policy_render_emit_integration_preamble
  policy_dist_append_preassembled_core_integrations || return 1
  policy_render_emit_resolved_builtin_path_rules_for_profiles "file-read*" "file-write*" "${policy_dist_preassembled_core_integration_keys[@]}" || return 1
  policy_render_append_profile "profiles/50-integrations-core/worktree-common-dir.sb" || return 1
  policy_render_append_profile "profiles/50-integrations-core/worktrees.sb" || return 1
  policy_render_append_optional_profiles || return 1
}

SCRIPT
}

emit_dist_script_body() {
  local embedded_profiles_last_modified_utc="$1"
  local project_version="$2"

  emit_banner "$embedded_profiles_last_modified_utc"
  emit_array_declaration "PROFILE_KEYS" "${profile_files[@]}"
  emit_embedded_profiles_function
  emit_safehouse_globals "$project_version"
  emit_inlined_runtime_sources "$project_version"
  emit_embedded_overrides
}

emit_self_update_validation_marker() {
  cat <<'SCRIPT'
# Self-update validation marker: generated standalone safehouse release asset.
# SAFEHOUSE_SELF_UPDATE_VALIDATION_MARKER=standalone-release-asset-v1
SCRIPT
}

write_dist_script() {
  local target_path="$1"
  local embedded_profiles_last_modified_utc="$2"
  local project_version="$3"
  local tmp_output

  mkdir -p "$(dirname "$target_path")"
  tmp_output="$(mktemp "${target_path}.XXXXXX")"

  {
    emit_dist_script_body "$embedded_profiles_last_modified_utc" "$project_version"
    echo 'safehouse_main "$@"'
    emit_self_update_validation_marker
  } >"$tmp_output"

  chmod 0755 "$tmp_output"
  mv "$tmp_output" "$target_path"
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

collect_profiles
collect_lib_sources
validate_profiles
collect_embedded_feature_catalog
collect_dist_preassembled_render_chunks
validate_embedded_agent_command_alias_catalog

project_version="$(read_project_version)"
embedded_profiles_last_modified_utc="$(resolve_embedded_profiles_last_modified_utc)"

write_dist_script "$output_path" "$embedded_profiles_last_modified_utc" "$project_version"
cleanup_committed_obsolete_dist_artifacts

printf '%s\n' "$output_path"
