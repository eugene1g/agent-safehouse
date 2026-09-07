#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

# Run a command under safehouse with an explicit HOME and CWD.
onepassword_run() {
  local home="$1" cwd="$2"
  shift 2

  ( cd "$cwd" && HOME="$home" "$DIST_SAFEHOUSE" "$@" )
}

@test "[POLICY-ONLY] enable=1password includes its optional profile source" {
  local profile
  profile="$(safehouse_profile --enable=1password)"

  sft_assert_includes_source "$profile" "55-integrations-optional/1password.sb"
}

@test "1Password socket and settings paths are denied by default and allowed when enabled" {
  local fake_home group_root socket_file settings_file symlink_path

  fake_home="$(sft_fake_home)" || return 1
  group_root="${fake_home}/Library/Group Containers/ABCD1234.com.1password"
  socket_file="${group_root}/t/agent.sock"
  settings_file="${group_root}/Library/Application Support/1Password/Data/settings/settings.json"

  mkdir -p "$(dirname "$socket_file")" "$(dirname "$settings_file")"
  printf '%s\n' "socket" > "$socket_file"
  printf '%s\n' "{}" > "$settings_file"

  HOME="$fake_home" safehouse_denied -- /usr/bin/stat "$socket_file"

  HOME="$fake_home" safehouse_denied -- /usr/bin/stat "$settings_file"

  HOME="$fake_home" safehouse_ok --enable=1password -- /usr/bin/stat "$socket_file" >/dev/null
  HOME="$fake_home" safehouse_ok --enable=1password -- /usr/bin/stat "$settings_file" >/dev/null
}

@test "[POLICY-ONLY] enable=1password allows network-outbound connect() to the SSH agent socket" { # https://github.com/eugene1g/agent-safehouse/issues/139
  local grant

  grant='(allow network-outbound
    (remote unix-socket (path-regex (string-append "^" HOME_DIR "/Library/Group Containers/[A-Za-z0-9]+\\.com\\.1password/t/agent\\.sock$"))))'
  sft_assert_contains "$(safehouse_profile --enable=1password)" "$grant"

  sft_assert_not_contains "$(safehouse_profile)" "com.1password"
}

@test "[EXECUTION] 1Password SSH agent socket connect() is denied by default and allowed with enable=1password" { # https://github.com/eugene1g/agent-safehouse/issues/139
  local fake_home socket_dirpath listener_pid

  fake_home="$(sft_fake_home)" || return 1
  socket_dirpath="${fake_home}/Library/Group Containers/ABCD1234.com.1password/t"
  mkdir -p "$socket_dirpath"

  # Create listening UNIX socket
  # NOTE: The absolute socket path exceeds the macOS UNIX socket pathname limit (104 bytes).
  #       Workaround by connecting with a short relative socket path.
  ( cd "$socket_dirpath" && exec nc -lkU agent.sock ) &
  listener_pid=$!
  sleep 0.3

  # Ensure connect fails inside the sandbox by default
  run onepassword_run "$fake_home" "$socket_dirpath" \
    -- nc -w5 -U agent.sock </dev/null
  local default_status="$status"

  # Ensure connect succeeds inside the sandbox when --enable=1password used
  run onepassword_run "$fake_home" "$socket_dirpath" --enable=1password \
    -- nc -w5 -U agent.sock </dev/null
  local enabled_status="$status"

  # Cleanup
  kill "$listener_pid" 2>/dev/null || true
  wait "$listener_pid" 2>/dev/null || true

  [ "$default_status" -ne 0 ]
  [ "$enabled_status" -eq 0 ]
}

@test "[EXECUTION] 1Password CLI binary can launch when installed" {
  local op_bin

  sft_command_path_or_skip op_bin op

  "$op_bin" --version >/dev/null 2>&1 || skip "op precheck failed outside sandbox"

  safehouse_ok --enable=1password -- "$op_bin" --version >/dev/null
}

@test "[POLICY-ONLY] 1Password grants read access to the app bundle for op-ssh-sign" {
  local enabled base

  enabled="$(safehouse_profile --enable=1password)"
  sft_assert_contains "$enabled" '(subpath "/Applications/1Password.app")'

  base="$(safehouse_profile)"
  sft_assert_not_contains "$base" "/Applications/1Password.app"
}

@test "[EXECUTION] 1Password app bundle (op-ssh-sign) is denied by default and readable when enabled" {
  local signer="/Applications/1Password.app/Contents/MacOS/op-ssh-sign"

  [ -f "$signer" ] || skip "1Password app / op-ssh-sign not installed"

  safehouse_denied -- /usr/bin/stat "$signer"

  safehouse_ok --enable=1password -- /usr/bin/stat "$signer" >/dev/null
}
