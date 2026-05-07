#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] trusted-workdirs file causes workdir config to be auto-trusted" {
  local trusted_workdirs_file readonly_dir config_file profile

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"
  readonly_dir="$(sft_external_dir "home-config-ro")" || return 1
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  mkdir -p "$(dirname "$trusted_workdirs_file")" || return 1
  printf '%s\n' "$SAFEHOUSE_WORKSPACE" > "$trusted_workdirs_file"
  printf 'add-dirs-ro=%s\n' "$readonly_dir" > "$config_file"

  profile="$(safehouse_profile)"
  sft_assert_contains "$profile" "$readonly_dir"
}

@test "[POLICY-ONLY] trusted-workdirs file with non-matching path does NOT auto-trust" {
  local trusted_workdirs_file other_dir readonly_dir config_file profile

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"
  other_dir="$(sft_external_dir "home-config-other")" || return 1
  readonly_dir="$(sft_external_dir "home-config-ro-no-trust")" || return 1
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  mkdir -p "$(dirname "$trusted_workdirs_file")" || return 1
  printf '%s\n' "$other_dir" > "$trusted_workdirs_file"
  printf 'add-dirs-ro=%s\n' "$readonly_dir" > "$config_file"

  profile="$(safehouse_profile)"
  sft_assert_not_contains "$profile" "$readonly_dir"
}

@test "[POLICY-ONLY] CLI --trust-workdir-config=0 overrides trusted-workdirs file auto-trust" {
  local trusted_workdirs_file readonly_dir config_file profile

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"
  readonly_dir="$(sft_external_dir "home-config-ro-override")" || return 1
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  mkdir -p "$(dirname "$trusted_workdirs_file")" || return 1
  printf '%s\n' "$SAFEHOUSE_WORKSPACE" > "$trusted_workdirs_file"
  printf 'add-dirs-ro=%s\n' "$readonly_dir" > "$config_file"

  profile="$(safehouse_profile --trust-workdir-config=0)"
  sft_assert_not_contains "$profile" "$readonly_dir"
}

@test "[POLICY-ONLY] trusted-workdirs file supports blank lines and # comments" {
  local trusted_workdirs_file readonly_dir config_file profile

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"
  readonly_dir="$(sft_external_dir "home-config-ro-comments")" || return 1
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  mkdir -p "$(dirname "$trusted_workdirs_file")" || return 1
  printf '# This is a comment\n\n%s\n\n# Another comment\n' "$SAFEHOUSE_WORKSPACE" > "$trusted_workdirs_file"
  printf 'add-dirs-ro=%s\n' "$readonly_dir" > "$config_file"

  profile="$(safehouse_profile)"
  sft_assert_contains "$profile" "$readonly_dir"
}

@test "[POLICY-ONLY] trusted-workdirs file explain output shows loaded entries" {
  local trusted_workdirs_file explain_log

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"
  explain_log="$(sft_workspace_path "explain-trusted.log")"

  mkdir -p "$(dirname "$trusted_workdirs_file")" || return 1
  printf '%s\n' "$SAFEHOUSE_WORKSPACE" > "$trusted_workdirs_file"

  safehouse_ok --explain --stdout >/dev/null 2>"$explain_log"

  sft_assert_file_contains "$explain_log" "$trusted_workdirs_file"
}
