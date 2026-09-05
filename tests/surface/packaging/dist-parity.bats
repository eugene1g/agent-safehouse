#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "compiled command selection matches source for every alias and app context without metadata reads" {
  local runtime_library
  runtime_library="$(sft_workspace_path "dist-library.sh")"
  sed '/^safehouse_main "\$@"$/d' "$DIST_SAFEHOUSE" > "$runtime_library"

  run /bin/bash -eu -c '
    source "$1"
    compiled_function="$(declare -f policy_selection_select_matching_command)"
    eval "${compiled_function/policy_selection_select_matching_command/compiled_select_command}"
    source "$2/bin/lib/policy/selection.sh"
    policy_selection_load_profile_catalog
    aliases=("" unrecognized-command)
    for key in "${policy_selection_agent_profile_keys[@]}"; do
      while IFS= read -r alias; do
        aliases+=("$alias")
      done < <(policy_metadata_emit_profile_command_alias_tokens "$key")
    done
    for alias in "${aliases[@]}"; do
      for app in "" claude.app codex.app cursor.app chatgpt.app; do
        expected="$(
          policy_selection_select_matching_command "$alias" "$app"
          declare -p policy_selection_selected_scoped_profile_keys policy_selection_selected_scoped_profile_reasons
        )"
        actual="$(
          policy_metadata_emit_profile_command_alias_tokens() { echo unexpected-metadata-read >&2; return 1; }
          compiled_select_command "$alias" "$app"
          declare -p policy_selection_selected_scoped_profile_keys policy_selection_selected_scoped_profile_reasons
        )"
        [[ "$actual" == "$expected" ]] || { printf "Selection differs: %s / %s\n" "$alias" "$app"; exit 1; }
      done
    done
  ' _ "$runtime_library" "$SAFEHOUSE_REPO_ROOT"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "[POLICY-ONLY] bin and dist default policy output match byte-for-byte" {
  local bin_policy dist_policy

  bin_policy="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --stdout)"
  dist_policy="$(safehouse_profile)"

  [ "$bin_policy" = "$dist_policy" ]
}

@test "[POLICY-ONLY] bin and dist command-scoped policies match for alias-driven and app-hosted commands" {
  local fake_copilot_bin fake_claude_app_bin fake_codex_app_bin fake_cursor_app_bin
  local bin_copilot dist_copilot bin_claude_app dist_claude_app bin_codex_app dist_codex_app
  local bin_cursor_app dist_cursor_app

  fake_copilot_bin="$(sft_workspace_path "copilot")"
  fake_claude_app_bin="$(sft_workspace_path "Claude.app/Contents/MacOS/Claude")"
  fake_codex_app_bin="$(sft_workspace_path "Codex.app/Contents/MacOS/codex")"
  fake_cursor_app_bin="$(sft_workspace_path "Cursor.app/Contents/MacOS/Cursor")"
  sft_make_fake_command "$fake_copilot_bin"
  sft_make_fake_command "$fake_claude_app_bin"
  sft_make_fake_command "$fake_codex_app_bin"
  sft_make_fake_command "$fake_cursor_app_bin"

  bin_copilot="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --stdout -- "$fake_copilot_bin")"
  dist_copilot="$(safehouse_profile -- "$fake_copilot_bin")"
  [ "$bin_copilot" = "$dist_copilot" ]
  sft_assert_includes_source "$dist_copilot" "60-agents/copilot-cli.sb"
  sft_assert_includes_source "$dist_copilot" "55-integrations-optional/keychain.sb"

  bin_claude_app="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --stdout -- "$fake_claude_app_bin")"
  dist_claude_app="$(safehouse_profile -- "$fake_claude_app_bin")"
  [ "$bin_claude_app" = "$dist_claude_app" ]
  sft_assert_includes_source "$dist_claude_app" "65-apps/claude-app.sb"
  sft_assert_includes_source "$dist_claude_app" "60-agents/claude-code.sb"

  bin_codex_app="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --stdout -- "$fake_codex_app_bin")"
  dist_codex_app="$(safehouse_profile -- "$fake_codex_app_bin")"
  [ "$bin_codex_app" = "$dist_codex_app" ]
  sft_assert_includes_source "$dist_codex_app" "65-apps/codex-app.sb"
  sft_assert_includes_source "$dist_codex_app" "55-integrations-optional/electron.sb"
  sft_assert_includes_source "$dist_codex_app" "55-integrations-optional/keychain.sb"
  sft_assert_omits_source "$dist_codex_app" "60-agents/codex.sb"

  bin_cursor_app="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --stdout -- "$fake_cursor_app_bin")"
  dist_cursor_app="$(safehouse_profile -- "$fake_cursor_app_bin")"
  [ "$bin_cursor_app" = "$dist_cursor_app" ]
  sft_assert_includes_source "$dist_cursor_app" "65-apps/cursor-app.sb"
  sft_assert_includes_source "$dist_cursor_app" "55-integrations-optional/electron.sb"
  sft_assert_includes_source "$dist_cursor_app" "55-integrations-optional/keychain.sb"
  sft_assert_omits_source "$dist_cursor_app" "60-agents/cursor-agent.sb"
}

@test "[EXECUTION] bin and dist apply playwright-chrome exec env defaults identically" {
  local bin_value dist_value

  bin_value="$("${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --enable=playwright-chrome -- /bin/sh -c 'printf "%s" "${PLAYWRIGHT_MCP_SANDBOX:-}"')"
  dist_value="$(safehouse_ok --enable=playwright-chrome -- /bin/sh -c 'printf "%s" "${PLAYWRIGHT_MCP_SANDBOX:-}"')"

  [ "$bin_value" = "$dist_value" ]
  [ "$dist_value" = "false" ]
}

@test "compiled path candidates match the parser for every profile and avoid runtime profile reads" {
  local runtime_library
  runtime_library="$(sft_workspace_path "dist-library.sh")"
  sed '/^safehouse_main "\$@"$/d' "$DIST_SAFEHOUSE" > "$runtime_library"

  run /bin/bash -eu -c '
    source "$1"
    for key in "${PROFILE_KEYS[@]}"; do
      parsed=()
      compiled=()
      policy_metadata_collect_profile_absolute_path_rules_from_source parsed "$key" "file-read*" "file-write*"
      policy_metadata_collect_profile_absolute_path_rules compiled "$key" "file-read*" "file-write*"
      [[ "${#parsed[@]}" -eq "${#compiled[@]}" ]] || exit 1
      for idx in "${!parsed[@]}"; do
        [[ "${parsed[$idx]}" == "${compiled[$idx]}" ]] || exit 1
      done
    done
    # Neither empty nor nonempty compiled entries may read/reparse profile text.
    policy_source_read_profile_content() { echo unexpected-profile-read >&2; return 1; }
    policy_metadata_list_absolute_path_rules_for_operation() { echo unexpected-parse >&2; return 1; }
    for key in "${PROFILE_KEYS[@]}"; do
      policy_metadata_collect_profile_absolute_path_rules compiled "$key" "file-read*" "file-write*"
    done
  ' _ "$runtime_library"

  [ "$status" -eq 0 ]
  [ -z "$output" ]
}

@test "compiled path metadata falls back for other operations and external profiles" {
  local runtime_library external_profile
  runtime_library="$(sft_workspace_path "dist-library.sh")"
  external_profile="$(sft_workspace_path "external.sb")"
  sed '/^safehouse_main "\$@"$/d' "$DIST_SAFEHOUSE" > "$runtime_library"
  cat > "$external_profile" <<'SB'
(allow file-read*
    (literal "/external-read")
)
(allow file-read* file-write*
    (subpath "/external-write")
)
(deny file-read*
    (subpath "/external-deny")
)
SB

  run /bin/bash -eu -c '
    source "$1"
    compiled=()
    policy_metadata_collect_profile_absolute_path_rules compiled "$2" "file-read*" "file-write*"
    [[ "${#compiled[@]}" -eq 1 && "${compiled[0]}" == "literal|/external-read" ]]
    policy_metadata_collect_profile_absolute_path_rules compiled "$2" "file-read*" ""
    [[ "${#compiled[@]}" -eq 2 && "${compiled[1]}" == "subpath|/external-write" ]]
    key=profiles/30-toolchains/node.sb
    parsed=()
    policy_metadata_collect_profile_absolute_path_rules_from_source parsed "$key" "file-read*" ""
    policy_metadata_collect_profile_absolute_path_rules compiled "$key" "file-read*" ""
    [[ "${#parsed[@]}" -gt 0 && "${#parsed[@]}" -eq "${#compiled[@]}" ]]
    for idx in "${!parsed[@]}"; do
      [[ "${parsed[$idx]}" == "${compiled[$idx]}" ]]
    done
  ' _ "$runtime_library" "$external_profile"

  [ "$status" -eq 0 ]
}
