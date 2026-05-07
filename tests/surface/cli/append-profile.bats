#!/usr/bin/env bats
# bats file_tags=suite:surface
#
# Append-profile custom rules.
# Verifies that --append-profile injects custom sandbox rules and that
# those rules grant access at runtime.
#
load ../../test_helper.bash

@test "[POLICY-ONLY] appended profile content appears in generated profile text" { # https://github.com/eugene1g/agent-safehouse/issues/15
  local profile_file profile

  profile_file="$(sft_workspace_path "inspect.sb")" || return 1
  printf ';; custom-sentinel-for-append-test\n' > "$profile_file"

  profile="$(safehouse_profile --append-profile="$profile_file")"
  sft_assert_contains "$profile" "custom-sentinel-for-append-test"
  sft_assert_order "$profile" "#safehouse-test-id:workdir-grant#" "custom-sentinel-for-append-test"
}

@test "[POLICY-ONLY] multiple appended profiles are all included in the profile" { # https://github.com/eugene1g/agent-safehouse/issues/15
  local profile_a profile_b profile

  profile_a="$(sft_workspace_path "profile-a.sb")" || return 1
  profile_b="$(sft_workspace_path "profile-b.sb")" || return 1

  printf ';; marker-alpha\n(allow file-read* (literal "/tmp/marker-alpha"))\n' > "$profile_a"
  printf ';; marker-beta\n(allow file-read* (literal "/tmp/marker-beta"))\n' > "$profile_b"

  profile="$(safehouse_profile --append-profile="$profile_a" --append-profile="$profile_b")"
  sft_assert_contains "$profile" "marker-alpha"
  sft_assert_contains "$profile" "marker-beta"
  sft_assert_order "$profile" "marker-alpha" "marker-beta"
}

@test "[EXECUTION] append-profile grants read access to an otherwise-denied path" { # https://github.com/eugene1g/agent-safehouse/issues/15
  local target_dir target_file profile_file result

  target_dir="$(sft_external_dir "append-target")" || return 1
  target_file="${target_dir}/secret.txt"
  profile_file="$(sft_workspace_path "custom-grant.sb")" || return 1

  printf '%s' "classified" > "$target_file"

  safehouse_denied -- /bin/sh -c "cat '$target_file'"

  printf '(allow file-read* (subpath "%s"))\n' "$target_dir" > "$profile_file"

  result="$(safehouse_ok --append-profile="$profile_file" -- /bin/sh -c "cat '$target_file'")" || return 1
  [ "$result" = "classified" ]
}

@test "[EXECUTION] append-profile grants write access to an otherwise-denied path" { # https://github.com/eugene1g/agent-safehouse/issues/15
  local target_dir target_file profile_file

  target_dir="$(sft_external_dir "append-write")" || return 1
  target_file="${target_dir}/output.txt"
  profile_file="$(sft_workspace_path "write-grant.sb")" || return 1

  printf '(allow file-read* file-write* (subpath "%s"))\n' "$target_dir" > "$profile_file"

  safehouse_ok --append-profile="$profile_file" \
    -- /bin/sh -c "printf '%s' granted > '$target_file'"
  sft_assert_file_content "$target_file" "granted"
}

@test "[POLICY-ONLY] --append-profile adds deny-write rule for the profile file" {
  local profile_file profile

  profile_file="$(sft_workspace_path "protect.sb")" || return 1
  printf ';; custom-sentinel\n' > "$profile_file"

  profile="$(safehouse_profile --append-profile="$profile_file")"
  sft_assert_contains "$profile" "#safehouse-test-id:append-profile-protections#"
  sft_assert_contains "$profile" "(deny file-write* (literal \"${profile_file}\"))"
}

@test "[POLICY-ONLY] --allow-profile-writes suppresses the deny-write rule" {
  local profile_file profile

  profile_file="$(sft_workspace_path "noprotect.sb")" || return 1
  printf ';; custom-sentinel\n' > "$profile_file"

  profile="$(safehouse_profile --append-profile="$profile_file" --allow-profile-writes)"
  sft_assert_not_contains "$profile" "append-profile-protections"
}

@test "[POLICY-ONLY] --append-profile deny rule appears after the profile content" {
  local profile_file profile sentinel

  profile_file="$(sft_workspace_path "order-check.sb")" || return 1
  sentinel=";; order-sentinel-12345"
  printf '%s\n' "$sentinel" > "$profile_file"

  profile="$(safehouse_profile --append-profile="$profile_file")"
  sft_assert_order "$profile" "order-sentinel-12345" "#safehouse-test-id:append-profile-protections#"
}
