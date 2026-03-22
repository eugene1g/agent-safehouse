#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

make_fake_opencode_bootstrap() {
  local path="$1"

  mkdir -p "$(dirname "$path")" || return 1
  cat >"$path" <<'EOF'
#!/bin/sh
set -eu

config="${XDG_CONFIG_HOME:-$HOME/.config}/opencode"
cache="${XDG_CACHE_HOME:-$HOME/.cache}/opencode"
data="${XDG_DATA_HOME:-$HOME/.local/share}/opencode"
state="${XDG_STATE_HOME:-$HOME/.local/state}/opencode"

mkdir -p "$config" "$cache" "$data" "$state"
printf '{}\n' >"$config/opencode.json"
printf 'cache\n' >"$cache/ok"
printf 'data\n' >"$data/ok"
printf 'state\n' >"$state/ok"
EOF
  chmod 755 "$path" || return 1
}

@test "[POLICY-ONLY] opencode resolves symlinked home-scoped config targets" {
  local fake_home fake_opencode target_dir policy

  fake_home="$(sft_fake_home)" || return 1
  fake_opencode="${fake_home}/.local/bin/opencode"
  target_dir="${fake_home}/.dotfiles/.config/opencode"

  mkdir -p "${fake_home}/.config" "$target_dir" || return 1
  /bin/ln -sf ../.dotfiles/.config/opencode "${fake_home}/.config/opencode"
  sft_make_fake_command "$fake_opencode"

  policy="$(HOME="$fake_home" safehouse_profile -- "$fake_opencode")"

  sft_assert_contains "$policy" "$(sft_source_marker "60-agents/opencode.sb")"
  sft_assert_contains "$policy" "Resolved target for home-scoped file-read* file-write* path from profiles/60-agents/opencode.sb: ${fake_home}/.config/opencode -> ${target_dir}"
  sft_assert_contains "$policy" "(subpath \"${target_dir}\")"
}

@test "[EXECUTION] opencode profile can bootstrap XDG paths when config dir is symlinked" {
  local fake_home workdir fake_opencode target_dir

  fake_home="$(sft_fake_home)" || return 1
  workdir="${fake_home}/sites/test"
  fake_opencode="${fake_home}/.local/bin/opencode"
  target_dir="${fake_home}/.dotfiles/.config/opencode"

  mkdir -p \
    "$workdir" \
    "${fake_home}/.config" \
    "${fake_home}/.cache" \
    "${fake_home}/.local" \
    "${fake_home}/.local/share" \
    "${fake_home}/.local/state" \
    "$target_dir" || return 1
  /bin/ln -sf ../.dotfiles/.config/opencode "${fake_home}/.config/opencode"
  make_fake_opencode_bootstrap "$fake_opencode" || return 1

  HOME="$fake_home" safehouse_ok_in_dir "$workdir" -- "$fake_opencode"

  [ -f "${target_dir}/opencode.json" ]
  [ -f "${fake_home}/.cache/opencode/ok" ]
  [ -f "${fake_home}/.local/share/opencode/ok" ]
  [ -f "${fake_home}/.local/state/opencode/ok" ]
}
