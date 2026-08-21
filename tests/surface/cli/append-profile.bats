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

@test "[EXECUTION] appended profiles can target the selected workdir through shared helpers" { # https://github.com/eugene1g/agent-safehouse/issues/172
  local denied_file allowed_file profile_file result

  denied_file="$(sft_workspace_path ".env")" || return 1
  allowed_file="$(sft_workspace_path "visible.txt")" || return 1
  profile_file="$(sft_workspace_path "workdir-deny.sb")" || return 1

  printf '%s' "secret" > "$denied_file"
  printf '%s' "visible" > "$allowed_file"
  printf '%s\n' '(deny file-read* file-write* (workdir-literal "/.env"))' > "$profile_file"

  safehouse_denied --append-profile="$profile_file" -- /bin/sh -c "cat '$denied_file'"
  safehouse_denied --append-profile="$profile_file" -- /bin/sh -c "printf '%s' changed > '$denied_file'"

  result="$(safehouse_ok --append-profile="$profile_file" -- /bin/sh -c "cat '$allowed_file'")" || return 1
  [ "$result" = "visible" ]
}

@test "[EXECUTION] workdir helpers fail closed when the workdir is disabled" { # https://github.com/eugene1g/agent-safehouse/issues/172
  local profile_file
  profile_file="$(sft_workspace_path "disabled-workdir.sb")" || return 1
  printf '%s\n' '(deny file-read* (workdir-literal "/.env"))' > "$profile_file"

  safehouse_run --workdir='' --append-profile="$profile_file" -- /usr/bin/true

  [ "$status" -eq 65 ]
  sft_assert_contains "$output" "argument 1 must be: string"
}

@test "[EXECUTION] workdir helpers join paths correctly when the workdir is root" { # https://github.com/eugene1g/agent-safehouse/issues/172
  local profile_file
  profile_file="$(sft_workspace_path "root-workdir.sb")" || return 1
  printf '%s\n' '(deny file-read* (workdir-literal "/System/Library/CoreServices/SystemVersion.plist"))' > "$profile_file"

  safehouse_denied --workdir=/ --append-profile="$profile_file" -- \
    /bin/cat /System/Library/CoreServices/SystemVersion.plist
}

@test "[POLICY-ONLY] --append-profile adds deny-write rule for the profile file" {
  local profile_file resolved_profile_file profile

  profile_file="$(sft_workspace_path "protect.sb")" || return 1
  printf ';; custom-sentinel\n' > "$profile_file"

  # Safehouse canonicalizes --append-profile paths, so the emitted deny rule
  # uses the resolved path (e.g. /private/var/... on macOS). Assert against the
  # canonicalized path rather than the raw temp path.
  resolved_profile_file="$(cd "$(dirname "$profile_file")" && pwd -P)/$(basename "$profile_file")"

  profile="$(safehouse_profile --append-profile="$profile_file")"
  sft_assert_contains "$profile" "#safehouse-test-id:append-profile-protections#"
  sft_assert_contains "$profile" "(deny file-write* (literal \"${resolved_profile_file}\"))"
}

@test "[POLICY-ONLY] --allow-profile-writes suppresses the deny-write rule" {
  local profile_file profile

  profile_file="$(sft_workspace_path "noprotect.sb")" || return 1
  printf ';; custom-sentinel\n' > "$profile_file"

  profile="$(safehouse_profile --append-profile="$profile_file" --allow-profile-writes)"
  sft_assert_not_contains "$profile" "#safehouse-test-id:append-profile-protections#"
}

@test "[POLICY-ONLY] --append-profile deny rule appears after the profile content" {
  local profile_file profile sentinel

  profile_file="$(sft_workspace_path "order-check.sb")" || return 1
  sentinel=";; order-sentinel-12345"
  printf '%s\n' "$sentinel" > "$profile_file"

  profile="$(safehouse_profile --append-profile="$profile_file")"
  sft_assert_order "$profile" "order-sentinel-12345" "#safehouse-test-id:append-profile-protections#"
}
