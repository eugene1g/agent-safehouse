#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

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
  symlink_path="${fake_home}/.1password/agent.sock"

  mkdir -p "$(dirname "$socket_file")" "$(dirname "$settings_file")" "$(dirname "$symlink_path")"
  printf '%s\n' "socket" > "$socket_file"
  printf '%s\n' "{}" > "$settings_file"
  /bin/ln -sf "$socket_file" "$symlink_path"

  HOME="$fake_home" safehouse_denied -- /usr/bin/stat "$socket_file"

  HOME="$fake_home" safehouse_denied -- /usr/bin/stat "$settings_file"

  HOME="$fake_home" safehouse_denied -- /bin/ls "$symlink_path"

  HOME="$fake_home" safehouse_ok --enable=1password -- /usr/bin/stat "$socket_file" >/dev/null
  HOME="$fake_home" safehouse_ok --enable=1password -- /usr/bin/stat "$settings_file" >/dev/null
  HOME="$fake_home" safehouse_ok --enable=1password -- /bin/ls "$symlink_path" >/dev/null
}

@test "[EXECUTION] 1Password CLI binary can launch when installed" {
  local op_bin

  op_bin="$(sft_command_path_or_skip op)" || return 1

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
