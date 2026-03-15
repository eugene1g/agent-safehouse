#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[EXECUTION] default sandbox can fork and exec subprocesses" {
  safehouse_ok -- /bin/sh -c 'echo sandbox-ok'
}

@test "[EXECUTION] default sandbox allows nested subprocess execution" {
  safehouse_ok -- /bin/sh -c '/bin/sh -c "echo nested-ok"'
}

@test "[EXECUTION] wrapper preserves sandboxed command stderr" {
  local stdout_file stderr_file

  stdout_file="$(sft_workspace_path "stdout.txt")"
  stderr_file="$(sft_workspace_path "stderr.txt")"

  safehouse_ok -- /bin/sh -c 'printf "%s\n" stdout; printf "%s\n" stderr >&2' >"$stdout_file" 2>"$stderr_file"

  sft_assert_file_content "$stdout_file" "stdout"
  sft_assert_file_content "$stderr_file" "stderr"
}

@test "[EXECUTION] default sandbox allows outbound https" {
  safehouse_ok -- /usr/bin/curl -sf --max-time 5 https://example.com
}
