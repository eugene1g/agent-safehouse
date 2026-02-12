#!/usr/bin/env bash

run_section_cli_edge_cases() {
  local policy_enable_arg policy_enable_csv policy_enable_kubectl policy_enable_macos_gui policy_enable_electron policy_enable_browser_native_messaging policy_enable_all_agents policy_enable_wide_read policy_workdir_empty_eq policy_env_grants policy_env_workdir
  local policy_dedup_paths
  local policy_env_workdir_empty policy_env_cli_workdir policy_workdir_config policy_workdir_config_ignored policy_workdir_config_env_trust missing_path home_not_dir
  local policy_tilde_flags policy_tilde_config policy_tilde_workdir policy_tilde_append_profile
  local policy_explain explain_output_file
  local policy_append_profile policy_append_profile_multi append_profile_file append_profile_file_2
  local policy_agent_codex policy_agent_goose policy_agent_kilo policy_agent_unknown policy_agent_claude_app policy_agent_vscode_app policy_agent_all_agents
  local output_space output_nested args_file workdir_config_file safehouse_env_policy safehouse_env_status
  local fake_codex_bin fake_goose_bin fake_unknown_bin fake_claude_app_dir fake_claude_app_bin fake_vscode_app_dir fake_vscode_app_bin kilo_cmd
  local append_profile_tilde_file
  local test_ro_dir_rel test_ro_dir_2_rel test_rw_dir_2_rel
  local resolved_test_rw_dir resolved_test_ro_dir
  local marker_dynamic marker_workdir marker_container_runtime_socket_deny marker_append_profile_one marker_append_profile_two
  local policy_marker

  marker_dynamic="#safehouse-test-id:dynamic-cli-grants#"
  marker_workdir="#safehouse-test-id:workdir-grant#"
  marker_container_runtime_socket_deny="#safehouse-test-id:container-runtime-socket-deny#"
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
  policy_enable_kubectl="${TEST_CWD}/policy-enable-kubectl.sb"
  policy_enable_browser_native_messaging="${TEST_CWD}/policy-enable-browser-native-messaging.sb"
  assert_command_succeeds "--enable docker parses as separate argument form" "$GENERATOR" --output "$policy_enable_arg" --enable docker
  assert_policy_contains "$policy_enable_arg" "--enable docker includes docker grants" "/var/run/docker.sock"
  assert_policy_contains "$policy_enable_arg" "--enable docker preamble reports explicit optional integration inclusion" "Optional integrations explicitly enabled: docker"
  assert_policy_not_contains "$policy_enable_arg" "--enable docker does not include browser native messaging grants unless explicitly enabled" "/NativeMessagingHosts"
  assert_command_succeeds "--enable kubectl parses as separate argument form" "$GENERATOR" --output "$policy_enable_kubectl" --enable kubectl
  assert_policy_contains "$policy_enable_kubectl" "--enable kubectl includes kubectl integration profile marker" "#safehouse-test-id:kubectl-integration#"
  assert_command_succeeds "--enable browser-native-messaging parses as separate argument form" "$GENERATOR" --output "$policy_enable_browser_native_messaging" --enable browser-native-messaging
  assert_policy_contains "$policy_enable_browser_native_messaging" "--enable browser-native-messaging includes browser native messaging grants" "/NativeMessagingHosts"
  assert_command_succeeds "--enable=docker,electron,kubectl parses CSV with whitespace" "$GENERATOR" --output "$policy_enable_csv" "--enable=docker, electron, kubectl"
  assert_policy_contains "$policy_enable_csv" "CSV --enable includes docker grants" "/var/run/docker.sock"
  assert_policy_contains "$policy_enable_csv" "CSV --enable includes electron grants" "#safehouse-test-id:electron-integration#"
  assert_policy_contains "$policy_enable_csv" "CSV --enable includes kubectl grants" "#safehouse-test-id:kubectl-integration#"
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
  assert_command_succeeds "--enable=all-agents restores full scoped profile inclusion (60-agents + 65-apps)" "$GENERATOR" --output "$policy_enable_all_agents" --enable=all-agents
  for policy_marker in \
    ";; Source: 65-apps/claude-app.sb" \
    ";; Source: 65-apps/vscode-app.sb" \
    ";; Source: 60-agents/claude-code.sb" \
    ";; Source: 60-agents/codex.sb" \
    ";; Source: 60-agents/goose.sb" \
    ";; Source: 60-agents/kilo-code.sb"; do
    assert_policy_contains "$policy_enable_all_agents" "--enable=all-agents includes expected marker (${policy_marker})" "$policy_marker"
  done
  policy_enable_wide_read="${TEST_CWD}/policy-enable-wide-read.sb"
  assert_command_succeeds "--enable=wide-read adds broad read-only filesystem visibility" "$GENERATOR" --output "$policy_enable_wide_read" --enable=wide-read
  assert_policy_contains "$policy_enable_wide_read" "--enable=wide-read emits wide-read marker" "#safehouse-test-id:wide-read#"
  assert_policy_contains "$policy_enable_wide_read" "--enable=wide-read emits recursive read grant for /" "(allow file-read* (subpath \"/\"))"

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

  section_begin "Path Grant Deduplication"
  policy_dedup_paths="${TEST_CWD}/policy-dedup-paths.sb"
  assert_command_succeeds "duplicate --add-dirs and --add-dirs-ro entries are deduplicated" "$GENERATOR" --workdir="" --output "$policy_dedup_paths" --add-dirs-ro="${TEST_RO_DIR}:${TEST_RO_DIR}" --add-dirs="${TEST_RW_DIR}:${TEST_RW_DIR}"
  local ro_grant_count rw_grant_count
  ro_grant_count="$(rg -F -c "(subpath \"${TEST_RO_DIR}\")" "$policy_dedup_paths" || true)"
  rw_grant_count="$(rg -F -c "file-read* file-write* (subpath \"${resolved_test_rw_dir}\")" "$policy_dedup_paths" || true)"
  if [[ "$ro_grant_count" -eq 1 ]]; then
    log_pass "duplicate read-only grants collapse to one emitted rule"
  else
    log_fail "duplicate read-only grants collapse to one emitted rule"
  fi
  if [[ "$rw_grant_count" -eq 1 ]]; then
    log_pass "duplicate read/write grants collapse to one emitted rule"
  else
    log_fail "duplicate read/write grants collapse to one emitted rule"
  fi

  section_begin "Workdir Config File"
  policy_workdir_config="${TEST_CWD}/policy-workdir-config.sb"
  policy_workdir_config_ignored="${TEST_CWD}/policy-workdir-config-ignored.sb"
  policy_workdir_config_env_trust="${TEST_CWD}/policy-workdir-config-env-trust.sb"
  workdir_config_file="${TEST_CWD}/.safehouse"
  cat > "$workdir_config_file" <<EOF
# SAFEHOUSE config loaded from selected workdir
add-dirs-ro=${TEST_RO_DIR_2}
add-dirs=${TEST_RW_DIR_2}
EOF
  assert_command_succeeds "workdir config file is ignored by default" /bin/sh -c "cd '${TEST_CWD}' && '${GENERATOR}' --output '${policy_workdir_config_ignored}'"
  assert_policy_not_contains "$policy_workdir_config_ignored" "workdir config file is ignored by default for read-only grants" "(subpath \"${TEST_RO_DIR_2}\")"
  assert_policy_not_contains "$policy_workdir_config_ignored" "workdir config file is ignored by default for read/write grants" "file-read* file-write* (subpath \"${TEST_RW_DIR_2}\")"
  assert_command_succeeds "workdir config file loads when --trust-workdir-config is set" /bin/sh -c "cd '${TEST_CWD}' && '${GENERATOR}' --trust-workdir-config --output '${policy_workdir_config}'"
  assert_policy_contains "$policy_workdir_config" "trusted workdir config file emits read-only grant" "(subpath \"${TEST_RO_DIR_2}\")"
  assert_policy_contains "$policy_workdir_config" "trusted workdir config file emits read/write grant" "file-read* file-write* (subpath \"${TEST_RW_DIR_2}\")"
  assert_command_succeeds "SAFEHOUSE_TRUST_WORKDIR_CONFIG=1 loads workdir config file" /bin/sh -c "cd '${TEST_CWD}' && SAFEHOUSE_TRUST_WORKDIR_CONFIG=1 '${GENERATOR}' --output '${policy_workdir_config_env_trust}'"
  assert_policy_contains "$policy_workdir_config_env_trust" "SAFEHOUSE_TRUST_WORKDIR_CONFIG trusted workdir config file emits read-only grant" "(subpath \"${TEST_RO_DIR_2}\")"
  assert_policy_contains "$policy_workdir_config_env_trust" "SAFEHOUSE_TRUST_WORKDIR_CONFIG trusted workdir config file emits read/write grant" "file-read* file-write* (subpath \"${TEST_RW_DIR_2}\")"
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
  assert_command_succeeds "trusted workdir config add-dirs values expand ~ and ~/..." /bin/sh -c "cd '${TEST_CWD}' && '${GENERATOR}' --trust-workdir-config --output '${policy_tilde_config}'"
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

  section_begin "Explain Output"
  policy_explain="${TEST_CWD}/policy-explain.sb"
  explain_output_file="${TEST_CWD}/policy-explain-output.txt"
  rm -f "$explain_output_file"
  set +e
  /bin/sh -c "cd '${TEST_CWD}' && '${GENERATOR}' --explain --workdir='${TEST_RW_DIR}' --output '${policy_explain}' --add-dirs-ro='${TEST_RO_DIR}' --add-dirs='${TEST_RW_DIR_2}' 2>'${explain_output_file}' >/dev/null"
  local explain_status=$?
  set -e
  if [[ "$explain_status" -eq 0 ]]; then
    log_pass "--explain succeeds for policy generation"
  else
    log_fail "--explain succeeds for policy generation"
  fi
  if [[ -f "$explain_output_file" ]] && grep -Fq "safehouse explain:" "$explain_output_file"; then
    log_pass "--explain emits summary header"
  else
    log_fail "--explain emits summary header"
  fi
  if [[ -f "$explain_output_file" ]] && grep -Fq "effective workdir: ${resolved_test_rw_dir} (source: --workdir)" "$explain_output_file"; then
    log_pass "--explain reports effective workdir and source"
  else
    log_fail "--explain reports effective workdir and source"
  fi
  if [[ -f "$explain_output_file" ]] && grep -Fq "add-dirs-ro (normalized): ${TEST_RO_DIR}" "$explain_output_file"; then
    log_pass "--explain reports normalized read-only grants"
  else
    log_fail "--explain reports normalized read-only grants"
  fi
  if [[ -f "$explain_output_file" ]] && grep -Fq "add-dirs (normalized): ${TEST_RW_DIR_2}" "$explain_output_file"; then
    log_pass "--explain reports normalized read/write grants"
  else
    log_fail "--explain reports normalized read/write grants"
  fi
  rm -f "$policy_explain" "$explain_output_file"

  section_begin "Scoped Profile Selection"
  policy_agent_codex="${TEST_CWD}/policy-agent-codex.sb"
  policy_agent_goose="${TEST_CWD}/policy-agent-goose.sb"
  policy_agent_kilo="${TEST_CWD}/policy-agent-kilo.sb"
  policy_agent_unknown="${TEST_CWD}/policy-agent-unknown.sb"
  policy_agent_claude_app="${TEST_CWD}/policy-agent-claude-app.sb"
  policy_agent_vscode_app="${TEST_CWD}/policy-agent-vscode-app.sb"
  policy_agent_all_agents="${TEST_CWD}/policy-agent-all-agents.sb"
  fake_codex_bin="${TEST_CWD}/codex"
  fake_goose_bin="${TEST_CWD}/goose"
  fake_unknown_bin="${TEST_CWD}/not-an-agent"
  fake_claude_app_dir="${TEST_CWD}/Claude.app"
  fake_claude_app_bin="${fake_claude_app_dir}/Contents/MacOS/Claude"
  fake_vscode_app_dir="${TEST_CWD}/Visual Studio Code.app"
  fake_vscode_app_bin="${fake_vscode_app_dir}/Contents/MacOS/Electron"

  cp /usr/bin/true "$fake_codex_bin"
  cp /usr/bin/true "$fake_goose_bin"
  cp /usr/bin/true "$fake_unknown_bin"
  mkdir -p "$(dirname "$fake_claude_app_bin")"
  cp /usr/bin/true "$fake_claude_app_bin"
  mkdir -p "$(dirname "$fake_vscode_app_bin")"
  cp /usr/bin/true "$fake_vscode_app_bin"

  assert_command_succeeds "safehouse selects the matching Codex profile for codex command basename" "$SAFEHOUSE" --output "$policy_agent_codex" -- "$fake_codex_bin"
  assert_policy_contains "$policy_agent_codex" "codex command includes codex agent profile only" ";; Source: 60-agents/codex.sb"
  assert_policy_contains "$policy_agent_codex" "codex command auto-injects keychain integration from profile metadata" ";; Integration: Keychain"
  assert_policy_not_contains "$policy_agent_codex" "codex command omits unrelated claude-code profile" ";; Source: 60-agents/claude-code.sb"

  assert_command_succeeds "safehouse selects the matching Goose profile for goose command basename" "$SAFEHOUSE" --output "$policy_agent_goose" -- "$fake_goose_bin"
  assert_policy_contains "$policy_agent_goose" "goose command includes goose agent profile" ";; Source: 60-agents/goose.sb"
  assert_policy_not_contains "$policy_agent_goose" "goose command omits unrelated codex profile" ";; Source: 60-agents/codex.sb"

  kilo_cmd="${TEST_CWD}/kilo"
  cp /usr/bin/true "$kilo_cmd"

  assert_command_succeeds "safehouse selects the matching Kilo Code profile for installed kilo/kilocode command basename" "$SAFEHOUSE" --output "$policy_agent_kilo" -- "$kilo_cmd"
  assert_policy_contains "$policy_agent_kilo" "kilo command includes kilo-code agent profile" ";; Source: 60-agents/kilo-code.sb"
  assert_policy_not_contains "$policy_agent_kilo" "kilo command omits unrelated codex profile" ";; Source: 60-agents/codex.sb"

  assert_command_succeeds "safehouse skips scoped app/agent modules for unknown commands by default" "$SAFEHOUSE" --output "$policy_agent_unknown" -- "$fake_unknown_bin"
  assert_policy_not_contains "$policy_agent_unknown" "unknown command policy omits codex agent profile" ";; Source: 60-agents/codex.sb"
  assert_policy_not_contains "$policy_agent_unknown" "unknown command policy omits macOS GUI desktop workflow grant" "(global-name \"com.apple.backgroundtaskmanagementagent\")"
  assert_policy_not_contains "$policy_agent_unknown" "unknown command policy omits keychain integration (no profile requirement selected)" ";; Integration: Keychain"
  assert_policy_contains "$policy_agent_unknown" "unknown command policy emits skip note for scoped profile layers" "No command-matched app/agent profile selected; skipping 60-agents and 65-apps modules."

  assert_command_succeeds "safehouse detects Claude.app command path and includes claude-app profile" "$SAFEHOUSE" --stdout --output "$policy_agent_claude_app" -- "$fake_claude_app_bin"
  for policy_marker in \
    ";; Source: 65-apps/claude-app.sb" \
    "(global-name \"com.apple.backgroundtaskmanagementagent\")" \
    ";; Integration: Keychain" \
    ";; Integration: macOS GUI" \
    "#safehouse-test-id:electron-integration#"; do
    assert_policy_contains "$policy_agent_claude_app" "Claude.app command includes expected marker (${policy_marker})" "$policy_marker"
  done
  assert_policy_contains "$policy_agent_claude_app" "Claude.app preamble reports implicit optional integrations from profile requirements" "Optional integrations implicitly injected: macos-gui electron"
  assert_policy_not_contains "$policy_agent_claude_app" "Claude.app command omits claude-code profile" ";; Source: 60-agents/claude-code.sb"

  assert_command_succeeds "safehouse detects Visual Studio Code.app command path and includes vscode-app profile" "$SAFEHOUSE" --stdout --output "$policy_agent_vscode_app" -- "$fake_vscode_app_bin"
  for policy_marker in \
    ";; Source: 65-apps/vscode-app.sb" \
    "(global-name \"com.apple.backgroundtaskmanagementagent\")" \
    ";; Integration: Keychain" \
    ";; Integration: macOS GUI" \
    "#safehouse-test-id:electron-integration#"; do
    assert_policy_contains "$policy_agent_vscode_app" "Visual Studio Code.app command includes expected marker (${policy_marker})" "$policy_marker"
  done
  assert_policy_contains "$policy_agent_vscode_app" "Visual Studio Code.app policy includes VSCode preference plist literal for direct write/unlink flows" "(home-literal \"/Library/Preferences/com.microsoft.VSCode.plist\")"
  assert_policy_not_contains "$policy_agent_vscode_app" "Visual Studio Code.app command omits claude-app app profile" ";; Source: 65-apps/claude-app.sb"

  assert_command_succeeds "--enable=all-agents in execute mode restores full scoped profile inclusion" "$SAFEHOUSE" --enable=all-agents --output "$policy_agent_all_agents" -- "$fake_unknown_bin"
  for policy_marker in \
    ";; Source: 65-apps/claude-app.sb" \
    "(global-name \"com.apple.backgroundtaskmanagementagent\")" \
    ";; Source: 65-apps/vscode-app.sb" \
    ";; Source: 60-agents/codex.sb" \
    ";; Source: 60-agents/claude-code.sb" \
    ";; Source: 60-agents/goose.sb" \
    ";; Source: 60-agents/kilo-code.sb" \
    ";; Integration: Keychain" \
    ";; Integration: macOS GUI" \
    "#safehouse-test-id:electron-integration#"; do
    assert_policy_contains "$policy_agent_all_agents" "all-agents execute mode includes expected marker (${policy_marker})" "$policy_marker"
  done

  rm -f "$fake_codex_bin" "$fake_goose_bin" "$fake_unknown_bin" "$kilo_cmd" "$policy_agent_codex" "$policy_agent_goose" "$policy_agent_kilo" "$policy_agent_unknown" "$policy_agent_claude_app" "$policy_agent_vscode_app" "$policy_agent_all_agents"
  rm -rf "$fake_claude_app_dir" "$fake_vscode_app_dir"

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
  assert_policy_order_literal "$policy_enable_arg" "container runtime deny core profile is emitted before docker optional integration profile" "$marker_container_runtime_socket_deny" ";; Integration: Docker"
  assert_policy_order_literal "$POLICY_DEFAULT" "toolchain modules are emitted in deterministic lexical order" ";; Source: 30-toolchains/bun.sb" ";; Source: 30-toolchains/deno.sb"
  assert_policy_order_literal "$POLICY_DEFAULT" "core integration modules are emitted in deterministic lexical order" ";; Source: 50-integrations-core/git.sb" ";; Source: 50-integrations-core/scm-clis.sb"
  assert_policy_order_literal "$policy_enable_all_agents" "all-agents emission keeps deterministic agent module order" ";; Source: 60-agents/aider.sb" ";; Source: 60-agents/amp.sb"
  assert_policy_order_literal "$policy_enable_all_agents" "all-agents emission keeps deterministic Claude module order across agent/app layers" ";; Source: 60-agents/claude-code.sb" ";; Source: 65-apps/claude-app.sb"
  assert_policy_order_literal "$policy_enable_all_agents" "all-agents emission keeps deterministic Goose module order" ";; Source: 60-agents/gemini.sb" ";; Source: 60-agents/goose.sb"

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
  assert_policy_order_literal "$policy_append_profile" "container runtime socket deny is emitted before appended profile rules" "$marker_container_runtime_socket_deny" "$marker_append_profile_one"
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
  if rg -Fq "sentinel-old" "$output_nested"; then
    log_fail "--output overwrite replaces previous file contents"
  else
    log_pass "--output overwrite replaces previous file contents"
  fi

  section_begin "App Bundle Auto-Detection"
  local fake_app_dir fake_app_policy fake_app_no_match_policy fake_app_path_lookup_policy resolved_fake_app_dir fake_app_cmd
  fake_app_dir="${TEST_CWD}/FakeApp.app"
  mkdir -p "${fake_app_dir}/Contents/MacOS"
  cp /usr/bin/true "${fake_app_dir}/Contents/MacOS/fake-binary"
  resolved_fake_app_dir="$(cd "$fake_app_dir" && pwd -P)"
  fake_app_policy="${TEST_CWD}/fake-app-policy.sb"
  fake_app_no_match_policy="${TEST_CWD}/fake-app-no-match-policy.sb"
  fake_app_path_lookup_policy="${TEST_CWD}/fake-app-path-lookup-policy.sb"
  fake_app_cmd="${TEST_CWD}/fake-app-cmd"
  cp /usr/bin/true "$fake_app_cmd"
  ln -sf "${fake_app_dir}/Contents/MacOS/fake-binary" "$fake_app_cmd"

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

  assert_command_succeeds "safehouse resolves bare command via PATH for .app bundle detection" /bin/sh -c "cd '${TEST_CWD}' && PATH='${TEST_CWD}:${PATH}' '${SAFEHOUSE}' --output '${fake_app_path_lookup_policy}' -- fake-app-cmd"
  if [[ -n "${fake_app_path_lookup_policy:-}" && -f "$fake_app_path_lookup_policy" ]]; then
    assert_policy_contains "$fake_app_path_lookup_policy" "safehouse bare-command app detection grants read-only app bundle access" "(subpath \"${resolved_fake_app_dir}\")"
  else
    log_fail "safehouse bare-command app detection produced a valid output policy"
  fi

  rm -f "$fake_app_policy" "$fake_app_no_match_policy" "$fake_app_path_lookup_policy" "$fake_app_cmd"
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
