#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=1password includes its optional profile source" {
  local profile
  profile="$(safehouse_profile --enable=1password)"

  sft_assert_includes_source "$profile" "55-integrations-optional/1password.sb"
}

@test "1Password desktop settings paths are denied by default and allowed when enabled" {
  local fake_home group_root settings_file

  fake_home="$(sft_fake_home)" || return 1
  group_root="${fake_home}/Library/Group Containers/ABCD1234.com.1password"
  settings_file="${group_root}/Library/Application Support/1Password/Data/settings/settings.json"

  mkdir -p "$(dirname "$settings_file")"
  printf '%s\n' "{}" > "$settings_file"

  HOME="$fake_home" safehouse_denied -- /usr/bin/stat "$settings_file"

  HOME="$fake_home" safehouse_ok --enable=1password -- /usr/bin/stat "$settings_file" >/dev/null
}

@test "1Password SSH agent socket paths are readable with enable=1password but not broadened by enable=ssh alone" {
  local fake_home group_root socket_file symlink_path

  fake_home="$(sft_fake_home)" || return 1
  group_root="${fake_home}/Library/Group Containers/ABCD1234.com.1password"
  socket_file="${group_root}/t/agent.sock"
  symlink_path="${fake_home}/.1password/agent.sock"

  mkdir -p "$(dirname "$socket_file")" "$(dirname "$symlink_path")"
  printf '%s\n' "socket" > "$socket_file"
  /bin/ln -sf "$socket_file" "$symlink_path"

  HOME="$fake_home" safehouse_denied -- /usr/bin/stat "$socket_file"
  HOME="$fake_home" safehouse_denied --enable=ssh -- /usr/bin/stat "$socket_file"
  HOME="$fake_home" safehouse_ok --enable=1password -- /usr/bin/stat "$socket_file" >/dev/null
  HOME="$fake_home" safehouse_denied -- /bin/ls "$symlink_path"
  HOME="$fake_home" safehouse_denied --enable=ssh -- /bin/ls "$symlink_path"
  HOME="$fake_home" safehouse_ok --enable=1password -- /bin/ls "$symlink_path" >/dev/null
}

@test "[EXECUTION] 1Password CLI binary can launch when installed" {
  local op_bin

  op_bin="$(sft_command_path_or_skip op)" || return 1

  "$op_bin" --version >/dev/null 2>&1 || skip "op precheck failed outside sandbox"

  safehouse_ok --enable=1password -- "$op_bin" --version >/dev/null
}
