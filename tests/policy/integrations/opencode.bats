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

make_fake_opencode_exec() {
  mkdir -p "$(dirname "$1")"
  printf '#!/bin/sh\nexec "$@"\n' >"$1"
  chmod 755 "$1"
}

@test "[EXECUTION] opencode can read existing config discovery entries outside the workdir" {
  local fake_home fake_opencode parent workdir name
  fake_home="$(sft_fake_home)"
  fake_opencode="${fake_home}/.local/bin/opencode"
  parent="${fake_home}/projects"
  workdir="${parent}/repo"
  mkdir -p "$workdir" "${fake_home}/.claude"
  make_fake_opencode_exec "$fake_opencode"

  HOME="$fake_home" safehouse_ok_in_dir "$workdir" -- "$fake_opencode" /bin/ls "${fake_home}/.claude"
  for name in .claude .agents .opencode; do
    mkdir -p "${parent}/${name}"
    HOME="$fake_home" safehouse_ok_in_dir "$workdir" -- "$fake_opencode" /bin/ls "${parent}/${name}"
  done
  for name in opencode.json opencode.jsonc; do
    printf '{}\n' >"${parent}/${name}"
    HOME="$fake_home" safehouse_ok_in_dir "$workdir" -- "$fake_opencode" /bin/cat "${parent}/${name}"
  done
}

@test "[EXECUTION] opencode discovery grants do not expose directory contents or writes" {
  local fake_home fake_opencode parent workdir name
  fake_home="$(sft_fake_home)"
  fake_opencode="${fake_home}/.local/bin/opencode"
  parent="${fake_home}/projects"
  workdir="${parent}/repo"
  mkdir -p "$workdir"
  make_fake_opencode_exec "$fake_opencode"

  for name in .claude .agents .opencode; do
    mkdir -p "${parent}/${name}"
    printf 'private fixture\n' >"${parent}/${name}/private.txt"
    HOME="$fake_home" safehouse_denied_in_dir "$workdir" -- "$fake_opencode" /bin/cat "${parent}/${name}/private.txt"
    HOME="$fake_home" safehouse_denied_in_dir "$workdir" -- "$fake_opencode" /bin/sh -c 'echo changed > "$1"' sh "${parent}/${name}/private.txt"
  done
  for name in opencode.json opencode.jsonc; do
    printf '{}\n' >"${parent}/${name}"
    HOME="$fake_home" safehouse_denied_in_dir "$workdir" -- "$fake_opencode" /bin/sh -c 'echo changed > "$1"' sh "${parent}/${name}"
  done
  printf 'private fixture\n' >"${parent}/opencode.json.backup"
  HOME="$fake_home" safehouse_denied_in_dir "$workdir" -- "$fake_opencode" /bin/cat "${parent}/opencode.json.backup"
  HOME="$fake_home" safehouse_denied_in_dir "$workdir" -- /bin/cat "${parent}/opencode.json"
}
