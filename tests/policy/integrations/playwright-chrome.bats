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
