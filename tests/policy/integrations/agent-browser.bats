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

@test "[EXECUTION] enable=agent-browser lets the downloaded Chrome for Testing runtime launch when invoked indirectly" {
  local chrome_bin smoke_url expected_title
  local -a chrome_args
  local precheck_output_file allowed_output_file precheck_output allowed_output
  local precheck_status allowed_status

  chrome_bin="$(sft_agent_browser_chrome_bin)"
  [ -n "$chrome_bin" ] || skip "agent-browser Chrome for Testing runtime is not installed"

  smoke_url='data:text/html,<title>Safehouse%20agent-browser%20smoke</title><h1>ok</h1>'
  expected_title='Safehouse agent-browser smoke'
  chrome_args=(--use-mock-keychain --no-sandbox --headless=new --dump-dom "$smoke_url")

  precheck_output_file="$(mktemp "/tmp/sft-agent-browser-precheck.XXXXXX")" || return 1
  precheck_status=0
  HOME="$SAFEHOUSE_HOST_HOME" "$chrome_bin" "${chrome_args[@]}" >"$precheck_output_file" 2>&1 || precheck_status=$?
  precheck_output="$(<"$precheck_output_file")"
  rm -f -- "$precheck_output_file"

  if [[ "$precheck_status" -ne 0 && "$precheck_output" != *"$expected_title"* ]]; then
    skip "agent-browser Chrome for Testing precheck failed outside sandbox"
  fi
  sft_assert_contains "$precheck_output" "$expected_title"

  # Validate the underlying runtime bundle instead of the agent-browser CLI.
  # Recent upstream native releases still report open IPC reliability bugs under
  # Safehouse-relevant flows: https://github.com/vercel-labs/agent-browser/issues/322
  #
  # Keep the negative half to plain file reads. Launching the denied browser
  # bundle locally makes macOS surface a Crash Reporter dialog for the aborted
  # Chrome-for-Testing process.
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_denied \
    --enable=chromium-full \
    -- /bin/sh -c '/usr/bin/head -c 4 "$1" >/dev/null' \
    _ "$chrome_bin"

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok \
    --enable=agent-browser \
    -- /bin/sh -c '/usr/bin/head -c 4 "$1" >/dev/null' \
    _ "$chrome_bin"

  allowed_output_file="$(mktemp "/tmp/sft-agent-browser-allowed.XXXXXX")" || return 1
  allowed_status=0
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok \
    --enable=agent-browser \
    -- /bin/sh -c '"$1" --use-mock-keychain --no-sandbox --headless=new --dump-dom "$2"' \
    _ "$chrome_bin" "$smoke_url" >"$allowed_output_file" 2>&1 || allowed_status=$?
  allowed_output="$(<"$allowed_output_file")"
  rm -f -- "$allowed_output_file"

  [ "$allowed_status" -eq 0 ] || sft_assert_contains "$allowed_output" "$expected_title"
  sft_assert_contains "$allowed_output" "$expected_title"
}

sft_agent_browser_chrome_bin() {
  local candidate newest=""

  shopt -s nullglob
  for candidate in "$SAFEHOUSE_HOST_HOME"/.agent-browser/browsers/chrome-*/Google\ Chrome\ for\ Testing.app/Contents/MacOS/Google\ Chrome\ for\ Testing; do
    newest="$candidate"
  done
  shopt -u nullglob

  printf '%s\n' "$newest"
}
