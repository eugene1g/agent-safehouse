#!/usr/bin/env bash

run_section_policy_behavior() {
  local policy_all_agents
  local policy_browser_native_messaging policy_cloud_credentials policy_onepassword
  local policy_ssh policy_spotlight policy_cleanshot

  section_begin "Feature Toggles"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits docker socket grants" "/var/run/docker.sock"
  assert_policy_contains "$POLICY_DOCKER" "--enable=docker includes docker socket grants" "/var/run/docker.sock"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits browser native messaging grants" "/NativeMessagingHosts"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Firefox native messaging grants" "/Mozilla/NativeMessagingHosts"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits extensions read grants" "/Default/Extensions"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits broad ~/.local read grant" "(home-subpath \"/.local\")"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes scoped ~/.local pipx grant" "/.local/pipx"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes scoped uv binary grant" "/.local/bin/uv"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes shared Claude agents directory grant" "/.claude/agents"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes shared Claude skills directory grant" "/.claude/skills"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes shared CLAUDE.md read grant" "/CLAUDE.md"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits aider-specific grants when no command is provided" "/.local/bin/aider-install"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits openCode-specific grants when no command is provided" "/.local/share/opentui"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes scoped pnpm XDG config grant" "/.config/pnpm"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes runtime manager proto grant" "/.proto"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes runtime manager pkgx grant" "/.pkgx"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Azure CLI grant" "/.azure"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Azure Developer CLI grant" "/.azd"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits regex 1Password socket-dir grant" "Group Containers/[A-Za-z0-9]+\\\\.com\\\\.1password/t(/.*)?$"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits regex 1Password desktop settings-dir grant" "Group Containers/[A-Za-z0-9]+\\\\.com\\\\.1password/Library/Application Support/1Password/Data/settings(/.*)?$"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits regex 1Password Homebrew Cask path grant" "/opt/homebrew/Caskroom/1password-cli(/.*)?$"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits regex 1Password Homebrew Cask data-volume path grant" "/System/Volumes/Data/opt/homebrew/Caskroom/1password-cli(/.*)?$"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits 1Password mach-lookup regex grant" "com\\.1password(\\..*)?$"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits SSH integration profile" ";; Integration: SSH"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Spotlight integration profile" ";; Integration: Spotlight"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits CleanShot integration profile" ";; Integration: CleanShot"

  policy_browser_native_messaging="${TEST_CWD}/policy-feature-browser-native-messaging.sb"
  policy_cloud_credentials="${TEST_CWD}/policy-feature-cloud-credentials.sb"
  policy_onepassword="${TEST_CWD}/policy-feature-1password.sb"
  policy_ssh="${TEST_CWD}/policy-feature-ssh.sb"
  policy_spotlight="${TEST_CWD}/policy-feature-spotlight.sb"
  policy_cleanshot="${TEST_CWD}/policy-feature-cleanshot.sb"

  assert_command_succeeds "--enable=browser-native-messaging includes browser native messaging profile" "$GENERATOR" --output "$policy_browser_native_messaging" --enable=browser-native-messaging
  assert_command_succeeds "--enable=cloud-credentials includes cloud credentials profile" "$GENERATOR" --output "$policy_cloud_credentials" --enable=cloud-credentials
  assert_command_succeeds "--enable=1password includes 1Password profile" "$GENERATOR" --output "$policy_onepassword" --enable=1password
  assert_command_succeeds "--enable=ssh includes SSH profile" "$GENERATOR" --output "$policy_ssh" --enable=ssh
  assert_command_succeeds "--enable=spotlight includes Spotlight profile" "$GENERATOR" --output "$policy_spotlight" --enable=spotlight
  assert_command_succeeds "--enable=cleanshot includes CleanShot profile" "$GENERATOR" --output "$policy_cleanshot" --enable=cleanshot

  assert_policy_contains "$policy_browser_native_messaging" "--enable=browser-native-messaging includes browser native messaging grants" "/NativeMessagingHosts"
  assert_policy_contains "$policy_browser_native_messaging" "--enable=browser-native-messaging includes Firefox native messaging grants" "/Mozilla/NativeMessagingHosts"
  assert_policy_contains "$policy_browser_native_messaging" "--enable=browser-native-messaging includes extensions read grants" "/Default/Extensions"
  assert_policy_contains "$policy_browser_native_messaging" "--enable=browser-native-messaging includes Browser Native Messaging profile marker" ";; Integration: Browser Native Messaging"

  assert_policy_contains "$policy_cloud_credentials" "--enable=cloud-credentials includes Azure CLI grant" "/.azure"
  assert_policy_contains "$policy_cloud_credentials" "--enable=cloud-credentials includes Azure Developer CLI grant" "/.azd"
  assert_policy_contains "$policy_cloud_credentials" "--enable=cloud-credentials includes Cloud Credentials profile marker" ";; Integration: Cloud Credentials"

  assert_policy_contains "$policy_onepassword" "--enable=1password includes regex 1Password socket-dir grant" "Group Containers/[A-Za-z0-9]+\\\\.com\\\\.1password/t(/.*)?$"
  assert_policy_contains "$policy_onepassword" "--enable=1password includes regex 1Password desktop settings-dir grant" "Group Containers/[A-Za-z0-9]+\\\\.com\\\\.1password/Library/Application Support/1Password/Data/settings(/.*)?$"
  assert_policy_contains "$policy_onepassword" "--enable=1password includes regex 1Password Homebrew Cask path grant" "/opt/homebrew/Caskroom/1password-cli(/.*)?$"
  assert_policy_contains "$policy_onepassword" "--enable=1password includes regex 1Password Homebrew Cask data-volume path grant" "/System/Volumes/Data/opt/homebrew/Caskroom/1password-cli(/.*)?$"
  assert_policy_contains "$policy_onepassword" "--enable=1password includes 1Password mach-lookup regex grant" "com\\.1password(\\..*)?$"
  assert_policy_contains "$policy_onepassword" "--enable=1password includes 1Password profile marker" ";; Integration: 1Password"

  assert_policy_contains "$policy_ssh" "--enable=ssh includes SSH profile marker" ";; Integration: SSH"
  assert_policy_contains "$policy_ssh" "--enable=ssh includes SSH known_hosts grant" "/.ssh/known_hosts"

  assert_policy_contains "$policy_spotlight" "--enable=spotlight includes Spotlight profile marker" ";; Integration: Spotlight"
  assert_policy_contains "$policy_spotlight" "--enable=spotlight includes Spotlight mach-lookup grant" "(global-name \"com.apple.metadata.mds\")"

  assert_policy_contains "$policy_cleanshot" "--enable=cleanshot includes CleanShot profile marker" ";; Integration: CleanShot"
  assert_policy_contains "$policy_cleanshot" "--enable=cleanshot includes CleanShot media grant" "/Library/Application Support/CleanShot/media"

  policy_all_agents="${TEST_CWD}/policy-all-agents-feature-toggle.sb"
  assert_command_succeeds "--enable=all-agents restores legacy agent-specific grants in policy mode" "$GENERATOR" --output "$policy_all_agents" --enable=all-agents
  assert_policy_contains "$policy_all_agents" "all-agents policy includes aider-install binary grant" "/.local/bin/aider-install"
  assert_policy_contains "$policy_all_agents" "all-agents policy includes opentui data grant" "/.local/share/opentui"
  assert_policy_contains "$policy_all_agents" "all-agents policy includes goose config grant" "/.config/goose"
  assert_policy_contains "$policy_all_agents" "all-agents policy includes kilocode binary grant" "/.local/bin/kilocode"
  rm -f "$policy_all_agents"

  for docker_sock in \
    "/var/run/docker.sock" \
    "/private/var/run/docker.sock" \
    "${HOME}/.docker/run/docker.sock"; do
    assert_denied_if_exists "$POLICY_DEFAULT" "docker socket access denied by default (${docker_sock})" "$docker_sock" /bin/ls "$docker_sock"
    assert_allowed_if_exists "$POLICY_DOCKER" "docker socket access allowed with --enable=docker (${docker_sock})" "$docker_sock" /bin/ls "$docker_sock"
  done

  for ext_dir in \
    "${HOME}/Library/Application Support/Google/Chrome/Default/Extensions" \
    "${HOME}/Library/Application Support/BraveSoftware/Brave-Browser/Default/Extensions" \
    "${HOME}/Library/Application Support/Arc/User Data/Default/Extensions" \
    "${HOME}/Library/Application Support/Microsoft Edge/Default/Extensions"; do
    browser_name="$(echo "$ext_dir" | sed "s|.*/Application Support/||;s|/.*||")"
    assert_denied_if_exists "$POLICY_DEFAULT" "browser extensions denied by default (${browser_name})" "$ext_dir" /bin/ls "$ext_dir"
    assert_allowed_if_exists "$policy_browser_native_messaging" "browser extensions allowed with --enable=browser-native-messaging (${browser_name})" "$ext_dir" /bin/ls "$ext_dir"
  done

  for cloud_dir in "${HOME}/.azure" "${HOME}/.azd"; do
    assert_denied_if_exists "$POLICY_DEFAULT" "cloud credential directory denied by default (${cloud_dir})" "$cloud_dir" /bin/ls "$cloud_dir"
    assert_allowed_if_exists "$policy_cloud_credentials" "cloud credential directory allowed with --enable=cloud-credentials (${cloud_dir})" "$cloud_dir" /bin/ls "$cloud_dir"
  done

  section_begin "Security Invariants"
  assert_allowed_if_exists "$POLICY_DEFAULT" "osascript execution allowed by default policy" "/usr/bin/osascript" /usr/bin/osascript -e 'return 1'

  for sensitive_path in \
    "${HOME}/Library/Application Support/Google/Chrome/Default/Cookies" \
    "${HOME}/Library/Application Support/Google/Chrome/Default/Login Data" \
    "${HOME}/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies" \
    "${HOME}/Library/Application Support/BraveSoftware/Brave-Browser/Default/Login Data" \
    "${HOME}/Library/Application Support/Arc/User Data/Default/Cookies" \
    "${HOME}/Library/Application Support/Arc/User Data/Default/Login Data" \
    "${HOME}/Library/Application Support/Microsoft Edge/Default/Cookies" \
    "${HOME}/Library/Application Support/Microsoft Edge/Default/Login Data"; do
    browser_name="$(echo "$sensitive_path" | sed "s|.*/Application Support/||;s|/.*||")"
    assert_denied_if_exists "$POLICY_DEFAULT" "read browser sensitive file denied (${browser_name})" "$sensitive_path" /bin/cat "$sensitive_path"
  done

  section_begin "Grant Merge/Precedence"
  assert_allowed_strict "$POLICY_MERGE" "read from repeated --add-dirs-ro colon-list path" /bin/cat "${TEST_RO_DIR_2}/readable2.txt"
  assert_denied_strict "$POLICY_MERGE" "write denied for read-only merged path" /usr/bin/touch "${TEST_RO_DIR_2}/should-fail.txt"
  assert_allowed_strict "$POLICY_MERGE" "write allowed for read/write merged path" /usr/bin/touch "${TEST_RW_DIR_2}/should-succeed.txt"
  assert_allowed_strict "$POLICY_MERGE" "write allowed for path with spaces" /usr/bin/touch "${TEST_SPACE_DIR}/space-write-ok.txt"
  assert_allowed_strict "$POLICY_MERGE" "read/write wins when path is in both --add-dirs-ro and --add-dirs" /usr/bin/touch "${TEST_OVERLAP_DIR}/overlap-write-ok.txt"
  assert_allowed_strict "$POLICY_MERGE" "read allowed for read-only file grant" /bin/cat "$TEST_RO_FILE"
  assert_denied_strict "$POLICY_MERGE" "write denied for read-only file grant" /bin/sh -c "echo denied >> '$TEST_RO_FILE'"
  assert_allowed_strict "$POLICY_MERGE" "read allowed for read/write file grant" /bin/cat "$TEST_RW_FILE"
  assert_allowed_strict "$POLICY_MERGE" "write allowed for read/write file grant" /bin/sh -c "echo allowed >> '$TEST_RW_FILE'"

  rm -f "$policy_browser_native_messaging" "$policy_cloud_credentials" "$policy_onepassword" "$policy_ssh" "$policy_spotlight" "$policy_cleanshot"
}

register_section run_section_policy_behavior
