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
  sft_assert_contains "$output" "Unknown key in workdir config: allow-home"
  sft_assert_contains "$output" "Supported keys: add-dirs-ro, add-dirs, enable, append-profile"
}

@test "[POLICY-ONLY] trusted .safehouse with enable=docker enables docker integration" {
  local config_file explain_log

  config_file="$(sft_workspace_path ".safehouse")" || return 1
  explain_log="$(sft_workspace_path "explain.log")" || return 1

  printf 'enable=docker\n' > "$config_file"

  trusted_profile="$(safehouse_profile --trust-workdir-config)"
  sft_assert_contains "$trusted_profile" "Integration: Docker"

  safehouse_ok --trust-workdir-config --explain --stdout >/dev/null 2>"$explain_log"
  sft_assert_file_contains "$explain_log" "docker"
}

@test "[POLICY-ONLY] trusted .safehouse with append-profile= appends the profile" {
  local config_file profile_file profile_dir profile

  profile_dir="$(mktemp -d "${SAFEHOUSE_WORKSPACE}/profiles.XXXXXX")" || return 1
  profile_file="${profile_dir}/custom.sb"
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  printf ';; custom-test-marker\n(allow file-read* (literal "/tmp"))\n' > "$profile_file"

  printf 'append-profile=%s\n' "$profile_file" > "$config_file"

  profile="$(safehouse_profile --trust-workdir-config)"
  sft_assert_contains "$profile" "#safehouse-test-id:workdir-config-append-profile#"
  sft_assert_contains "$profile" "custom-test-marker"
}

@test "[POLICY-ONLY] trusted .safehouse append-profile appears before --append-profile in policy" {
  local config_file workdir_profile_file cli_profile_file profile

  workdir_profile_file="$(sft_workspace_path "workdir-extra.sb")" || return 1
  cli_profile_file="$(sft_workspace_path "cli-extra.sb")" || return 1
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  printf ';; workdir-config-marker\n' > "$workdir_profile_file"
  printf ';; cli-append-marker\n' > "$cli_profile_file"

  printf 'append-profile=%s\n' "$workdir_profile_file" > "$config_file"

  profile="$(safehouse_profile --trust-workdir-config --append-profile="$cli_profile_file")"
  sft_assert_order "$profile" "#safehouse-test-id:workdir-config-append-profile#" "#safehouse-test-id:append-profile#"
}

@test "[POLICY-ONLY] untrusted .safehouse enable= is ignored" {
  local config_file profile

  config_file="$(sft_workspace_path ".safehouse")" || return 1
  printf 'enable=docker\n' > "$config_file"

  profile="$(safehouse_profile)"
  sft_assert_not_contains "$profile" "Integration: Docker"
}

@test "unknown key in .safehouse fails" {
  local config_file

  config_file="$(sft_workspace_path ".safehouse")" || return 1
  printf 'badkey=value\n' > "$config_file"

  safehouse_run --trust-workdir-config --stdout
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "Unknown key in workdir config: badkey"
}
