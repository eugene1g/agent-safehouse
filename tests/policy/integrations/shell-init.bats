#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=shell-init includes its optional profile source" {
  local default_profile enabled_profile

  default_profile="$(safehouse_profile)"
  enabled_profile="$(safehouse_profile --enable=shell-init)"

  sft_assert_omits_source "$default_profile" "55-integrations-optional/shell-init.sb"
  sft_assert_includes_source "$enabled_profile" "55-integrations-optional/shell-init.sb"
}

@test "[EXECUTION] zsh user startup config is only loaded when shell-init is enabled" {
  local fake_home workdir

  [ -x /bin/zsh ] || skip "zsh is not installed"

  fake_home="$(sft_fake_home)" || return 1
  workdir="$(sft_workspace_path "zsh-workdir")" || return 1
  mkdir -p "$workdir"
  printf '%s\n' 'export SAFEHOUSE_ZSH_STARTUP=loaded' > "${fake_home}/.zshrc"

  /usr/bin/env -i HOME="$fake_home" PATH="/bin:/usr/bin:/usr/sbin:/sbin" USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-${USER:-$(id -un)}}" SHELL=/bin/zsh TMPDIR=/tmp \
    /bin/zsh -i -c 'test "$SAFEHOUSE_ZSH_STARTUP" = loaded' || skip "zsh startup precheck failed outside sandbox"

  HOME="$fake_home" safehouse_denied --workdir="$workdir" -- /bin/zsh -i -c 'test "$SAFEHOUSE_ZSH_STARTUP" = loaded'

  HOME="$fake_home" safehouse_ok --workdir="$workdir" --enable=shell-init -- /bin/zsh -i -c 'test "$SAFEHOUSE_ZSH_STARTUP" = loaded'
}

@test "[EXECUTION] fish startup config is only loaded when shell-init is enabled" {
  local fish_bin fake_home workdir

  fish_bin="$(sft_command_path_or_skip fish)" || return 1

  fake_home="$(sft_fake_home)" || return 1
  workdir="$(sft_workspace_path "fish-workdir")" || return 1
  mkdir -p "${fake_home}/.config/fish" "$workdir"
  printf '%s\n' 'set -gx SAFEHOUSE_FISH_STARTUP loaded' > "${fake_home}/.config/fish/config.fish"

  /usr/bin/env -i HOME="$fake_home" PATH="$(dirname "$fish_bin"):/usr/bin:/bin:/usr/sbin:/sbin" USER="${USER:-$(id -un)}" LOGNAME="${LOGNAME:-${USER:-$(id -un)}}" SHELL="$fish_bin" TMPDIR=/tmp XDG_CONFIG_HOME="$fake_home/.config" \
    "$fish_bin" -c 'test "$SAFEHOUSE_FISH_STARTUP" = loaded' || skip "fish startup precheck failed outside sandbox"

  HOME="$fake_home" XDG_CONFIG_HOME="$fake_home/.config" safehouse_denied --workdir="$workdir" -- "$fish_bin" -c 'test "$SAFEHOUSE_FISH_STARTUP" = loaded'

  HOME="$fake_home" XDG_CONFIG_HOME="$fake_home/.config" safehouse_ok --workdir="$workdir" --enable=shell-init -- "$fish_bin" -c 'test "$SAFEHOUSE_FISH_STARTUP" = loaded'
}
