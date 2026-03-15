#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] chromium-headless and chromium-full keep their intended dependency boundaries" {
  local headless_profile full_profile

  headless_profile="$(safehouse_profile --enable=chromium-headless)"
  full_profile="$(safehouse_profile --enable=chromium-full)"

  sft_assert_includes_source "$headless_profile" "55-integrations-optional/chromium-headless.sb"
  sft_assert_omits_source "$headless_profile" "55-integrations-optional/agent-browser.sb"

  sft_assert_includes_source "$full_profile" "55-integrations-optional/chromium-full.sb"
  sft_assert_includes_source "$full_profile" "55-integrations-optional/chromium-headless.sb"
  sft_assert_omits_source "$full_profile" "55-integrations-optional/agent-browser.sb"
}

@test "[EXECUTION] chromium-full can launch Google Chrome headless against example.com when Chrome is installed" {
  local chrome_bin
  local -a chrome_args

  chrome_bin="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
  [ -x "$chrome_bin" ] || skip "Google Chrome is not installed"
  # Bats runs with a fake HOME by default. Force Chrome to use its mock
  # keychain backend so the test stays non-interactive and does not require
  # real host keychain access.
  chrome_args=(--use-mock-keychain --no-sandbox --headless=new --dump-dom https://example.com)

  "$chrome_bin" "${chrome_args[@]}" >/dev/null 2>&1 || skip "Google Chrome headless precheck failed outside sandbox"

  safehouse_denied -- "$chrome_bin" "${chrome_args[@]}"

  run safehouse_ok --enable=chromium-full -- "$chrome_bin" "${chrome_args[@]}"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Example Domain"
}

@test "[EXECUTION] chromium-headless can launch Playwright chrome-headless-shell against example.com when installed" {
  local headless_shell
  local -a headless_args

  headless_shell="$(sft_playwright_headless_shell)"
  [ -n "$headless_shell" ] || skip "Playwright chrome-headless-shell is not installed"

  headless_args=(--no-sandbox --headless --dump-dom https://example.com)

  HOME="$SAFEHOUSE_HOST_HOME" "$headless_shell" "${headless_args[@]}" >/dev/null 2>&1 || skip "chrome-headless-shell precheck failed outside sandbox"

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_denied -- "$headless_shell" "${headless_args[@]}"

  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok --enable=chromium-headless -- "$headless_shell" "${headless_args[@]}"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Example Domain"
}

sft_playwright_headless_shell() {
  local cache_root candidate newest=""

  cache_root="${SAFEHOUSE_HOST_HOME}/Library/Caches/ms-playwright"

  shopt -s nullglob
  for candidate in "$cache_root"/chromium_headless_shell-*/chrome-headless-shell-mac-*/chrome-headless-shell; do
    newest="$candidate"
  done
  shopt -u nullglob

  printf '%s\n' "$newest"
}
