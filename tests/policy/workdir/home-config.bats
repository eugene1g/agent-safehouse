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

@test "[POLICY-ONLY] trusted-workdirs entry under a path alias still auto-trusts" {
  local trusted_workdirs_file alias_link readonly_dir config_file profile

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"
  readonly_dir="$(sft_external_dir "home-config-ro-alias")" || return 1
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  # A symlink to the workspace stands in for macOS aliases like /var -> /private/var:
  # the file stores the aliased path while the effective workdir is normalized.
  alias_link="$(sft_external_dir "home-config-alias-parent")/workdir-alias" || return 1
  ln -s "$SAFEHOUSE_WORKSPACE" "$alias_link" || return 1

  mkdir -p "$(dirname "$trusted_workdirs_file")" || return 1
  printf '%s\n' "$alias_link" > "$trusted_workdirs_file"
  printf 'add-dirs-ro=%s\n' "$readonly_dir" > "$config_file"

  profile="$(safehouse_profile)"
  sft_assert_contains "$profile" "$readonly_dir"
}

@test "[POLICY-ONLY] explain output names the trusted-workdirs file as the trust source" {
  local trusted_workdirs_file explain_log

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"
  explain_log="$(sft_workspace_path "explain-trusted.log")"

  mkdir -p "$(dirname "$trusted_workdirs_file")" || return 1
  printf '%s\n' "$SAFEHOUSE_WORKSPACE" > "$trusted_workdirs_file"

  safehouse_ok --explain --stdout >/dev/null 2>"$explain_log"

  sft_assert_file_contains "$explain_log" "workdir config trust: enabled (source: ${trusted_workdirs_file})"
}

@test "[EXECUTION] sandboxed process in a home subdir cannot write to the trusted-workdirs file" {
  local workdir trusted_workdirs_file

  workdir="${HOME}/subdir"
  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"

  mkdir -p "$workdir" || return 1
  # Pre-create the parent directory so a denied write is the only reason the
  # file cannot be created (rules out a spurious "no such directory" failure).
  mkdir -p "$(dirname "$trusted_workdirs_file")" || return 1

  # Default-deny: the workdir grant covers ~/subdir only, so a sandboxed process
  # must not be able to self-escalate trust by appending to ~/.config/safehouse.
  safehouse_denied_in_dir "$workdir" -- /bin/sh -c "printf '%s\n' '$workdir' >> '$trusted_workdirs_file'"
  sft_assert_path_absent "$trusted_workdirs_file"
}
