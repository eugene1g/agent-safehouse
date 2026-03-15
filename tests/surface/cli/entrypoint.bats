#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "--version prints the project version" {
  local expected_version
  expected_version="$(awk 'NR == 1 { sub(/\r$/, "", $0); print; exit }' "${BATS_TEST_DIRNAME}/../../../VERSION")"

  safehouse_run --version
  [ "$status" -eq 0 ]
  [ "$output" = "Agent Safehouse ${expected_version}" ]
}

@test "--help documents the primary wrapper entrypoints" {
  safehouse_run --help
  [ "$status" -eq 0 ]

  sft_assert_contains "$output" "Agent Safehouse"
  sft_assert_contains "$output" "--version"
  sft_assert_contains "$output" "--stdout"
  sft_assert_contains "$output" "--output"
}

@test "running without a command prints a generated policy path" {
  local policy_path policy_text

  safehouse_run
  [ "$status" -eq 0 ]

  policy_path="$output"
  [ -n "$policy_path" ]
  [ -f "$policy_path" ]

  policy_text="$(cat "$policy_path")"
  sft_assert_contains "$policy_text" ";; Agent Safehouse Policy (generated file)"
  sft_assert_contains "$policy_text" "(version 1)"

  rm -f "$policy_path"
}

@test "--stdout prints policy text and does not execute the wrapped command" {
  local canary
  canary="$(sft_workspace_path "stdout-canary")"

  safehouse_run --stdout -- /usr/bin/touch "$canary"
  [ "$status" -eq 0 ]

  sft_assert_contains "$output" "(version 1)"
  sft_assert_path_absent "$canary"
}

@test "--output keeps the generated policy file and still executes the wrapped command" {
  local canary output_policy
  canary="$(sft_workspace_path "output-canary")"
  output_policy="$(sft_workspace_path "generated-policy.sb")"

  safehouse_ok --output "$output_policy" -- /usr/bin/touch "$canary"

  sft_assert_file_exists "$canary"
  sft_assert_file_exists "$output_policy"
}

@test "[EXECUTION] wrapped command exit codes are preserved" {
  safehouse_run -- /bin/sh -c 'exit 6'
  [ "$status" -eq 6 ]

  safehouse_run /bin/sh -c 'exit 5'
  [ "$status" -eq 5 ]
}

@test "invalid wrapper flags fail fast" {
  safehouse_run --bogus-flag
  [ "$status" -ne 0 ]
}
