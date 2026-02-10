#!/usr/bin/env bash

run_section_integrations() {
  local private_key_candidates
  local ssh_config_path ssh_config_link_target

  section_begin "SSH Key Protection"
  ssh_config_path="${HOME}/.ssh/config"
  if [[ -L "$ssh_config_path" ]]; then
    ssh_config_link_target="$(readlink "$ssh_config_path" 2>/dev/null || true)"
    if [[ "$ssh_config_link_target" == /* && "$ssh_config_link_target" != "${HOME}/.ssh/"* ]]; then
      log_skip "read ~/.ssh/config (symlink target outside ~/.ssh; allow via --append-profile if needed)"
    else
      assert_allowed_if_exists "$POLICY_DEFAULT" "read ~/.ssh/config" "$ssh_config_path" /bin/cat "$ssh_config_path"
    fi
  else
    assert_allowed_if_exists "$POLICY_DEFAULT" "read ~/.ssh/config" "$ssh_config_path" /bin/cat "$ssh_config_path"
  fi

  assert_allowed_if_exists "$POLICY_DEFAULT" "read ~/.ssh/known_hosts" "${HOME}/.ssh/known_hosts" /bin/cat "${HOME}/.ssh/known_hosts"

  private_key_candidates=0
  for keyfile in "${HOME}"/.ssh/id_*; do
    [[ -e "$keyfile" ]] || continue
    keyname="$(basename "$keyfile")"
    if [[ "$keyname" == *.pub ]]; then
      continue
    fi

    private_key_candidates=$((private_key_candidates + 1))
    assert_denied_strict "$POLICY_DEFAULT" "read SSH private key (~/.ssh/${keyname})" /bin/cat "$keyfile"
  done

  if [[ "$private_key_candidates" -eq 0 ]]; then
    log_skip "SSH private key deny tests (no private key files found in ~/.ssh/)"
  fi

  section_begin "Browser Profile Deny (Default Policy)"
  for browser_dir in \
    "${HOME}/Library/Application Support/Google/Chrome/Default" \
    "${HOME}/Library/Application Support/BraveSoftware/Brave-Browser/Default" \
    "${HOME}/Library/Application Support/Arc/User Data/Default" \
    "${HOME}/Library/Application Support/Microsoft Edge/Default"; do
    browser_name="$(echo "$browser_dir" | sed "s|.*/Application Support/||;s|/.*||")"
    assert_denied_if_exists "$POLICY_DEFAULT" "read browser profile root denied (${browser_name})" "$browser_dir" /bin/ls "$browser_dir"
  done

  section_begin "macOS GUI / Electron Integration Policy Coverage"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits macOS GUI integration profile" ";; Integration: macOS GUI"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits electron integration profile" "#safehouse-test-id:electron-integration#"

  assert_policy_contains "$POLICY_MACOS_GUI" "--enable=macos-gui includes macOS GUI integration profile" ";; Integration: macOS GUI"
  assert_policy_contains "$POLICY_MACOS_GUI" "--enable=macos-gui includes CARenderServer mach-lookup grant" "(global-name \"com.apple.CARenderServer\")"
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

  section_begin "Keychain Access"
  assert_allowed_if_exists "$POLICY_DEFAULT" "security find-certificate" "security" /usr/bin/security find-certificate -a
  assert_allowed_if_exists "$POLICY_DEFAULT" "read keychain metadata" "${HOME}/Library/Keychains/login.keychain-db" /usr/bin/stat "${HOME}/Library/Keychains/login.keychain-db"
  assert_policy_not_contains "$POLICY_DEFAULT" "keychain policy omits broad home Library metadata grant" "(home-subpath \"/Library\")"
  assert_policy_contains "$POLICY_DEFAULT" "keychain policy includes scoped home Library root metadata grant" "(home-literal \"/Library\")"
  assert_policy_contains "$POLICY_DEFAULT" "keychain policy includes scoped user keychain metadata grant" "(home-literal \"/Library/Keychains\")"
  assert_policy_contains "$POLICY_DEFAULT" "keychain policy includes scoped Data-volume Library root metadata grant" "(data-home-literal \"/Library\")"
  assert_policy_contains "$POLICY_DEFAULT" "keychain policy includes scoped user security preferences grant" "(home-literal \"/Library/Preferences/com.apple.security.plist\")"
}

register_section run_section_integrations
