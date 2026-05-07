#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "--always-trust-workdir-config writes workdir to trusted-workdirs file" {
  local trusted_workdirs_file

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"

  safehouse_ok --always-trust-workdir-config --stdout >/dev/null

  sft_assert_file_exists "$trusted_workdirs_file"
  sft_assert_file_contains "$trusted_workdirs_file" "$SAFEHOUSE_WORKSPACE"
}

@test "--always-trust-workdir-config creates the file and parent dirs if they do not exist" {
  local trusted_workdirs_file

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"

  [ ! -e "$trusted_workdirs_file" ]

  safehouse_ok --always-trust-workdir-config --stdout >/dev/null

  sft_assert_file_exists "$trusted_workdirs_file"
}

@test "--always-trust-workdir-config is idempotent (running twice does not duplicate)" {
  local trusted_workdirs_file count

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"

  safehouse_ok --always-trust-workdir-config --stdout >/dev/null
  safehouse_ok --always-trust-workdir-config --stdout >/dev/null

  count="$(grep -cF "$SAFEHOUSE_WORKSPACE" "$trusted_workdirs_file" || true)"
  [ "$count" -eq 1 ]
}

@test "--always-trust-workdir-config enables trust for the current invocation" {
  local trusted_workdirs_file readonly_dir config_file profile

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"
  readonly_dir="$(sft_external_dir "always-trust-ro")" || return 1
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  printf 'add-dirs-ro=%s\n' "$readonly_dir" > "$config_file"

  profile="$(safehouse_profile --always-trust-workdir-config)"

  sft_assert_contains "$profile" "$readonly_dir"
  sft_assert_file_exists "$trusted_workdirs_file"
  sft_assert_file_contains "$trusted_workdirs_file" "$SAFEHOUSE_WORKSPACE"
}

@test "--always-trust-workdir-config with --trust-workdir-config=false conflicts" {
  safehouse_run --always-trust-workdir-config --trust-workdir-config=false --stdout
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "--trust-workdir-config=false conflicts with --always-trust-workdir-config=true"
}

@test "--trust-workdir-config=false with --always-trust-workdir-config conflicts regardless of order" {
  safehouse_run --trust-workdir-config=false --always-trust-workdir-config --stdout
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "--trust-workdir-config=false conflicts with --always-trust-workdir-config=true"
}

@test "--always-trust-workdir-config conflicts with all falsy values of --trust-workdir-config" {
  local falsy_val

  for falsy_val in 0 no off; do
    safehouse_run --always-trust-workdir-config "--trust-workdir-config=${falsy_val}" --stdout
    [ "$status" -ne 0 ] || {
      printf 'expected conflict error for --trust-workdir-config=%s\n' "$falsy_val" >&2
      return 1
    }
    sft_assert_contains "$output" "--trust-workdir-config=false conflicts with --always-trust-workdir-config=true"
  done
}

@test "--always-trust-workdir-config with --trust-workdir-config (bare) is allowed" {
  safehouse_run --always-trust-workdir-config --trust-workdir-config --stdout
  [ "$status" -eq 0 ]
}

@test "--always-trust-workdir-config with --trust-workdir-config=true is allowed" {
  safehouse_run --always-trust-workdir-config --trust-workdir-config=true --stdout
  [ "$status" -eq 0 ]
}

@test "[POLICY-ONLY] --always-trust-workdir-config=false removes workdir from trusted file and disables trust" {
  local trusted_workdirs_file readonly_dir config_file profile

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"
  readonly_dir="$(sft_external_dir "always-trust-false-ro")" || return 1
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  mkdir -p "$(dirname "$trusted_workdirs_file")" || return 1
  printf '%s\n' "$SAFEHOUSE_WORKSPACE" > "$trusted_workdirs_file"
  printf 'add-dirs-ro=%s\n' "$readonly_dir" > "$config_file"

  profile="$(safehouse_profile --always-trust-workdir-config=false)"
  sft_assert_not_contains "$profile" "$readonly_dir"

  # Workdir should have been removed from the file
  if [ -f "$trusted_workdirs_file" ]; then
    local file_content
    file_content="$(cat "$trusted_workdirs_file")"
    sft_assert_not_contains "$file_content" "$SAFEHOUSE_WORKSPACE"
  fi
}

@test "[POLICY-ONLY] --always-trust-workdir-config=false with --trust-workdir-config trusts this session but removes from file" {
  local trusted_workdirs_file readonly_dir config_file profile

  trusted_workdirs_file="${HOME}/.config/safehouse/trusted-workdirs"
  readonly_dir="$(sft_external_dir "always-trust-false-session-ro")" || return 1
  config_file="$(sft_workspace_path ".safehouse")" || return 1

  mkdir -p "$(dirname "$trusted_workdirs_file")" || return 1
  printf '%s\n' "$SAFEHOUSE_WORKSPACE" > "$trusted_workdirs_file"
  printf 'add-dirs-ro=%s\n' "$readonly_dir" > "$config_file"

  profile="$(safehouse_profile --always-trust-workdir-config=false --trust-workdir-config)"
  sft_assert_contains "$profile" "$readonly_dir"

  # Workdir should have been removed from the file
  if [ -f "$trusted_workdirs_file" ]; then
    local file_content
    file_content="$(cat "$trusted_workdirs_file")"
    sft_assert_not_contains "$file_content" "$SAFEHOUSE_WORKSPACE"
  fi
}
