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

@test "[POLICY-ONLY] shell-init allows Homebrew GUI-app completion symlink targets" { # https://github.com/eugene1g/agent-safehouse/issues/67
  local default_profile enabled_profile

  default_profile="$(safehouse_profile)"
  enabled_profile="$(safehouse_profile --enable=shell-init)"

  sft_assert_not_contains "$default_profile" '(regex #"^/Applications/[^/]+\.app/Contents/Resources(/[^/]+)*/(_[^/]+|[^/]+\.(bash|fish|zsh)|[^/]+\.(bash|fish|zsh)-completion)$")'
  sft_assert_contains "$enabled_profile" '(literal "/Applications")'
  sft_assert_contains "$enabled_profile" '(literal "/System/Volumes/Data/Applications")'
  sft_assert_contains "$enabled_profile" '(regex #"^/Applications/[^/]+\.app/Contents/Resources(/[^/]+)*/(_[^/]+|[^/]+\.(bash|fish|zsh)|[^/]+\.(bash|fish|zsh)-completion)$")'
  sft_assert_contains "$enabled_profile" '(regex #"^/System/Volumes/Data/Applications/[^/]+\.app/Contents/Resources(/[^/]+)*/(_[^/]+|[^/]+\.(bash|fish|zsh)|[^/]+\.(bash|fish|zsh)-completion)$")'
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

@test "[EXECUTION] shell-init can follow Homebrew-style completion symlinks when the resolved target is granted" { # https://github.com/eugene1g/agent-safehouse/issues/67
  local fake_home workdir external_root target_dir target_file source_dir symlink_path profile_file

  [ -x /bin/zsh ] || skip "zsh is not installed"

  fake_home="$(sft_fake_home)" || return 1
  workdir="$(sft_workspace_path "completion-symlink-workdir")" || return 1
  external_root="$(sft_external_dir "completion-symlink-target")" || return 1
  target_dir="${external_root}/Fake.app/Contents/Resources/etc"
  target_file="${target_dir}/docker.zsh-completion"
  source_dir="${workdir}/site-functions"
  symlink_path="${source_dir}/_docker"
  profile_file="$(sft_workspace_path "completion-symlink-grant.sb")" || return 1

  mkdir -p "$source_dir" "$target_dir"
  printf 'fpath=("%s" $fpath)\nautoload -Uz compinit\ncompinit -D\n' "$source_dir" > "${fake_home}/.zshrc"
  printf '#compdef docker\n_docker() { :; }\n' > "$target_file"
  /bin/ln -sf "$target_file" "$symlink_path"

  safehouse_run_env HOME="$fake_home" -- --enable=shell-init --workdir="$workdir" -- /bin/zsh -i -c 'true'
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "operation not permitted: ${symlink_path}"

  printf '(allow file-read* (subpath "%s"))\n' "${external_root}/Fake.app/Contents/Resources" > "$profile_file"

  safehouse_run_env HOME="$fake_home" -- --enable=shell-init --append-profile="$profile_file" --workdir="$workdir" -- /bin/zsh -i -c 'true'
  [ "$status" -eq 0 ]
  sft_assert_not_contains "$output" "operation not permitted: ${symlink_path}"
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
