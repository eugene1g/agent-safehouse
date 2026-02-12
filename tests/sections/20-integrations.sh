#!/usr/bin/env bash

run_section_integrations() {
  local private_key_candidates
  local keyfile keyname browser_dir browser_name
  local ssh_config_path ssh_config_link_target
  local ssh_auth_sock
  local onepassword_group_container_dir onepassword_socket_dir onepassword_settings_file
  local onepassword_op_candidate onepassword_op_candidates
  local policy_ssh policy_browser_native_messaging policy_onepassword
  local policy_keychain_agent policy_non_keychain_agent

  section_begin "SSH Integration (Opt-In)"
  policy_ssh="${TEST_CWD}/policy-enable-ssh.sb"
  assert_command_succeeds "safehouse generates policy with --enable=ssh" "$GENERATOR" --output "$policy_ssh" --enable=ssh

  ssh_config_path="${HOME}/.ssh/config"
  if [[ -L "$ssh_config_path" ]]; then
    ssh_config_link_target="$(readlink "$ssh_config_path" 2>/dev/null || true)"
    if [[ "$ssh_config_link_target" == /* && "$ssh_config_link_target" != "${HOME}/.ssh/"* ]]; then
      assert_denied_if_exists "$POLICY_DEFAULT" "read ~/.ssh/config denied by default" "$ssh_config_path" /bin/cat "$ssh_config_path"
      log_skip "read ~/.ssh/config allowed with --enable=ssh (symlink target outside ~/.ssh; allow via --append-profile if needed)"
    else
      assert_denied_if_exists "$POLICY_DEFAULT" "read ~/.ssh/config denied by default" "$ssh_config_path" /bin/cat "$ssh_config_path"
      assert_allowed_if_exists "$policy_ssh" "read ~/.ssh/config allowed with --enable=ssh" "$ssh_config_path" /bin/cat "$ssh_config_path"
    fi
  else
    assert_denied_if_exists "$POLICY_DEFAULT" "read ~/.ssh/config denied by default" "$ssh_config_path" /bin/cat "$ssh_config_path"
    assert_allowed_if_exists "$policy_ssh" "read ~/.ssh/config allowed with --enable=ssh" "$ssh_config_path" /bin/cat "$ssh_config_path"
  fi

  assert_denied_if_exists "$POLICY_DEFAULT" "read ~/.ssh/known_hosts denied by default" "${HOME}/.ssh/known_hosts" /bin/cat "${HOME}/.ssh/known_hosts"
  assert_allowed_if_exists "$policy_ssh" "read ~/.ssh/known_hosts allowed with --enable=ssh" "${HOME}/.ssh/known_hosts" /bin/cat "${HOME}/.ssh/known_hosts"

  ssh_auth_sock="${SSH_AUTH_SOCK:-}"
  if [[ -n "$ssh_auth_sock" ]]; then
    if [[ "$ssh_auth_sock" =~ ^/private/tmp/com\.apple\.launchd\.[^/]+/Listeners$ || "$ssh_auth_sock" =~ ^/tmp/com\.apple\.launchd\.[^/]+/Listeners$ ]]; then
      assert_denied_if_exists "$POLICY_DEFAULT" "read SSH_AUTH_SOCK launchd listener denied by default" "$ssh_auth_sock" /bin/ls "$ssh_auth_sock"
      assert_allowed_if_exists "$policy_ssh" "read SSH_AUTH_SOCK launchd listener allowed with --enable=ssh" "$ssh_auth_sock" /bin/ls "$ssh_auth_sock"
    else
      log_skip "SSH_AUTH_SOCK launchd listener allow/deny test (socket path does not match launchd listener patterns)"
    fi
  else
    log_skip "SSH_AUTH_SOCK launchd listener allow/deny test (SSH_AUTH_SOCK is unset)"
  fi

  private_key_candidates=0
  for keyfile in "${HOME}"/.ssh/id_*; do
    [[ -e "$keyfile" ]] || continue
    keyname="$(basename "$keyfile")"
    if [[ "$keyname" == *.pub ]]; then
      continue
    fi

    private_key_candidates=$((private_key_candidates + 1))
    assert_denied_strict "$POLICY_DEFAULT" "read SSH private key (~/.ssh/${keyname})" /bin/cat "$keyfile"
    assert_denied_strict "$policy_ssh" "read SSH private key remains denied with --enable=ssh (~/.ssh/${keyname})" /bin/cat "$keyfile"
  done

  if [[ "$private_key_candidates" -eq 0 ]]; then
    log_skip "SSH private key deny tests (no private key files found in ~/.ssh/)"
  fi

  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits SSH integration profile" ";; Integration: SSH"
  assert_policy_contains "$policy_ssh" "--enable=ssh includes SSH integration profile" ";; Integration: SSH"

  section_begin "Browser Profile Deny (Default Policy)"
  for browser_dir in \
    "${HOME}/Library/Application Support/Google/Chrome/Default" \
    "${HOME}/Library/Application Support/BraveSoftware/Brave-Browser/Default" \
    "${HOME}/Library/Application Support/Arc/User Data/Default" \
    "${HOME}/Library/Application Support/Microsoft Edge/Default"; do
    browser_name="$(echo "$browser_dir" | sed "s|.*/Application Support/||;s|/.*||")"
    assert_denied_if_exists "$POLICY_DEFAULT" "read browser profile root denied (${browser_name})" "$browser_dir" /bin/ls "$browser_dir"
  done

  section_begin "Browser Native Messaging and 1Password Integrations (Opt-In)"
  policy_browser_native_messaging="${TEST_CWD}/policy-enable-browser-native-messaging.sb"
  policy_onepassword="${TEST_CWD}/policy-enable-1password.sb"
  assert_command_succeeds "safehouse generates policy with --enable=browser-native-messaging" "$GENERATOR" --output "$policy_browser_native_messaging" --enable=browser-native-messaging
  assert_command_succeeds "safehouse generates policy with --enable=1password" "$GENERATOR" --output "$policy_onepassword" --enable=1password

  assert_denied_if_exists "$POLICY_DEFAULT" "read Firefox native messaging hosts dir denied by default" "${HOME}/Library/Application Support/Mozilla/NativeMessagingHosts" /bin/ls "${HOME}/Library/Application Support/Mozilla/NativeMessagingHosts"
  assert_allowed_if_exists "$policy_browser_native_messaging" "read Firefox native messaging hosts dir allowed with --enable=browser-native-messaging" "${HOME}/Library/Application Support/Mozilla/NativeMessagingHosts" /bin/ls "${HOME}/Library/Application Support/Mozilla/NativeMessagingHosts"
  onepassword_group_container_dir="$(find "${HOME}/Library/Group Containers" -mindepth 1 -maxdepth 1 -type d -name "*.com.1password" 2>/dev/null | head -n 1 || true)"
  if [[ -n "$onepassword_group_container_dir" ]]; then
    onepassword_socket_dir="${onepassword_group_container_dir}/t"
    onepassword_settings_file="${onepassword_group_container_dir}/Library/Application Support/1Password/Data/settings/settings.json"
    assert_denied_if_exists "$POLICY_DEFAULT" "read 1Password socket directory denied by default" "$onepassword_socket_dir" /bin/ls "$onepassword_socket_dir"
    assert_allowed_if_exists "$policy_onepassword" "read 1Password socket directory allowed with --enable=1password" "$onepassword_socket_dir" /bin/ls "$onepassword_socket_dir"
    assert_denied_if_exists "$POLICY_DEFAULT" "read 1Password desktop settings metadata denied by default" "$onepassword_settings_file" /usr/bin/stat "$onepassword_settings_file"
    assert_allowed_if_exists "$policy_onepassword" "read 1Password desktop settings metadata allowed with --enable=1password" "$onepassword_settings_file" /usr/bin/stat "$onepassword_settings_file"
  else
    log_skip "read 1Password socket directory (matching Group Container not found)"
  fi
  assert_denied_if_exists "$POLICY_DEFAULT" "access 1Password SSH agent socket symlink denied by default" "${HOME}/.1password/agent.sock" /bin/ls "${HOME}/.1password/agent.sock"
  assert_allowed_if_exists "$policy_onepassword" "access 1Password SSH agent socket symlink allowed with --enable=1password" "${HOME}/.1password/agent.sock" /bin/ls "${HOME}/.1password/agent.sock"

  onepassword_op_candidates=0
  for onepassword_op_candidate in \
    /opt/homebrew/Caskroom/1password-cli/*/op \
    /System/Volumes/Data/opt/homebrew/Caskroom/1password-cli/*/op \
    /usr/local/Caskroom/1password-cli/*/op \
    /System/Volumes/Data/usr/local/Caskroom/1password-cli/*/op; do
    [[ -e "$onepassword_op_candidate" ]] || continue
    onepassword_op_candidates=$((onepassword_op_candidates + 1))
    assert_allowed_strict "$policy_onepassword" "read Homebrew Cask 1Password CLI binary allowed with --enable=1password (${onepassword_op_candidate})" /usr/bin/stat "$onepassword_op_candidate"
  done
  if [[ "$onepassword_op_candidates" -eq 0 ]]; then
    log_skip "read Homebrew Cask 1Password CLI binary (no 1password-cli Cask install found)"
  fi
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Browser Native Messaging integration profile" ";; Integration: Browser Native Messaging"
  assert_policy_contains "$policy_browser_native_messaging" "--enable=browser-native-messaging includes Browser Native Messaging integration profile" ";; Integration: Browser Native Messaging"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits 1Password integration profile" ";; Integration: 1Password"
  assert_policy_contains "$policy_onepassword" "--enable=1password includes 1Password integration profile" ";; Integration: 1Password"

  section_begin "macOS GUI / Electron Integration Policy Coverage"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits macOS GUI integration profile" ";; Integration: macOS GUI"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits electron integration profile" "#safehouse-test-id:electron-integration#"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy does not load agent-specific Claude Desktop profile when no command is provided" "(preference-domain \"com.anthropic.claudefordesktop\")"

  assert_policy_contains "$POLICY_MACOS_GUI" "--enable=macos-gui includes macOS GUI integration profile" ";; Integration: macOS GUI"
  assert_policy_contains "$POLICY_MACOS_GUI" "--enable=macos-gui includes CARenderServer mach-lookup grant" "(global-name \"com.apple.CARenderServer\")"
  assert_policy_contains "$POLICY_MACOS_GUI" "--enable=macos-gui includes usymptomsd mach-lookup grant" "(global-name \"com.apple.usymptomsd\")"
  assert_policy_contains "$POLICY_MACOS_GUI" "--enable=macos-gui includes inputmethodkit launchagent mach-lookup grant" "(global-name \"com.apple.inputmethodkit.launchagent\")"
  assert_policy_contains "$POLICY_MACOS_GUI" "--enable=macos-gui includes inputmethodkit launcher mach-lookup grant" "(global-name \"com.apple.inputmethodkit.launcher\")"
  assert_policy_contains "$POLICY_MACOS_GUI" "--enable=macos-gui includes inputmethodkit xpc endpoint mach-lookup grant" "(global-name \"com.apple.inputmethodkit.getxpcendpoint\")"
  assert_policy_contains "$POLICY_MACOS_GUI" "--enable=macos-gui includes Sidecar relay mach-lookup grant" "(global-name \"com.apple.sidecar-relay\")"
  assert_policy_not_contains "$POLICY_MACOS_GUI" "--enable=macos-gui does not include electron integration profile" "#safehouse-test-id:electron-integration#"

  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron includes electron integration marker" "#safehouse-test-id:electron-integration#"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron includes electron GPU/Metal marker" "#safehouse-test-id:electron-gpu-metal#"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron includes electron crashpad marker" "#safehouse-test-id:electron-crashpad#"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron includes electron crashpad mach-lookup marker" "#safehouse-test-id:electron-crashpad-lookup#"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron includes electron crashpad mach-register marker" "#safehouse-test-id:electron-crashpad-register#"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron includes no-sandbox workaround docs" "Primary workaround under Safehouse: launch Electron with --no-sandbox."
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron includes MTLCompilerService mach-lookup grant" "(global-name \"com.apple.MTLCompilerService\")"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron includes IOSurfaceRootUserClient IOKit grant" "(iokit-user-client-class \"IOSurfaceRootUserClient\")"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron includes AGXDeviceUserClient IOKit grant" "(iokit-user-client-class \"AGXDeviceUserClient\")"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron includes crashpad handshake regex grant" "(global-name-regex #\"^org\\.chromium\\.crashpad\\.child_port_handshake\\.\")"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron implies macOS GUI integration profile" ";; Integration: macOS GUI"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron implies CARenderServer mach-lookup grant via macOS GUI profile" "(global-name \"com.apple.CARenderServer\")"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron implies usymptomsd mach-lookup grant via macOS GUI profile" "(global-name \"com.apple.usymptomsd\")"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron implies inputmethodkit launchagent mach-lookup grant via macOS GUI profile" "(global-name \"com.apple.inputmethodkit.launchagent\")"
  assert_policy_contains "$POLICY_ELECTRON" "--enable=electron implies Sidecar relay mach-lookup grant via macOS GUI profile" "(global-name \"com.apple.sidecar-relay\")"

  section_begin "Keychain Access"
  policy_keychain_agent="${TEST_CWD}/policy-agent-keychain-codex.sb"
  policy_non_keychain_agent="${TEST_CWD}/policy-agent-no-keychain-aider.sb"

  assert_command_succeeds "safehouse generates command-scoped policy for keychain-enabled codex profile" "$SAFEHOUSE" --stdout --output "$policy_keychain_agent" -- codex --version
  assert_command_succeeds "safehouse generates command-scoped policy for non-keychain aider profile" "$SAFEHOUSE" --stdout --output "$policy_non_keychain_agent" -- aider --version

  assert_denied_if_exists "$POLICY_DEFAULT" "security find-certificate denied by default (no baseline keychain access)" "security" /usr/bin/security find-certificate -a
  assert_denied_if_exists "$policy_non_keychain_agent" "security find-certificate denied for non-keychain agent profile" "security" /usr/bin/security find-certificate -a
  assert_denied_if_exists "$policy_keychain_agent" "security find-certificate remains denied when keychain integration module is not injected" "security" /usr/bin/security find-certificate -a

  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits keychain integration profile" ";; Integration: Keychain"
  assert_policy_not_contains "$policy_keychain_agent" "keychain-enabled agent policy omits shared keychain integration profile" ";; Integration: Keychain"
  assert_policy_not_contains "$policy_non_keychain_agent" "non-keychain agent policy omits keychain integration profile" ";; Integration: Keychain"
  assert_policy_not_contains "$policy_keychain_agent" "keychain policy omits broad home Library metadata grant" "(home-subpath \"/Library\")"
  assert_policy_contains "$policy_keychain_agent" "keychain-enabled agent profile provides keychain write path grant" "(home-subpath \"/Library/Keychains\")"
  assert_policy_contains "$policy_keychain_agent" "keychain-enabled agent profile provides scoped security preferences grant" "(home-literal \"/Library/Preferences/com.apple.security.plist\")"

  rm -f "$policy_ssh" "$policy_browser_native_messaging" "$policy_onepassword" "$policy_keychain_agent" "$policy_non_keychain_agent"
}

register_section run_section_integrations
