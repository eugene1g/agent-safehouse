# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# Purpose: Render the finalized policy plan into an SBPL file.
# Reads globals: policy_req_* request state and policy_plan_* render inputs.
# Writes globals: policy_render_* output state.
# Called by: commands/policy.sh after policy_plan_build().
# Notes: Render order is security-sensitive. Keep policy_render_to_path() phase order exact.

policy_render_output_path=""
policy_render_keep_output_path=0
policy_render_target_path=""
policy_render_target_fd=""

policy_render_close_target_fd() {
  if [[ -n "${policy_render_target_fd:-}" ]]; then
    # Do not redirect shell stderr here: `exec` is a shell builtin, so `2>/dev/null`
    # would permanently discard later stderr from wrapped commands.
    exec 9>&- || true
    policy_render_target_fd=""
  fi
}

policy_render_write_line() {
  printf '%s\n' "$1" >&"$policy_render_target_fd"
}

policy_render_write_blank() {
  printf '\n' >&"$policy_render_target_fd"
}

policy_render_append_profile() {
  local profile_key="$1"
  local content

  if [[ "$profile_key" == "profiles/50-integrations-core/worktree-common-dir.sb" ]]; then
    policy_render_append_resolved_worktree_common_dir_profile "$profile_key" || return 1
    return 0
  fi

  if [[ "$profile_key" == "profiles/50-integrations-core/worktrees.sb" ]]; then
    policy_render_append_resolved_worktrees_profile "$profile_key" || return 1
    return 0
  fi

  content="$(policy_source_read_profile_content "$profile_key")" || return 1
  printf '%s\n\n' "$content" >&"$policy_render_target_fd"
  policy_render_emit_resolved_builtin_path_rules "$profile_key" "$content" "file-read*" "file-write*" || return 1
}

policy_render_list_profile_absolute_path_rules_for_operation() {
  local content="$1"
  local operation="$2"
  local excluded_operation="${3:-}"
  local line in_matching_block=0 matcher path allow_prefix

  allow_prefix="(allow ${operation}"

  while IFS= read -r line || [[ -n "$line" ]]; do
    if [[ "$in_matching_block" -eq 0 ]]; then
      if [[ "$line" =~ ^[[:space:]]*\(allow[[:space:]]+ ]] && [[ "$line" == *"$allow_prefix"* ]] && [[ -z "$excluded_operation" || "$line" != *"$excluded_operation"* ]]; then
        in_matching_block=1
      fi
      continue
    fi

    if [[ "$line" =~ ^[[:space:]]*\) ]]; then
      in_matching_block=0
      continue
    fi

    if [[ "$line" =~ \((literal|subpath)[[:space:]]+\"(/[^\"]*)\"\) ]]; then
      matcher="${BASH_REMATCH[1]}"
      path="${BASH_REMATCH[2]}"
      printf '%s|%s\n' "$matcher" "$path"
    fi
  done <<< "$content"
}

policy_render_should_skip_resolved_builtin_path() {
  local profile_key="$1"
  local path="$2"

  [[ "$profile_key" == "profiles/10-system-runtime.sb" ]] || return 1

  case "$path" in
    /private/var/select/developer_dir|/var/select/developer_dir|/private/var/db/xcode_select_link|/var/db/xcode_select_link)
      # These are host-selection pointers, not compatibility aliases like /etc -> /private/etc.
      # Resolving them at render time would make the default policy silently inherit whatever
      # developer root xcode-select currently targets. On CI hosts that can redirect the sandbox
      # from CLT into a full versioned Xcode bundle. Keep that wider Xcode surface explicit in
      # the xcode/lldb integrations instead of auto-following these selector symlinks here.
      return 0
      ;;
  esac

  return 1
}

policy_render_resolve_builtin_absolute_path() {
  local path="$1"
  local resolved_path=""

  [[ "$path" == /* ]] || return 1
  [[ -e "$path" ]] || return 1

  resolved_path="$(safehouse_normalize_abs_path "$path" 2>/dev/null)" || return 1
  [[ "$resolved_path" != "$path" ]] || return 1

  printf '%s\n' "$resolved_path"
}

policy_render_emit_resolved_builtin_path_rule() {
  local profile_key="$1"
  local matcher="$2"
  local original_path="$3"
  local resolved_path="$4"
  local operation="$5"
  local escaped_resolved_path

  policy_render_write_line ";; #safehouse-test-id:resolved-built-in-path# Resolved target for built-in ${operation} path from ${profile_key}: ${original_path} -> ${resolved_path}"
  policy_render_emit_path_ancestor_literals "$resolved_path" "resolved built-in ${operation} path" || return 1
  escaped_resolved_path="$(safehouse_escape_for_sb "$resolved_path")" || return 1
  policy_render_write_line "(allow ${operation} (${matcher} \"${escaped_resolved_path}\"))"
  policy_render_write_blank
}

policy_render_emit_resolved_builtin_path_rules() {
  local profile_key="$1"
  local content="$2"
  local operation="$3"
  local excluded_operation="${4:-}"
  local entry matcher path resolved_path resolved_key
  local -a candidate_entries=()
  local -a existing_rule_keys=()
  local -a emitted_rule_keys=()

  [[ "$profile_key" == profiles/* ]] || return 0

  while IFS= read -r entry || [[ -n "$entry" ]]; do
    candidate_entries+=("$entry")
  done < <(policy_render_list_profile_absolute_path_rules_for_operation "$content" "$operation" "$excluded_operation")

  if [[ "${#candidate_entries[@]}" -eq 0 ]]; then
    return 0
  fi

  for entry in "${candidate_entries[@]}"; do
    matcher="${entry%%|*}"
    path="${entry#*|}"
    safehouse_array_append_unique existing_rule_keys "${matcher}:${path}"
  done

  for entry in "${candidate_entries[@]}"; do
    matcher="${entry%%|*}"
    path="${entry#*|}"
    if policy_render_should_skip_resolved_builtin_path "$profile_key" "$path"; then
      continue
    fi
    resolved_path="$(policy_render_resolve_builtin_absolute_path "$path" || true)"
    [[ -n "$resolved_path" ]] || continue

    resolved_key="${matcher}:${resolved_path}"
    if [[ "${#existing_rule_keys[@]}" -gt 0 ]] && safehouse_array_contains_exact "$resolved_key" "${existing_rule_keys[@]}"; then
      continue
    fi
    if [[ "${#emitted_rule_keys[@]}" -gt 0 ]] && safehouse_array_contains_exact "$resolved_key" "${emitted_rule_keys[@]}"; then
      continue
    fi

    policy_render_emit_resolved_builtin_path_rule "$profile_key" "$matcher" "$path" "$resolved_path" "$operation" || return 1
    emitted_rule_keys+=("$resolved_key")
  done
}

policy_render_emit_resolved_builtin_path_rules_for_profiles() {
  local operation="$1"
  local excluded_operation=""
  if [[ "${2:-}" == profiles/* || -z "${2:-}" ]]; then
    shift
  else
    excluded_operation="$2"
    shift 2
  fi
  local profile_key content

  for profile_key in "$@"; do
    content="$(policy_source_read_profile_content "$profile_key")" || return 1
    policy_render_emit_resolved_builtin_path_rules "$profile_key" "$content" "$operation" "$excluded_operation" || return 1
  done
}

policy_render_emit_policy_origin_preamble() {
  policy_render_write_line ";; ---------------------------------------------------------------------------"
  policy_render_write_line ";; ${safehouse_project_name} Policy (generated file)"
  policy_render_write_line ";; Project: ${safehouse_project_url}"
  policy_render_write_line ";; GitHub: ${safehouse_project_github_url}"
  policy_render_write_line ";; Contribute: ${safehouse_project_github_url}"
  policy_render_write_line ";;"
  policy_render_write_line ";; Debug sandbox denials (examples):"
  policy_render_write_line ";;   /usr/bin/log stream --style compact --predicate 'eventMessage CONTAINS \"Sandbox:\" AND eventMessage CONTAINS \"deny(\"'"
  policy_render_write_line ";;   /usr/bin/log stream --style compact --info --debug --predicate '(processID == 0) AND (senderImagePath CONTAINS \"/Sandbox\")'"
  policy_render_write_line ";; ---------------------------------------------------------------------------"
  policy_render_write_blank
}

policy_render_append_resolved_base_profile() {
  local profile_key="$1"
  local escaped_home resolved_base first_line remaining_lines

  escaped_home="$(safehouse_escape_for_sb "$policy_req_home_dir")" || return 1
  resolved_base="$(policy_source_read_profile_content "$profile_key" | safehouse_replace_literal_stream_required "$HOME_DIR_TEMPLATE_TOKEN" "$escaped_home")" || {
    safehouse_fail \
      "Failed to resolve HOME_DIR placeholder in base profile: ${profile_key}" \
      "Expected HOME_DIR placeholder token: ${HOME_DIR_TEMPLATE_TOKEN}"
    return 1
  }

  first_line="${resolved_base%%$'\n'*}"
  if [[ "$resolved_base" == *$'\n'* ]]; then
    remaining_lines="${resolved_base#*$'\n'}"
  else
    remaining_lines=""
  fi

  policy_render_write_line "$first_line"
  policy_render_write_blank
  policy_render_emit_policy_origin_preamble
  printf '%s\n\n' "$remaining_lines" >&"$policy_render_target_fd"
}

policy_render_append_unscoped_module_dir() {
  local base_dir="$1"
  local profile_key
  local -a profile_keys=()

  policy_source_collect_sorted_profile_keys_in_dir profile_keys "$base_dir"
  if [[ "${#profile_keys[@]}" -eq 0 ]]; then
    safehouse_fail "No module profiles found in: ${base_dir}"
    return 1
  fi

  for profile_key in "${profile_keys[@]}"; do
    policy_render_append_profile "$profile_key" || return 1
  done
}

policy_render_append_scoped_module_dir() {
  local base_dir="$1"
  local profile_key appended_any=0
  local -a profile_keys=()

  policy_source_collect_sorted_profile_keys_in_dir profile_keys "$base_dir"
  if [[ "${#profile_keys[@]}" -eq 0 ]]; then
    safehouse_fail "No module profiles found in: ${base_dir}"
    return 1
  fi

  for profile_key in "${profile_keys[@]}"; do
    policy_plan_should_include_scoped_profile_key "$profile_key" || continue
    policy_render_append_profile "$profile_key" || return 1
    appended_any=1
  done

  if [[ "$base_dir" == "profiles/60-agents" && "$appended_any" -eq 0 && "$policy_req_enable_all_agents" -ne 1 ]]; then
    if [[ "${#policy_plan_scoped_profile_keys[@]}" -eq 0 ]]; then
      policy_render_write_line ";; No command-matched app/agent profile selected; skipping 60-agents and 65-apps modules."
      policy_render_write_line ";; Use --enable=all-agents,all-apps to restore legacy all-profile behavior."
      policy_render_write_blank
    fi
  fi
}

policy_render_emit_integration_preamble() {
  local keychain_status="not included"

  if [[ "$policy_plan_keychain_included" -eq 1 ]]; then
    keychain_status="included"
  fi

  if [[ "${#policy_plan_optional_integrations_explicit_included[@]}" -gt 0 ]]; then
    policy_render_write_line ";; Optional integrations explicitly enabled: $(safehouse_join_by_space "${policy_plan_optional_integrations_explicit_included[@]}")"
  else
    policy_render_write_line ";; Optional integrations explicitly enabled: $(safehouse_join_by_space)"
  fi
  if [[ "${#policy_plan_optional_integrations_implicit_included[@]}" -gt 0 ]]; then
    policy_render_write_line ";; Optional integrations implicitly injected: $(safehouse_join_by_space "${policy_plan_optional_integrations_implicit_included[@]}")"
  else
    policy_render_write_line ";; Optional integrations implicitly injected: $(safehouse_join_by_space)"
  fi
  if [[ "${#policy_plan_optional_integrations_not_included[@]}" -gt 0 ]]; then
    policy_render_write_line ";; Optional integrations not included: $(safehouse_join_by_space "${policy_plan_optional_integrations_not_included[@]}")"
  else
    policy_render_write_line ";; Optional integrations not included: $(safehouse_join_by_space)"
  fi
  policy_render_write_line ";; Keychain integration (auto-injected from profile requirements): ${keychain_status}"
  policy_render_write_line ";; Use --enable=<feature> (comma-separated) to include optional integrations explicitly."
  policy_render_write_line ";; Note: selected profiles and enabled optional integrations can inject dependencies via \$\$require=<profile-path>\$\$ metadata."
  policy_render_write_line ";; Threat-model note: blocking exfiltration/C2 is explicitly NOT a goal for this sandbox."
  policy_render_write_blank
}

policy_render_append_optional_profiles() {
  local profile_key
  local -a optional_profile_keys=()

  policy_source_collect_sorted_profile_keys_in_dir optional_profile_keys "profiles/55-integrations-optional"
  if [[ "${#optional_profile_keys[@]}" -eq 0 ]]; then
    safehouse_fail "No optional integration profiles found in: profiles/55-integrations-optional"
    return 1
  fi

  for profile_key in "${optional_profile_keys[@]}"; do
    policy_plan_optional_profile_selected "$profile_key" || continue
    policy_render_append_profile "$profile_key" || return 1
  done
}

policy_render_build_path_ancestor_literals_block() {
  local path="$1"
  local label="$2"
  local chunk trimmed_path current_path path_part escaped_current_path
  local IFS='/'
  local -a path_parts=()

  chunk=";; Generated ancestor directory literals for ${label}: ${path}"
  chunk+=$'\n;;'
  chunk+=$'\n;; Why file-read* (not file-read-metadata) with literal (not subpath):'
  chunk+=$'\n;; Agents (notably Claude Code) call readdir() on every ancestor of the working'
  chunk+=$'\n;; directory during startup. If only file-read-metadata (stat) is granted, the'
  chunk+=$'\n;; agent cannot list directory contents, which causes it to blank PATH and break.'
  chunk+=$'\n;; Using '\''literal'\'' (not '\''subpath'\'') keeps this safe: it grants read access to the'
  chunk+=$'\n;; directory entry itself (i.e. listing its immediate children), but does NOT'
  chunk+=$'\n;; grant recursive read access to files or subdirectories under it.'
  chunk+=$'\n(allow file-read*'
  chunk+=$'\n    (literal "/")'

  trimmed_path="${path#/}"
  if [[ -n "$trimmed_path" ]]; then
    current_path=""
    read -r -a path_parts <<< "$trimmed_path"
    for path_part in "${path_parts[@]}"; do
      [[ -z "$path_part" ]] && continue
      current_path+="/${path_part}"
      escaped_current_path="$(safehouse_escape_for_sb "$current_path")" || return 1
      chunk+="$(printf '\n    (literal "%s")' "$escaped_current_path")"
    done
  fi

  chunk+=$'\n)\n'
  printf '%s' "$chunk"
}

policy_render_emit_path_ancestor_literals() {
  policy_render_build_path_ancestor_literals_block "$1" "$2" >&"$policy_render_target_fd"
}

policy_render_emit_path_ancestor_metadata_literals() {
  local path="$1"
  local label="$2"
  local chunk trimmed_path current_path path_part escaped_current_path
  local IFS='/'
  local -a path_parts=()

  chunk=";; #safehouse-test-id:home-ancestor-metadata# Metadata-only ancestor directory literals for ${label}: ${path}"
  chunk+=$'\n;;'
  chunk+=$'\n;; Why file-read-metadata on HOME ancestors:'
  chunk+=$'\n;; Some macOS runtimes probe HOME-scoped toolchain paths (for example ~/Library/Java)'
  chunk+=$'\n;; even when the selected workdir lives elsewhere. Without metadata-only access to the'
  chunk+=$'\n;; HOME ancestor chain, those probes fail before the more specific home-subpath/home-literal'
  chunk+=$'\n;; grants can match. Keep this metadata-only to avoid broad read visibility into HOME.'
  chunk+=$'\n(allow file-read-metadata'
  chunk+=$'\n    (literal "/")'

  trimmed_path="${path#/}"
  if [[ -n "$trimmed_path" ]]; then
    current_path=""
    read -r -a path_parts <<< "$trimmed_path"
    for path_part in "${path_parts[@]}"; do
      [[ -z "$path_part" ]] && continue
      current_path+="/${path_part}"
      escaped_current_path="$(safehouse_escape_for_sb "$current_path")" || return 1
      chunk+="$(printf '\n    (literal "%s")' "$escaped_current_path")"
    done
  fi

  chunk+=$'\n)\n'
  printf '%s' "$chunk" >&"$policy_render_target_fd"
}

policy_render_emit_extra_access_rules() {
  local path escaped_path

  if [[ "$policy_plan_readonly_count" -eq 0 && "$policy_plan_rw_count" -eq 0 ]]; then
    return 0
  fi

  policy_render_write_line ";; #safehouse-test-id:dynamic-cli-grants# Additional dynamic path grants from config/env/CLI."
  policy_render_write_line ";; NOTE: appended profile denies (--append-profile) may still block sensitive paths."
  policy_render_write_line ";; Emission order here is: add-dirs-ro sources first, then add-dirs sources."
  policy_render_write_blank

  if [[ "$policy_plan_readonly_count" -gt 0 ]]; then
    for path in "${policy_plan_readonly_paths[@]}"; do
      policy_render_emit_path_ancestor_literals "$path" "extra read-only path" || return 1
      escaped_path="$(safehouse_escape_for_sb "$path")" || return 1
      if [[ -d "$path" ]]; then
        policy_render_write_line "(allow file-read* (subpath \"${escaped_path}\"))"
      else
        policy_render_write_line "(allow file-read* (literal \"${escaped_path}\"))"
      fi
      policy_render_write_blank
    done
  fi

  if [[ "$policy_plan_rw_count" -gt 0 ]]; then
    for path in "${policy_plan_rw_paths[@]}"; do
      policy_render_emit_path_ancestor_literals "$path" "extra read/write path" || return 1
      escaped_path="$(safehouse_escape_for_sb "$path")" || return 1
      if [[ -d "$path" ]]; then
        policy_render_write_line "(allow file-read* file-write* (subpath \"${escaped_path}\"))"
      else
        policy_render_write_line "(allow file-read* file-write* (literal \"${escaped_path}\"))"
      fi
      policy_render_write_blank
    done
  fi
}

policy_render_emit_wide_read_access() {
  if [[ "$policy_req_enable_wide_read" -ne 1 ]]; then
    return 0
  fi

  policy_render_write_line ";; #safehouse-test-id:wide-read# Broad read-only visibility across the full filesystem."
  policy_render_write_line ";; Added by --enable=wide-read. This emits a recursive read grant on /."
  policy_render_write_line ";; WARNING: because this rule is emitted late, it can override earlier deny file-read* rules."
  policy_render_write_line ";; Use --append-profile deny rules if you must keep specific paths unreadable."
  policy_render_write_line "(allow file-read* (subpath \"/\"))"
  policy_render_write_blank
}

policy_render_build_git_worktree_common_dir_rule_block() {
  local path="$1"
  local escaped_path

  if [[ -z "$path" ]]; then
    return 0
  fi

  printf '%s\n' ";; #safehouse-test-id:git-worktree-common-dir-grant# Allow linked git worktrees to read/write shared repository metadata."
  printf '%s\n' ";; Git stores refs/index/worktree bookkeeping under the common dir owned by the main checkout."
  policy_render_build_path_ancestor_literals_block "$path" "git worktree common dir" || return 1
  escaped_path="$(safehouse_escape_for_sb "$path")" || return 1
  printf '(allow file-read* file-write* (subpath "%s"))\n\n' "$escaped_path"
}

policy_render_build_git_linked_worktree_rule_block() {
  local path="$1"
  local escaped_path

  if [[ -z "$path" ]]; then
    return 0
  fi

  printf '%s\n' ";; #safehouse-test-id:git-linked-worktree-grant# Allow read access to linked git worktrees discovered at Safehouse launch."
  printf '%s\n' ";; Keep sibling worktrees read-only by default; the selected workdir retains its own read/write grant."
  printf '%s\n' ";; New worktrees created after launch are not added to this running policy."
  policy_render_build_path_ancestor_literals_block "$path" "linked git worktree" || return 1
  escaped_path="$(safehouse_escape_for_sb "$path")" || return 1
  printf '(allow file-read* (subpath "%s"))\n\n' "$escaped_path"
}

policy_render_build_git_worktree_common_dir_runtime_rules_block() {
  if [[ -n "${policy_req_git_worktree_common_dir:-}" ]]; then
    policy_render_build_git_worktree_common_dir_rule_block "$policy_req_git_worktree_common_dir" || return 1
    return 0
  fi

  printf '%s\n' ";; No external shared git common dir detected for this selected workdir."
}

policy_render_build_git_linked_worktree_runtime_rules_block() {
  local worktree_path

  if [[ "${#policy_req_git_linked_worktree_paths[@]}" -gt 0 ]]; then
    for worktree_path in "${policy_req_git_linked_worktree_paths[@]}"; do
      policy_render_build_git_linked_worktree_rule_block "$worktree_path" || return 1
    done
    return 0
  fi

  printf '%s\n' ";; No linked git worktree snapshot detected for this selected workdir."
}

policy_render_append_resolved_worktree_common_dir_profile() {
  local profile_key="$1"
  local content common_dir_status runtime_rules

  content="$(policy_source_read_profile_content "$profile_key")" || return 1
  if [[ -n "${policy_req_git_worktree_common_dir:-}" ]]; then
    common_dir_status="${policy_req_git_worktree_common_dir}"
  else
    common_dir_status="(none)"
  fi
  runtime_rules="$(policy_render_build_git_worktree_common_dir_runtime_rules_block)" || return 1

  content="$(printf '%s' "$content" | safehouse_replace_literal_stream_required "$WORKTREES_COMMON_DIR_STATUS_TEMPLATE_TOKEN" "$common_dir_status")" || return 1
  printf '%s\n\n' "$content" >&"$policy_render_target_fd"
  printf '%s\n\n' "$runtime_rules" >&"$policy_render_target_fd"
}

policy_render_append_resolved_worktrees_profile() {
  local profile_key="$1"
  local content linked_paths_status runtime_rules

  content="$(policy_source_read_profile_content "$profile_key")" || return 1
  if [[ "${#policy_req_git_linked_worktree_paths[@]}" -gt 0 ]]; then
    linked_paths_status="$(safehouse_join_by_space "${policy_req_git_linked_worktree_paths[@]}")"
  else
    linked_paths_status="$(safehouse_join_by_space)"
  fi
  runtime_rules="$(policy_render_build_git_linked_worktree_runtime_rules_block)" || return 1

  content="$(printf '%s' "$content" | safehouse_replace_literal_stream_required "$WORKTREES_LINKED_PATHS_STATUS_TEMPLATE_TOKEN" "$linked_paths_status")" || return 1
  printf '%s\n\n' "$content" >&"$policy_render_target_fd"
  printf '%s\n\n' "$runtime_rules" >&"$policy_render_target_fd"
}

policy_render_emit_workdir_access() {
  local path="$1"
  local escaped_path

  if [[ -z "$path" ]]; then
    return 0
  fi

  policy_render_write_line ";; #safehouse-test-id:workdir-grant# Allow read/write access to the selected workdir."
  policy_render_emit_path_ancestor_literals "$path" "selected workdir" || return 1
  escaped_path="$(safehouse_escape_for_sb "$path")" || return 1
  if [[ -d "$path" ]]; then
    policy_render_write_line "(allow file-read* file-write* (subpath \"${escaped_path}\"))"
  else
    policy_render_write_line "(allow file-read* file-write* (literal \"${escaped_path}\"))"
  fi
  policy_render_write_blank
}

policy_render_emit_home_ancestor_metadata_access() {
  if [[ -z "${policy_req_home_dir:-}" ]]; then
    return 0
  fi

  policy_render_write_line ";; Generated HOME ancestor metadata access for home-scoped runtime/toolchain discovery."
  policy_render_emit_path_ancestor_metadata_literals "$policy_req_home_dir" "HOME path" || return 1
}

policy_render_append_cli_profiles() {
  local profile_path

  if [[ "$(safehouse_array_length policy_req_append_profile_paths)" -gt 0 ]]; then
    for profile_path in "${policy_req_append_profile_paths[@]}"; do
      policy_render_write_line ";; #safehouse-test-id:append-profile# Appended profile from --append-profile: ${profile_path}"
      policy_render_write_blank
      policy_render_append_profile "$profile_path" || return 1
    done
  fi
}

policy_render_reset_output_state() {
  policy_render_close_target_fd
  policy_render_output_path=""
  policy_render_keep_output_path=0
  policy_render_target_path=""
  policy_render_target_fd=""
}

policy_render_begin_stdout_target() {
  policy_render_reset_output_state
  policy_render_target_path="/dev/stdout"
  # Avoid fd 3 because Bats reserves it when commands run under the test harness.
  exec 9>&1
  policy_render_target_fd="9"
}

policy_render_begin_path_target() {
  local target_path="$1"

  policy_render_target_path="$target_path"
  : >"$policy_render_target_path"
  exec 9>"$policy_render_target_path"
  policy_render_target_fd="9"
}

policy_render_open_output_target() {
  local tmp_output_path tmp_dir

  if [[ -n "$policy_req_output_path" ]]; then
    mkdir -p "$(dirname "$policy_req_output_path")"
    tmp_output_path="$(mktemp "${policy_req_output_path}.XXXXXX")"
  else
    tmp_dir="${TMPDIR:-/tmp}"
    if [[ ! -d "$tmp_dir" ]]; then
      tmp_dir="/tmp"
    fi
    tmp_output_path="$(mktemp "${tmp_dir%/}/agent-sandbox-policy.XXXXXX")"
  fi

  printf '%s\n' "$tmp_output_path"
}

policy_render_emit_fixed_sections() {
  policy_render_append_resolved_base_profile "profiles/00-base.sb" || return 1
  policy_render_append_profile "profiles/10-system-runtime.sb" || return 1
  policy_render_emit_home_ancestor_metadata_access || return 1
  policy_render_append_profile "profiles/20-network.sb" || return 1
  policy_render_append_unscoped_module_dir "profiles/30-toolchains" || return 1
  policy_render_append_unscoped_module_dir "profiles/40-shared" || return 1
}

policy_render_emit_integration_sections() {
  policy_render_emit_integration_preamble
  policy_render_append_unscoped_module_dir "profiles/50-integrations-core" || return 1
  policy_render_append_optional_profiles || return 1
}

policy_render_emit_scoped_sections() {
  policy_render_append_scoped_module_dir "profiles/60-agents" || return 1
  policy_render_append_scoped_module_dir "profiles/65-apps" || return 1
}

policy_render_emit_dynamic_sections() {
  policy_render_emit_extra_access_rules || return 1
  policy_render_emit_wide_read_access
  policy_render_emit_workdir_access "$policy_req_effective_workdir" || return 1
  policy_render_append_cli_profiles || return 1
}

policy_render_emit_all_sections() {
  policy_render_emit_fixed_sections || return 1
  policy_render_emit_integration_sections || return 1
  policy_render_emit_scoped_sections || return 1
  policy_render_emit_dynamic_sections || return 1
}

policy_render_finalize_output_path() {
  local temp_output_path="$1"

  if [[ -n "$policy_req_output_path" ]]; then
    mv "$temp_output_path" "$policy_req_output_path"
    policy_render_output_path="$policy_req_output_path"
    policy_render_keep_output_path=1
    return 0
  fi

  policy_render_output_path="$temp_output_path"
  policy_render_keep_output_path=0
}

policy_render_to_path() {
  local temp_output_path render_status

  policy_render_reset_output_state
  temp_output_path="$(policy_render_open_output_target)" || return 1

  policy_render_begin_path_target "$temp_output_path" || return 1

  if policy_render_emit_all_sections; then
    :
  else
    render_status=$?
    policy_render_reset_output_state
    return "$render_status"
  fi

  policy_render_close_target_fd
  policy_render_finalize_output_path "$temp_output_path" || return 1
}

policy_render_to_stdout() {
  local render_status
  local temp_output_path=""

  # Render to a temporary file first, then stream it with cat. Repeated Bash
  # builtin printf writes to a pipe can intermittently fail with EINTR under
  # high-concurrency command substitutions, while rendering to a file avoids
  # that path and cat handles stdout streaming robustly.
  policy_render_to_path || return 1
  temp_output_path="$policy_render_output_path"

  if cat "$temp_output_path"; then
    :
  else
    render_status=$?
    rm -f "$temp_output_path"
    policy_render_reset_output_state
    return "$render_status"
  fi

  rm -f "$temp_output_path"
  policy_render_reset_output_state
}
