#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=agent-browser adds state access and only its intended dependencies" {
  local profile
  profile="$(safehouse_profile --enable=agent-browser)"

  sft_assert_includes_source "$profile" "55-integrations-optional/agent-browser.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/chromium-full.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/chromium-headless.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/electron.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/macos-gui.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/shell-init.sb"
}

@test "[EXECUTION] enable=agent-browser can launch and read a page title" {
  local smoke_url expected_title agent_browser_bin
  local precheck_session sandbox_session precheck_socket_dir sandbox_socket_dir

  smoke_url='data:text/html,<title>Safehouse%20agent-browser%20smoke</title><h1>ok</h1>'
  expected_title='Safehouse agent-browser smoke'

  agent_browser_bin="$(sft_command_path_or_skip agent-browser)"

  precheck_session="abp-${BATS_TEST_NUMBER}-$$"
  sandbox_session="abs-${BATS_TEST_NUMBER}-$$"
  precheck_socket_dir="$(mktemp -d "/tmp/sft-abp.${BATS_TEST_NUMBER}.XXXXXX")" || return 1
  sandbox_socket_dir="$(mktemp -d "/tmp/sft-abs.${BATS_TEST_NUMBER}.XXXXXX")" || return 1

  run agent_browser_get_page_title "$agent_browser_bin" "$precheck_session" "$smoke_url" "$SAFEHOUSE_HOST_HOME" "$precheck_socket_dir"
  [ "$status" -eq 0 ] || skip "agent-browser precheck failed outside sandbox"

  safehouse_ok_env \
    "HOME=$SAFEHOUSE_HOST_HOME" \
    "AGENT_BROWSER_SOCKET_DIR=$sandbox_socket_dir" \
    "AGENT_BROWSER_DEFAULT_TIMEOUT=30000" \
    -- \
    --enable=agent-browser \
    -- "$agent_browser_bin" --session "$sandbox_session" open "$smoke_url" >/dev/null

  run safehouse_ok_env \
    "HOME=$SAFEHOUSE_HOST_HOME" \
    "AGENT_BROWSER_SOCKET_DIR=$sandbox_socket_dir" \
    "AGENT_BROWSER_DEFAULT_TIMEOUT=30000" \
    -- \
    --enable=agent-browser \
    -- "$agent_browser_bin" --session "$sandbox_session" get title
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$expected_title"

  HOME="$SAFEHOUSE_HOST_HOME" \
    AGENT_BROWSER_SOCKET_DIR="$sandbox_socket_dir" \
    AGENT_BROWSER_DEFAULT_TIMEOUT=30000 \
    "$agent_browser_bin" --session "$sandbox_session" close >/dev/null 2>&1 || true
  rm -rf -- "$precheck_socket_dir" "$sandbox_socket_dir"
}

agent_browser_get_page_title() {
  local agent_browser_bin="$1" session_name="$2" page_url="$3" home_dir="${4:-$HOME}" socket_dir="${5:-}"
  local title

  HOME="$home_dir" \
    AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
    AGENT_BROWSER_DEFAULT_TIMEOUT=30000 \
    "$agent_browser_bin" --session "$session_name" open "$page_url" >/dev/null || return 1

  title="$(
    HOME="$home_dir" \
      AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
      AGENT_BROWSER_DEFAULT_TIMEOUT=30000 \
      "$agent_browser_bin" --session "$session_name" get title
  )" || return 1

  printf '%s\n' "$title"

  HOME="$home_dir" \
    AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
    AGENT_BROWSER_DEFAULT_TIMEOUT=30000 \
    "$agent_browser_bin" --session "$session_name" close >/dev/null 2>&1 || true
}
