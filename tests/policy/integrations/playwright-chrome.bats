#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Playwright Chrome integration checks.
#
load ../../test_helper.bash

@test "[POLICY-ONLY] enable=playwright-chrome includes its metadata profile and chromium dependencies" { # https://github.com/eugene1g/agent-safehouse/issues/28 https://github.com/eugene1g/agent-safehouse/issues/25
  local profile
  profile="$(safehouse_profile --enable=playwright-chrome)"

  sft_assert_includes_source "$profile" "55-integrations-optional/playwright-chrome.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/chromium-full.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/chromium-headless.sb"
}

@test "[EXECUTION] playwright-chrome lets Playwright launch Chrome and capture a screenshot" {
  local playwright_bin playwright_runtime_root precheck_png allowed_png

  playwright_bin="$(sft_command_path_or_skip playwright)"
  playwright_runtime_root="$(playwright_runtime_root "$playwright_bin")"
  precheck_png="$(sft_workspace_path "playwright-chrome-precheck.png")"
  allowed_png="$(sft_workspace_path "playwright-chrome-allowed.png")"

  HOME="$SAFEHOUSE_HOST_HOME" "$playwright_bin" screenshot --channel=chrome https://example.com "$precheck_png" >/dev/null 2>&1 ||
    skip "Playwright Chrome precheck failed outside sandbox"

  # The underlying denial path is already covered by chromium-full's bare-Safehouse
  # launch smoke. Reproducing it through Playwright triggers the macOS crash report
  # dialog for Chrome on local developer machines.
  safehouse_ok_env \
    "HOME=$SAFEHOUSE_HOST_HOME" \
    -- \
    --add-dirs-ro="$playwright_runtime_root" \
    --enable=playwright-chrome \
    -- "$playwright_bin" screenshot --channel=chrome https://example.com "$allowed_png" >/dev/null
  sft_assert_file_exists "$allowed_png"
}

playwright_runtime_root() {
  local playwright_bin="$1"
  local bin_dir

  bin_dir="$(dirname "$playwright_bin")"
  if [[ "$(basename "$bin_dir")" == "bin" ]]; then
    dirname "$bin_dir"
    return 0
  fi

  printf '%s\n' "$bin_dir"
}
