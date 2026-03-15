#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=browser-native-messaging includes its optional profile source" {
  local profile
  profile="$(safehouse_profile --enable=browser-native-messaging)"

  sft_assert_includes_source "$profile" "55-integrations-optional/browser-native-messaging.sb"
}

@test "browser native messaging paths stay denied by default and become readable when enabled" {
  local fake_home chrome_ext_dir firefox_hosts_dir

  fake_home="$(sft_fake_home)" || return 1
  chrome_ext_dir="${fake_home}/Library/Application Support/Google/Chrome/Default/Extensions"
  firefox_hosts_dir="${fake_home}/Library/Application Support/Mozilla/NativeMessagingHosts"
  mkdir -p "$chrome_ext_dir" "$firefox_hosts_dir"
  printf '%s\n' "{}" > "${firefox_hosts_dir}/com.safehouse.json"

  HOME="$fake_home" safehouse_denied -- /bin/ls "$chrome_ext_dir"

  HOME="$fake_home" safehouse_denied -- /bin/ls "$firefox_hosts_dir"

  HOME="$fake_home" safehouse_ok --enable=browser-native-messaging -- /bin/ls "$chrome_ext_dir" >/dev/null
  HOME="$fake_home" safehouse_ok --enable=browser-native-messaging -- /bin/ls "$firefox_hosts_dir" >/dev/null
}

@test "browser native messaging still keeps cookies and login data denied when enabled" {
  local fake_home profile_root cookies_file login_file

  fake_home="$(sft_fake_home)" || return 1
  profile_root="${fake_home}/Library/Application Support/Google/Chrome/Default"
  cookies_file="${profile_root}/Cookies"
  login_file="${profile_root}/Login Data"

  mkdir -p "$profile_root"
  printf '%s\n' "cookie" > "$cookies_file"
  printf '%s\n' "login" > "$login_file"

  HOME="$fake_home" safehouse_denied --enable=browser-native-messaging -- /bin/cat "$cookies_file"
  HOME="$fake_home" safehouse_denied --enable=browser-native-messaging -- /bin/cat "$login_file"
}
