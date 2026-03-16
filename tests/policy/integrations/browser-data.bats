#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Browser-sensitive data boundary checks.
#
load ../../test_helper.bash

@test "[POLICY-ONLY] default profile denies browser cookie and login data access" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_not_contains "$profile" '"Cookies"'
}

@test "browser profile roots stay denied by default to generic file reads" {
  local fake_home profile_root

  fake_home="$(sft_fake_home)" || return 1
  profile_root="${fake_home}/Library/Application Support/Google/Chrome/Default"
  mkdir -p "$profile_root"

  HOME="$fake_home" safehouse_denied -- /bin/ls "$profile_root"
}

@test "browser cookies and login data files stay denied by default at runtime" {
  local fake_home profile_root cookies_file login_file

  fake_home="$(sft_fake_home)" || return 1
  profile_root="${fake_home}/Library/Application Support/Google/Chrome/Default"
  cookies_file="${profile_root}/Cookies"
  login_file="${profile_root}/Login Data"

  mkdir -p "$profile_root"
  printf '%s\n' "cookie" > "$cookies_file"
  printf '%s\n' "login" > "$login_file"

  HOME="$fake_home" safehouse_denied -- /bin/cat "$cookies_file"

  HOME="$fake_home" safehouse_denied -- /bin/cat "$login_file"
}

@test "browser cookies and login data files stay denied when chromium and Playwright integrations are enabled" {
  local fake_home profile_root cookies_file login_file

  fake_home="$(sft_fake_home)" || return 1
  profile_root="${fake_home}/Library/Application Support/Google/Chrome/Default"
  cookies_file="${profile_root}/Cookies"
  login_file="${profile_root}/Login Data"

  mkdir -p "$profile_root"
  printf '%s\n' "cookie" > "$cookies_file"
  printf '%s\n' "login" > "$login_file"

  HOME="$fake_home" safehouse_denied --enable=chromium-headless -- /bin/cat "$cookies_file"
  HOME="$fake_home" safehouse_denied --enable=chromium-headless -- /bin/cat "$login_file"
  HOME="$fake_home" safehouse_denied --enable=chromium-full -- /bin/cat "$cookies_file"
  HOME="$fake_home" safehouse_denied --enable=chromium-full -- /bin/cat "$login_file"
  HOME="$fake_home" safehouse_denied --enable=playwright-chrome -- /bin/cat "$cookies_file"
  HOME="$fake_home" safehouse_denied --enable=playwright-chrome -- /bin/cat "$login_file"
  HOME="$fake_home" safehouse_denied --enable=agent-browser -- /bin/cat "$cookies_file"
  HOME="$fake_home" safehouse_denied --enable=agent-browser -- /bin/cat "$login_file"
}
