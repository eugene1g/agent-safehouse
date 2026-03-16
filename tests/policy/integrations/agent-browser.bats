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

@test "[EXECUTION] enable=agent-browser can open example.com and read the page title" {
  local precheck_session sandbox_session socket_dir

  sft_require_cmd_or_skip agent-browser

  precheck_session="abp-${BATS_TEST_NUMBER}-$$"
  sandbox_session="abs-${BATS_TEST_NUMBER}-$$"
  socket_dir="$(mktemp -d "/tmp/sft-ab.${BATS_TEST_NUMBER}.XXXXXX")" || return 1

  run agent_browser_get_example_title "$precheck_session" "$SAFEHOUSE_HOST_HOME" "$socket_dir"
  [ "$status" -eq 0 ] || skip "agent-browser precheck failed outside sandbox"

  run safehouse_ok_env \
    "HOME=$SAFEHOUSE_HOST_HOME" \
    "AGENT_BROWSER_SOCKET_DIR=$socket_dir" \
    "AGENT_BROWSER_DEFAULT_TIMEOUT=10000" \
    -- \
    --enable=agent-browser \
    -- /bin/sh -c '
    session_name="$1"
    cleanup() {
      agent-browser --session "$session_name" close >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    agent-browser --session "$session_name" open https://example.com >/dev/null &&
      agent-browser --session "$session_name" wait 500 >/dev/null &&
      agent-browser --session "$session_name" get title
  ' _ "$sandbox_session"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Example Domain"
  rm -rf -- "$socket_dir"
}

agent_browser_get_example_title() {
  local session_name="$1" home_dir="${2:-$HOME}" socket_dir="${3:-}"

  HOME="$home_dir" \
    AGENT_BROWSER_SOCKET_DIR="$socket_dir" \
    AGENT_BROWSER_DEFAULT_TIMEOUT=10000 \
    /bin/sh -c '
    session_name="$1"
    cleanup() {
      agent-browser --session "$session_name" close >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    agent-browser --session "$session_name" open https://example.com >/dev/null &&
      agent-browser --session "$session_name" wait 500 >/dev/null &&
      agent-browser --session "$session_name" get title
  ' _ "$session_name"
}
