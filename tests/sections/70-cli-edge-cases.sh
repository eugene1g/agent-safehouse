#!/usr/bin/env bash

run_section_cli_edge_cases() {
  local policy_enable_arg policy_enable_csv policy_enable_macos_gui policy_enable_electron policy_enable_all_agents policy_workdir_empty_eq policy_env_grants policy_env_workdir
  local policy_env_workdir_empty policy_env_cli_workdir policy_workdir_config missing_path home_not_dir
  local policy_tilde_flags policy_tilde_config policy_tilde_workdir policy_tilde_append_profile
  local policy_append_profile policy_append_profile_multi append_profile_file append_profile_file_2
  local policy_agent_codex policy_agent_kilo policy_agent_unknown policy_agent_claude_app policy_agent_all_agents
  local output_space output_nested args_file workdir_config_file safehouse_env_policy safehouse_env_status
  local fake_codex_bin fake_unknown_bin fake_claude_app_dir fake_claude_app_bin kilo_cmd
  local append_profile_tilde_file
  local test_ro_dir_rel test_ro_dir_2_rel test_rw_dir_2_rel
  local resolved_test_rw_dir resolved_test_ro_dir
  local marker_dynamic marker_workdir marker_append_profile_one marker_append_profile_two

  marker_dynamic="#safehouse-test-id:dynamic-cli-grants#"
  marker_workdir="#safehouse-test-id:workdir-grant#"
  marker_append_profile_one="#safehouse-test-id:append-profile-one#"
  marker_append_profile_two="#safehouse-test-id:append-profile-two#"
  resolved_test_rw_dir="$(cd "$TEST_RW_DIR" && pwd -P)"
  resolved_test_ro_dir="$(cd "$TEST_RO_DIR" && pwd -P)"
  test_ro_dir_rel="${TEST_RO_DIR#"${HOME}/"}"
  test_ro_dir_2_rel="${TEST_RO_DIR_2#"${HOME}/"}"
  test_rw_dir_2_rel="${TEST_RW_DIR_2#"${HOME}/"}"

  section_begin "Binary Entry Points"
  assert_command_succeeds "bin/safehouse.sh works from /tmp via absolute path (policy mode)" /bin/sh -c "cd /tmp && '${SAFEHOUSE}' >/dev/null"
  assert_command_succeeds "bin/safehouse.sh works from /tmp via absolute path (execute mode)" /bin/sh -c "cd /tmp && '${SAFEHOUSE}' -- /usr/bin/true"
  assert_command_succeeds "bin/safehouse.sh runs wrapped command without requiring --" /bin/sh -c "cd /tmp && '${SAFEHOUSE}' /usr/bin/true"
  assert_command_succeeds "bin/safehouse.sh with no command generates a policy path" /usr/bin/env SAFEHOUSE_BIN="$SAFEHOUSE" /bin/sh -c 'cd /tmp && policy_path="$($SAFEHOUSE_BIN)" && [ -n "$policy_path" ] && [ -f "$policy_path" ] && rm -f "$policy_path"'

  section_begin "Enable Flag Parsing"
  policy_enable_arg="${TEST_CWD}/policy-enable-arg.sb"
  policy_enable_csv="${TEST_CWD}/policy-enable-csv.sb"
  assert_command_succeeds "--enable docker parses as separate argument form" "$GENERATOR" --output "$policy_enable_arg" --enable docker
  assert_policy_contains "$policy_enable_arg" "--enable docker includes docker grants" "/var/run/docker.sock"
  assert_policy_contains "$policy_enable_arg" "--enable docker preserves default browser native messaging grants" "/NativeMessagingHosts"
  assert_command_succeeds "--enable=docker,electron parses CSV with whitespace" "$GENERATOR" --output "$policy_enable_csv" "--enable=docker, electron"
  assert_policy_contains "$policy_enable_csv" "CSV --enable includes docker grants" "/var/run/docker.sock"
  assert_policy_contains "$policy_enable_csv" "CSV --enable includes electron grants" "#safehouse-test-id:electron-integration#"
  assert_policy_contains "$policy_enable_csv" "CSV --enable=electron implies macOS GUI integration" ";; Integration: macOS GUI"
  policy_enable_macos_gui="${TEST_CWD}/policy-enable-macos-gui.sb"
  policy_enable_electron="${TEST_CWD}/policy-enable-electron.sb"
  assert_command_succeeds "--enable macos-gui parses as separate argument form" "$GENERATOR" --output "$policy_enable_macos_gui" --enable macos-gui
  assert_policy_contains "$policy_enable_macos_gui" "--enable macos-gui includes macOS GUI integration profile" ";; Integration: macOS GUI"
  assert_policy_not_contains "$policy_enable_macos_gui" "--enable macos-gui does not include electron integration profile" "#safehouse-test-id:electron-integration#"
  assert_command_succeeds "--enable=electron parses and implies macos-gui" "$GENERATOR" --output "$policy_enable_electron" --enable=electron
  assert_policy_contains "$policy_enable_electron" "--enable=electron includes electron integration profile" "#safehouse-test-id:electron-integration#"
  assert_policy_contains "$policy_enable_electron" "--enable=electron implies macOS GUI integration profile" ";; Integration: macOS GUI"
  policy_enable_all_agents="${TEST_CWD}/policy-enable-all-agents.sb"
  assert_command_succeeds "--enable=all-agents restores full 60-agents module inclusion" "$GENERATOR" --output "$policy_enable_all_agents" --enable=all-agents
  assert_policy_contains "$policy_enable_all_agents" "--enable=all-agents includes Claude Code profile" ";; Source: 60-agents/claude-code.sb"
  assert_policy_contains "$policy_enable_all_agents" "--enable=all-agents includes Codex profile" ";; Source: 60-agents/codex.sb"
  assert_policy_contains "$policy_enable_all_agents" "--enable=all-agents includes Kilo Code profile" ";; Source: 60-agents/kilo-code.sb"

  section_begin "Workdir Flag Parsing"
  policy_workdir_empty_eq="${TEST_CWD}/policy-workdir-empty-equals.sb"
  assert_command_succeeds "--workdir= (empty) is accepted and disables automatic workdir grant" "$GENERATOR" --output "$policy_workdir_empty_eq" --workdir=
  assert_policy_not_contains "$policy_workdir_empty_eq" "--workdir= omits automatic workdir grant marker" "$marker_workdir"

  section_begin "Environment Inputs"
  policy_env_grants="${TEST_CWD}/policy-env-grants.sb"
  policy_env_workdir="${TEST_CWD}/policy-env-workdir.sb"
  policy_env_workdir_empty="${TEST_CWD}/policy-env-workdir-empty.sb"
  policy_env_cli_workdir="${TEST_CWD}/policy-env-cli-workdir.sb"
  assert_command_succeeds "SAFEHOUSE_ADD_DIRS* env vars add dynamic grants" /usr/bin/env SAFEHOUSE_ADD_DIRS_RO="$TEST_RO_DIR" SAFEHOUSE_ADD_DIRS="$TEST_RW_DIR" "$GENERATOR" --output "$policy_env_grants"
  assert_policy_contains "$policy_env_grants" "SAFEHOUSE_ADD_DIRS_RO emits read-only grant" "(subpath \"${resolved_test_ro_dir}\")"
  assert_policy_contains "$policy_env_grants" "SAFEHOUSE_ADD_DIRS emits read/write grant" "file-read* file-write* (subpath \"${resolved_test_rw_dir}\")"
  assert_command_succeeds "SAFEHOUSE_WORKDIR sets workdir when --workdir is omitted" /usr/bin/env SAFEHOUSE_WORKDIR="$TEST_RW_DIR" "$GENERATOR" --output "$policy_env_workdir"
  assert_policy_contains "$policy_env_workdir" "SAFEHOUSE_WORKDIR-selected workdir is granted" "(subpath \"${resolved_test_rw_dir}\")"
  assert_command_succeeds "SAFEHOUSE_WORKDIR empty string disables automatic workdir grants" /usr/bin/env SAFEHOUSE_WORKDIR="" "$GENERATOR" --output "$policy_env_workdir_empty"
  assert_policy_not_contains "$policy_env_workdir_empty" "SAFEHOUSE_WORKDIR= omits automatic workdir marker" "$marker_workdir"
  assert_command_succeeds "CLI --workdir overrides SAFEHOUSE_WORKDIR" /usr/bin/env SAFEHOUSE_WORKDIR="$TEST_DENIED_DIR" "$GENERATOR" --output "$policy_env_cli_workdir" --workdir "$TEST_RW_DIR"
  assert_policy_contains "$policy_env_cli_workdir" "CLI --workdir wins over SAFEHOUSE_WORKDIR for selected path" "(subpath \"${resolved_test_rw_dir}\")"
  assert_policy_not_contains "$policy_env_cli_workdir" "SAFEHOUSE_WORKDIR path is ignored when CLI --workdir is present" "(subpath \"${TEST_DENIED_DIR}\")"

  set +e
  safehouse_env_policy="$(/usr/bin/env SAFEHOUSE_WORKDIR="" "$SAFEHOUSE" 2>/dev/null)"
  safehouse_env_status=$?
  set -e
  if [[ "$safehouse_env_status" -eq 0 && -n "$safehouse_env_policy" && -f "$safehouse_env_policy" ]]; then
    log_pass "safehouse honors SAFEHOUSE_WORKDIR for policy generation"
    assert_policy_not_contains "$safehouse_env_policy" "safehouse+SAFEHOUSE_WORKDIR= omits automatic workdir marker" "$marker_workdir"
  else
    log_fail "safehouse honors SAFEHOUSE_WORKDIR for policy generation"
  fi
  if [[ -n "$safehouse_env_policy" ]]; then
    rm -f "$safehouse_env_policy"
  fi

  section_begin "Workdir Config File"
  policy_workdir_config="${TEST_CWD}/policy-workdir-config.sb"
  workdir_config_file="${TEST_CWD}/.safehouse"
  cat > "$workdir_config_file" <<EOF
# SAFEHOUSE config loaded from selected workdir
add-dirs-ro=${TEST_RO_DIR_2}
add-dirs=${TEST_RW_DIR_2}
EOF
  assert_command_succeeds "workdir config file adds --add-dirs-ro/--add-dirs equivalents" /bin/sh -c "cd '${TEST_CWD}' && '${GENERATOR}' --output '${policy_workdir_config}'"
  assert_policy_contains "$policy_workdir_config" "workdir config file emits read-only grant" "(subpath \"${TEST_RO_DIR_2}\")"
  assert_policy_contains "$policy_workdir_config" "workdir config file emits read/write grant" "file-read* file-write* (subpath \"${TEST_RW_DIR_2}\")"
  rm -f "$workdir_config_file"

  section_begin "Tilde Path Expansion"
  policy_tilde_flags="${TEST_CWD}/policy-tilde-flags.sb"
  policy_tilde_config="${TEST_CWD}/policy-tilde-config.sb"
  policy_tilde_workdir="${TEST_CWD}/policy-tilde-workdir.sb"
  policy_tilde_append_profile="${TEST_CWD}/policy-tilde-append-profile.sb"
  append_profile_tilde_file="${HOME}/.safehouse-append-tilde-$$.sb"

  assert_command_succeeds "--add-dirs flags expand ~ and ~/... values" "$GENERATOR" --output "$policy_tilde_flags" --add-dirs-ro="~/${test_ro_dir_rel}" --add-dirs="~/${test_rw_dir_2_rel}"
  assert_policy_contains "$policy_tilde_flags" "--add-dirs-ro with ~ expands to HOME path" "(subpath \"${TEST_RO_DIR}\")"
  assert_policy_contains "$policy_tilde_flags" "--add-dirs with ~ expands to HOME path" "file-read* file-write* (subpath \"${TEST_RW_DIR_2}\")"

  cat > "$workdir_config_file" <<EOF
add-dirs-ro=~/${test_ro_dir_2_rel}
add-dirs=~/${test_rw_dir_2_rel}
EOF
  assert_command_succeeds "workdir config add-dirs values expand ~ and ~/..." /bin/sh -c "cd '${TEST_CWD}' && '${GENERATOR}' --output '${policy_tilde_config}'"
  assert_policy_contains "$policy_tilde_config" "workdir config add-dirs-ro with ~ expands to HOME path" "(subpath \"${TEST_RO_DIR_2}\")"
  assert_policy_contains "$policy_tilde_config" "workdir config add-dirs with ~ expands to HOME path" "file-read* file-write* (subpath \"${TEST_RW_DIR_2}\")"
  rm -f "$workdir_config_file"

  assert_command_succeeds "--workdir expands ~ and ~/..." "$GENERATOR" --output "$policy_tilde_workdir" --workdir="~/${test_rw_dir_2_rel}"
  assert_policy_contains "$policy_tilde_workdir" "--workdir with ~ selects expanded HOME path" "(subpath \"${TEST_RW_DIR_2}\")"

  cat > "$append_profile_tilde_file" <<'EOF'
;; #safehouse-test-id:append-profile-tilde#
(allow file-read-metadata (literal "/tmp"))
EOF
  assert_command_succeeds "--append-profile expands ~ and ~/..." "$GENERATOR" --output "$policy_tilde_append_profile" --append-profile="~/.safehouse-append-tilde-$$.sb"
  assert_policy_contains "$policy_tilde_append_profile" "--append-profile with ~ appends expanded file" "#safehouse-test-id:append-profile-tilde#"
  rm -f "$append_profile_tilde_file"

  section_begin "Agent Profile Selection"
  policy_agent_codex="${TEST_CWD}/policy-agent-codex.sb"
  policy_agent_kilo="${TEST_CWD}/policy-agent-kilo.sb"
  policy_agent_unknown="${TEST_CWD}/policy-agent-unknown.sb"
  policy_agent_claude_app="${TEST_CWD}/policy-agent-claude-app.sb"
  policy_agent_all_agents="${TEST_CWD}/policy-agent-all-agents.sb"
  fake_codex_bin="${TEST_CWD}/codex"
  fake_unknown_bin="${TEST_CWD}/not-an-agent"
  fake_claude_app_dir="${TEST_CWD}/Claude.app"
  fake_claude_app_bin="${fake_claude_app_dir}/Contents/MacOS/Claude"

  cp /usr/bin/true "$fake_codex_bin"
  cp /usr/bin/true "$fake_unknown_bin"
  mkdir -p "$(dirname "$fake_claude_app_bin")"
  cp /usr/bin/true "$fake_claude_app_bin"

  assert_command_succeeds "safehouse selects the matching Codex profile for codex command basename" "$SAFEHOUSE" --output "$policy_agent_codex" -- "$fake_codex_bin"
  assert_policy_contains "$policy_agent_codex" "codex command includes codex agent profile only" ";; Source: 60-agents/codex.sb"
  assert_policy_not_contains "$policy_agent_codex" "codex command omits unrelated claude-code profile" ";; Source: 60-agents/claude-code.sb"

  kilo_cmd="${TEST_CWD}/kilo"
  cp /usr/bin/true "$kilo_cmd"

  assert_command_succeeds "safehouse selects the matching Kilo Code profile for installed kilo/kilocode command basename" "$SAFEHOUSE" --output "$policy_agent_kilo" -- "$kilo_cmd"
  assert_policy_contains "$policy_agent_kilo" "kilo command includes kilo-code agent profile" ";; Source: 60-agents/kilo-code.sb"
  assert_policy_not_contains "$policy_agent_kilo" "kilo command omits unrelated codex profile" ";; Source: 60-agents/codex.sb"

  assert_command_succeeds "safehouse skips 60-agents modules for unknown commands by default" "$SAFEHOUSE" --output "$policy_agent_unknown" -- "$fake_unknown_bin"
  assert_policy_not_contains "$policy_agent_unknown" "unknown command policy omits codex agent profile" ";; Source: 60-agents/codex.sb"
  assert_policy_contains "$policy_agent_unknown" "unknown command policy emits skip note for 60-agents layer" "No command-matched agent profile selected; skipping 60-agents modules."

  assert_command_succeeds "safehouse detects Claude.app command path and includes claude-app profile" "$SAFEHOUSE" --stdout --output "$policy_agent_claude_app" -- "$fake_claude_app_bin"
  assert_policy_contains "$policy_agent_claude_app" "Claude.app command includes claude-app profile" ";; Source: 60-agents/claude-app.sb"
  assert_policy_not_contains "$policy_agent_claude_app" "Claude.app command omits claude-code profile" ";; Source: 60-agents/claude-code.sb"

  assert_command_succeeds "--enable=all-agents in execute mode restores full 60-agents inclusion" "$SAFEHOUSE" --enable=all-agents --output "$policy_agent_all_agents" -- "$fake_unknown_bin"
  assert_policy_contains "$policy_agent_all_agents" "all-agents execute mode includes codex profile" ";; Source: 60-agents/codex.sb"
  assert_policy_contains "$policy_agent_all_agents" "all-agents execute mode includes claude-code profile" ";; Source: 60-agents/claude-code.sb"
  assert_policy_contains "$policy_agent_all_agents" "all-agents execute mode includes kilo-code profile" ";; Source: 60-agents/kilo-code.sb"

  rm -f "$fake_codex_bin" "$fake_unknown_bin" "$kilo_cmd" "$policy_agent_codex" "$policy_agent_kilo" "$policy_agent_unknown" "$policy_agent_claude_app" "$policy_agent_all_agents"
  rm -rf "$fake_claude_app_dir"

  section_begin "Generator Path/Home Validation"
  missing_path="/tmp/safehouse-missing-path-$$"
  rm -rf "$missing_path"
  assert_command_fails "--add-dirs fails for nonexistent path" "$GENERATOR" --add-dirs "$missing_path"
  assert_command_fails "--add-dirs-ro fails for nonexistent path" "$GENERATOR" --add-dirs-ro "$missing_path"
  assert_command_fails "--workdir fails for nonexistent path" "$GENERATOR" --workdir "$missing_path"
  assert_command_fails "generator fails when HOME is unset" /usr/bin/env -u HOME "$GENERATOR"
  home_not_dir="${TEST_CWD}/home-not-a-directory.txt"
  printf 'not-a-directory\n' > "$home_not_dir"
  assert_command_fails "generator fails when HOME is not a directory" /usr/bin/env HOME="$home_not_dir" "$GENERATOR"

  section_begin "Policy Emission Order"
  assert_policy_order_literal "$POLICY_MERGE" "dynamic grants are emitted before workdir grant" "$marker_dynamic" "$marker_workdir"
  assert_policy_order_literal "$POLICY_DEFAULT" "toolchain modules are emitted in deterministic lexical order" ";; Source: 30-toolchains/bun.sb" ";; Source: 30-toolchains/deno.sb"
  assert_policy_order_literal "$POLICY_DEFAULT" "core integration modules are emitted in deterministic lexical order" ";; Source: 50-integrations-core/1password.sb" ";; Source: 50-integrations-core/browser-native-messaging.sb"
  assert_policy_order_literal "$policy_enable_all_agents" "all-agents emission keeps deterministic agent module order" ";; Source: 60-agents/aider.sb" ";; Source: 60-agents/amp.sb"
  assert_policy_order_literal "$policy_enable_all_agents" "all-agents emission keeps deterministic Claude module order" ";; Source: 60-agents/claude-app.sb" ";; Source: 60-agents/claude-code.sb"

  section_begin "Append Profile Option"
  policy_append_profile="${TEST_CWD}/policy-append-profile.sb"
  policy_append_profile_multi="${TEST_CWD}/policy-append-profile-multi.sb"
  append_profile_file="${TEST_CWD}/append-profile-one.sb"
  append_profile_file_2="${TEST_CWD}/append-profile-two.sb"
  cat > "$append_profile_file" <<EOF
;; ${marker_append_profile_one}
(allow file-read-metadata (literal "/tmp"))
EOF
  cat > "$append_profile_file_2" <<EOF
;; ${marker_append_profile_two}
(allow file-read-metadata (literal "/private/tmp"))
EOF

  assert_command_succeeds "--append-profile appends custom profile file" "$GENERATOR" --output "$policy_append_profile" --append-profile "$append_profile_file"
  assert_policy_contains "$policy_append_profile" "appended profile content is present" "$marker_append_profile_one"
  assert_policy_order_literal "$policy_append_profile" "workdir grant is emitted before appended profile rules" "$marker_workdir" "$marker_append_profile_one"
  assert_command_succeeds "--append-profile supports repeated values and equals form" "$GENERATOR" --output "$policy_append_profile_multi" --append-profile="$append_profile_file" --append-profile "$append_profile_file_2"
  assert_policy_order_literal "$policy_append_profile_multi" "repeated --append-profile values preserve append order" "$marker_append_profile_one" "$marker_append_profile_two"
  assert_command_fails "--append-profile fails for nonexistent file" "$GENERATOR" --append-profile "$missing_path"

  rm -f "$policy_append_profile" "$policy_append_profile_multi" "$append_profile_file" "$append_profile_file_2"

  section_begin "Output Path Edge Cases"
  output_space="${TEST_CWD}/output dir/policy with spaces.sb"
  output_nested="${TEST_CWD}/nested/output/path/policy.sb"
  assert_command_succeeds "--output supports paths with spaces" "$GENERATOR" --output "$output_space"
  if [[ -f "$output_space" ]]; then
    log_pass "--output with spaces creates file"
  else
    log_fail "--output with spaces creates file"
  fi
  assert_policy_contains "$output_space" "--output with spaces writes a valid policy" "(version 1)"
  rm -rf "${TEST_CWD}/nested"
  assert_command_succeeds "--output auto-creates missing parent directories" "$GENERATOR" --output "$output_nested"
  if [[ -f "$output_nested" ]]; then
    log_pass "--output created nested parent directories"
  else
    log_fail "--output created nested parent directories"
  fi
  printf 'sentinel-old\n' > "$output_nested"
  assert_command_succeeds "--output overwrites existing policy file" "$GENERATOR" --output "$output_nested"
  if grep -Fq "sentinel-old" "$output_nested"; then
    log_fail "--output overwrite replaces previous file contents"
  else
    log_pass "--output overwrite replaces previous file contents"
  fi

  section_begin "App Bundle Auto-Detection"
  local fake_app_dir fake_app_policy fake_app_no_match_policy resolved_fake_app_dir
  fake_app_dir="${TEST_CWD}/FakeApp.app"
  mkdir -p "${fake_app_dir}/Contents/MacOS"
  cp /usr/bin/true "${fake_app_dir}/Contents/MacOS/fake-binary"
  resolved_fake_app_dir="$(cd "$fake_app_dir" && pwd -P)"
  fake_app_policy="${TEST_CWD}/fake-app-policy.sb"
  fake_app_no_match_policy="${TEST_CWD}/fake-app-no-match-policy.sb"

  assert_command_succeeds "safehouse with .app bundle command exits zero" "$SAFEHOUSE" --output "$fake_app_policy" -- "${fake_app_dir}/Contents/MacOS/fake-binary"

  if [[ -n "${fake_app_policy:-}" && -f "$fake_app_policy" ]]; then
    assert_policy_contains "$fake_app_policy" "safehouse auto-detects .app bundle and grants read-only access" "(subpath \"${resolved_fake_app_dir}\")"
    assert_policy_contains "$fake_app_policy" "safehouse .app bundle grant includes file-read*" "file-read*"
  else
    log_fail "safehouse .app bundle auto-detection produced a valid policy file"
  fi

  assert_command_succeeds "safehouse non-.app command policy generation works" "$SAFEHOUSE" --output "$fake_app_no_match_policy" -- /usr/bin/true
  if [[ -n "${fake_app_no_match_policy:-}" && -f "$fake_app_no_match_policy" ]]; then
    assert_policy_not_contains "$fake_app_no_match_policy" "safehouse does not inject .app grant for non-.app command" "FakeApp.app"
  else
    log_fail "safehouse non-.app command produced a valid output policy"
  fi

  rm -f "$fake_app_policy" "$fake_app_no_match_policy"
  rm -rf "$fake_app_dir"

  section_begin "safehouse Argument Passthrough"
  args_file="/tmp/safehouse-args-$$.txt"
  rm -f "$args_file"
  assert_command_succeeds "safehouse preserves quoted and spaced wrapped command arguments" "$SAFEHOUSE" -- /bin/sh -c 'printf "[%s]|[%s]|[%s]|[%s]\n" "$1" "$2" "$3" "$4" > "$5"' sh "two words" 'quote"double' "single'quote" '$dollar value' "$args_file"
  if [[ -f "$args_file" ]] && grep -Fxq "[two words]|[quote\"double]|[single'quote]|[\$dollar value]" "$args_file"; then
    log_pass "safehouse preserves exact wrapped command argument boundaries"
  else
    log_fail "safehouse preserves exact wrapped command argument boundaries"
  fi
  rm -f "$args_file"
}

register_section run_section_cli_edge_cases
