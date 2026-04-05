#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] workdir config is ignored by default and loaded when trusted" {
  local readonly_dir writable_dir config_file
  local default_profile trusted_profile env_trusted_profile cli_false_profile

  readonly_dir="$(sft_external_dir "config-ro")" || return 1
  writable_dir="$(sft_external_dir "config-rw")" || return 1
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  printf '# SAFEHOUSE config loaded from selected workdir\nadd-dirs-ro=%s\nadd-dirs=%s\n' \
    "$readonly_dir" "$writable_dir" > "$config_file"

  default_profile="$(safehouse_profile)"
  sft_assert_not_contains "$default_profile" "$readonly_dir"
  sft_assert_not_contains "$default_profile" "$writable_dir"

  trusted_profile="$(safehouse_profile --trust-workdir-config)"
  sft_assert_contains "$trusted_profile" "$readonly_dir"
  sft_assert_contains "$trusted_profile" "$writable_dir"

  env_trusted_profile="$(SAFEHOUSE_TRUST_WORKDIR_CONFIG=1 safehouse_profile)"
  sft_assert_contains "$env_trusted_profile" "$readonly_dir"
  sft_assert_contains "$env_trusted_profile" "$writable_dir"

  cli_false_profile="$(SAFEHOUSE_TRUST_WORKDIR_CONFIG=1 safehouse_profile --trust-workdir-config=0)"
  sft_assert_not_contains "$cli_false_profile" "$readonly_dir"
  sft_assert_not_contains "$cli_false_profile" "$writable_dir"
}

@test "trusted workdir config rejects malformed lines" {
  local config_file

  config_file="$(sft_workspace_path ".safehouse")" || return 1
  printf '%s\n' 'not-a-key-value-line' > "$config_file"

  safehouse_run --trust-workdir-config --stdout
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "Invalid config line in "
  sft_assert_contains "$output" ".safehouse:1: expected key=value"
}

@test "[POLICY-ONLY] trusted workdir config is not discovered from an enclosing git repo by default" {
  local repo_root nested_dir readonly_dir profile

  sft_require_cmd_or_skip git

  repo_root="$(sft_external_dir "nested-config-repo")" || return 1
  nested_dir="${repo_root}/nested/work"
  readonly_dir="$(sft_external_dir "nested-config-ro")" || return 1

  mkdir -p "$nested_dir" || return 1
  git -C "$repo_root" init -q || return 1
  printf 'add-dirs-ro=%s\n' "$readonly_dir" > "${repo_root}/.safehouse"

  profile="$(safehouse_profile_in_dir "$nested_dir" --trust-workdir-config)"
  sft_assert_not_contains "$profile" "$readonly_dir"
}

@test "trusted workdir config rejects unknown keys" {
  local config_file

  config_file="$(sft_workspace_path ".safehouse")" || return 1
  printf '%s\n' 'allow-home=true' > "$config_file"

  safehouse_run --trust-workdir-config --stdout
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "Invalid config key in "
  sft_assert_contains "$output" ".safehouse:1: allow-home"
  sft_assert_contains "$output" "Supported keys: add-dirs-ro, add-dirs"
}

@test "[POLICY-ONLY] generated policy contains terminal deny sentinel for .safehouse writes" {
  local profile

  profile="$(safehouse_profile)"
  sft_assert_contains "$profile" "#safehouse-test-id:terminal-deny-safehouse#"
}

@test "[POLICY-ONLY] terminal deny rule appears after workdir grant" {
  local profile

  profile="$(safehouse_profile)"
  sft_assert_order "$profile" "#safehouse-test-id:workdir-grant#" "#safehouse-test-id:terminal-deny-safehouse#"
}

@test "[POLICY-ONLY] --allow-workdir-config-writes suppresses the terminal deny rule" {
  local profile

  profile="$(safehouse_profile --allow-workdir-config-writes)"
  sft_assert_not_contains "$profile" "terminal-deny-safehouse"
}
