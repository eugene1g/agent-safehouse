#!/usr/bin/env bash

run_section_tooling() {
  local node_bin
  local policy_claude_startup policy_amp_startup

  section_begin "Toolchains"
  assert_allowed_if_exists "$POLICY_DEFAULT" "git --version" "git" /bin/sh -c 'git --version'

  node_bin="$(command -v node 2>/dev/null || true)"
  if [[ -n "$node_bin" ]]; then
    node_bin="$(realpath "$node_bin" 2>/dev/null || readlink -f "$node_bin" 2>/dev/null || echo "$node_bin")"
    assert_allowed_strict "$POLICY_DEFAULT" "node --version" "$node_bin" --version
  else
    log_skip "node --version (node not found)"
  fi

  assert_allowed_if_exists "$POLICY_DEFAULT" "python3 --version" "python3" /bin/sh -c 'python3 --version'
  assert_allowed_if_exists "$POLICY_DEFAULT" "perl -v" "perl" /bin/sh -c 'perl -v >/dev/null'

  section_begin "Agent Startup"
  policy_claude_startup="${TEST_CWD}/policy-agent-startup-claude.sb"
  policy_amp_startup="${TEST_CWD}/policy-agent-startup-amp.sb"

  assert_command_succeeds "safehouse generates command-scoped policy for claude startup checks" "$SAFEHOUSE" --stdout --output "$policy_claude_startup" -- claude --version
  assert_command_succeeds "safehouse generates command-scoped policy for amp startup checks" "$SAFEHOUSE" --stdout --output "$policy_amp_startup" -- amp --version

  assert_allowed_if_exists "$policy_claude_startup" "claude --version" "${HOME}/.local/bin/claude" /bin/sh -c "'${HOME}/.local/bin/claude' --version"
  assert_allowed_if_exists "$policy_amp_startup" "amp --version" "${HOME}/.amp/bin/amp" /bin/sh -c "'${HOME}/.amp/bin/amp' --version"

  rm -f "$policy_claude_startup" "$policy_amp_startup"

  section_begin "Git Operations"
  assert_allowed "$POLICY_DEFAULT" "git init in CWD" /bin/sh -c "cd '${TEST_CWD}' && git init -q"
  assert_allowed_if_exists "$POLICY_DEFAULT" "git config read" "git" /bin/sh -c 'git config --global --list'
  assert_allowed_if_exists "$POLICY_DEFAULT" "git ls-remote (network HTTPS)" "git" /bin/sh -c 'git ls-remote --exit-code https://github.com/git/git.git HEAD'
}

register_section run_section_tooling
