#!/usr/bin/env bash

run_section_tooling() {
  local node_bin java_home_dir copilot_bin
  local policy_claude_startup policy_amp_startup policy_copilot_startup

  section_begin "Toolchains"
  assert_allowed_if_exists "$POLICY_DEFAULT" "git --version" "git" /bin/sh -c 'git --version'

  node_bin="$(command -v node 2>/dev/null || true)"
  if [[ -n "$node_bin" ]]; then
    node_bin="$(realpath "$node_bin" 2>/dev/null || readlink -f "$node_bin" 2>/dev/null || echo "$node_bin")"
    assert_allowed_strict "$POLICY_DEFAULT" "node --version" "$node_bin" --version
  else
    log_skip "node --version (node not found)"
  fi

  if [[ -x /usr/bin/java ]]; then
    java_home_dir="$(/usr/libexec/java_home 2>/dev/null || true)"
    if [[ -n "$java_home_dir" ]] && [[ "$java_home_dir" == /Library/Java/* || "$java_home_dir" == "${HOME}"/Library/Java/* ]]; then
      assert_allowed_strict "$POLICY_DEFAULT" "java -version" /usr/bin/java -version
    elif [[ -n "$java_home_dir" ]]; then
      log_skip "java -version (java_home resolved nonstandard runtime outside policy: ${java_home_dir})"
    else
      log_skip "java -version (no discoverable macOS runtime via java_home)"
    fi
  else
    log_skip "java -version (/usr/bin/java not found)"
  fi

  assert_allowed_if_exists "$POLICY_DEFAULT" "python3 --version" "python3" /bin/sh -c 'python3 --version'
  assert_allowed_if_exists "$POLICY_DEFAULT" "perl -v" "perl" /bin/sh -c 'perl -v >/dev/null'

  section_begin "Agent Startup"
  policy_claude_startup="${TEST_CWD}/policy-agent-startup-claude.sb"
  policy_amp_startup="${TEST_CWD}/policy-agent-startup-amp.sb"
  policy_copilot_startup="${TEST_CWD}/policy-agent-startup-copilot.sb"

  assert_command_succeeds "safehouse generates command-scoped policy for claude startup checks" "$SAFEHOUSE" --stdout --output "$policy_claude_startup" -- claude --version
  assert_command_succeeds "safehouse generates command-scoped policy for amp startup checks" "$SAFEHOUSE" --stdout --output "$policy_amp_startup" -- amp --version
  copilot_bin="$(command -v copilot 2>/dev/null || true)"
  if [[ -n "$copilot_bin" ]]; then
    copilot_bin="$(realpath "$copilot_bin" 2>/dev/null || readlink -f "$copilot_bin" 2>/dev/null || echo "$copilot_bin")"
    assert_command_succeeds "safehouse generates command-scoped policy for copilot startup checks" "$SAFEHOUSE" --stdout --output "$policy_copilot_startup" -- "$copilot_bin" --version
  else
    log_skip "safehouse generates command-scoped policy for copilot startup checks (copilot not found)"
  fi

  assert_allowed_if_exists "$policy_claude_startup" "claude --version" "${HOME}/.local/bin/claude" /bin/sh -c "'${HOME}/.local/bin/claude' --version"
  assert_allowed_if_exists "$policy_amp_startup" "amp --version" "${HOME}/.amp/bin/amp" /bin/sh -c "'${HOME}/.amp/bin/amp' --version"
  if [[ -n "$copilot_bin" ]]; then
    assert_allowed_strict "$policy_copilot_startup" "copilot --version" "$copilot_bin" --version
  else
    log_skip "copilot --version (copilot not found)"
  fi

  rm -f "$policy_claude_startup" "$policy_amp_startup" "$policy_copilot_startup"

  section_begin "Git Operations"
  assert_allowed "$POLICY_DEFAULT" "git init in CWD" /bin/sh -c "cd '${TEST_CWD}' && git init -q"
  assert_allowed_if_exists "$POLICY_DEFAULT" "git config read" "git" /bin/sh -c 'git config --global --list'
  assert_allowed_if_exists "$POLICY_DEFAULT" "git ls-remote (network HTTPS)" "git" /bin/sh -c 'git ls-remote --exit-code https://github.com/git/git.git HEAD'
}

register_section run_section_tooling
