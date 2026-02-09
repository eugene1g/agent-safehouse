#!/usr/bin/env bash

run_section_integrations() {
  local private_key_candidates

  section_begin "SSH Key Protection"
  assert_allowed_if_exists "$POLICY_DEFAULT" "read ~/.ssh/config" "${HOME}/.ssh/config" /bin/cat "${HOME}/.ssh/config"
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
