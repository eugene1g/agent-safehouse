#!/usr/bin/env bats
# bats file_tags=suite:surface
#
# PATH sanitization in the default (sanitized) env mode.

bats_require_minimum_version 1.5.0

load ../../test_helper.bash

# Directories runtime_build_sanitized_exec_path appends when missing, for HOME=/h.
APPENDED_DEV_PATHS="/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:/opt/homebrew/sbin:/h/.local/bin"

run_sanitize_exec_path() {
  run --separate-stderr /bin/bash -c '
    source "$1"
    runtime_build_sanitized_exec_path "$2" /h
  ' _ "${SAFEHOUSE_REPO_ROOT}/bin/lib/runtime/environment.sh" "$1"
}

# ------------------------------------------------------------------------------
# Sanitizer function

@test "absolute PATH entries are kept in order, including duplicates" {
  run_sanitize_exec_path "/b:/a:/b"
  [ "$status" -eq 0 ]
  [ "$output" = "/b:/a:/b:${APPENDED_DEV_PATHS}" ]
  [ -z "$stderr" ]
}

@test "absolute PATH entries are kept exactly as written" {
  run_sanitize_exec_path "/a//b/./c/:/d/../e:///:/."
  [ "$status" -eq 0 ]
  [ "$output" = "/a//b/./c/:/d/../e:///:/.:${APPENDED_DEV_PATHS}" ]
  [ -z "$stderr" ]
}

@test "empty PATH entries are dropped with a warning" {
  run_sanitize_exec_path ":/a::/b:"
  [ "$status" -eq 0 ]
  [ "$output" = "/a:/b:${APPENDED_DEV_PATHS}" ]
  [ "$stderr" = "$(printf '%s\n' \
    "safehouse: Dropped empty path from PATH" \
    "safehouse: Dropped empty path from PATH" \
    "safehouse: Dropped empty path from PATH")" ]
}

@test "relative PATH entries are dropped with a warning" {
  run_sanitize_exec_path "bin:/a:./x:node_modules/.bin"
  [ "$status" -eq 0 ]
  [ "$output" = "/a:${APPENDED_DEV_PATHS}" ]
  [ "$stderr" = "$(printf '%s\n' \
    "safehouse: Dropped relative path from PATH: bin" \
    "safehouse: Dropped relative path from PATH: ./x" \
    "safehouse: Dropped relative path from PATH: node_modules/.bin")" ]
}

@test "~ PATH entries are dropped with a warning" {
  run_sanitize_exec_path "~/bin:/a:~bob/bin:~"
  [ "$status" -eq 0 ]
  [ "$output" = "/a:${APPENDED_DEV_PATHS}" ]
  [ "$stderr" = "$(printf '%s\n' \
    "safehouse: Dropped ~ path from PATH: ~/bin" \
    "safehouse: Dropped ~ path from PATH: ~bob/bin" \
    "safehouse: Dropped ~ path from PATH: ~")" ]
}

@test "PATH=\"\" is one empty entry, so it is dropped and the default PATH is used" {
  run_sanitize_exec_path ""
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin:/bin:/usr/sbin:/sbin:${APPENDED_DEV_PATHS}" ]
  [ "$stderr" = "$(printf '%s\n' \
    "safehouse: Dropped empty path from PATH" \
    "safehouse: PATH had no usable entries; using default: /usr/bin:/bin:/usr/sbin:/sbin")" ]
}

@test "a PATH with no usable entries falls back to the default PATH with a warning" {
  run_sanitize_exec_path "bin:~/bin"
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/bin:/bin:/usr/sbin:/sbin:${APPENDED_DEV_PATHS}" ]
  sft_assert_contains "$stderr" "safehouse: PATH had no usable entries; using default: /usr/bin:/bin:/usr/sbin:/sbin"
}

# ------------------------------------------------------------------------------
# Env modes: only the default sanitized mode cleans PATH

@test "[EXECUTION] default sanitized mode drops a relative PATH entry with a warning" {
  run --separate-stderr safehouse_ok_env PATH="rel-bin:/usr/bin:/bin:/usr/sbin:/sbin" -- \
    -- /bin/sh -c 'printf "%s\n" "$PATH"'
  [ "$status" -eq 0 ]
  sft_assert_not_contains ":${output}:" ":rel-bin:"
  [ "${output%%:*}" = "/usr/bin" ]
  sft_assert_contains "$stderr" "safehouse: Dropped relative path from PATH: rel-bin"
}

@test "[EXECUTION] --env passes the caller PATH through unchanged" {
  run --separate-stderr safehouse_ok_env PATH="rel-bin:/usr/bin:/bin:/usr/sbin:/sbin" -- \
    --env -- /bin/sh -c 'printf "%s\n" "$PATH"'
  [ "$status" -eq 0 ]
  [ "$output" = "rel-bin:/usr/bin:/bin:/usr/sbin:/sbin" ]
  sft_assert_not_contains "$stderr" "from PATH"
}

@test "[EXECUTION] --env-pass=PATH passes the caller PATH through unchanged" {
  run --separate-stderr safehouse_ok_env PATH="rel-bin:/usr/bin:/bin:/usr/sbin:/sbin" -- \
    --env-pass=PATH -- /bin/sh -c 'printf "%s\n" "$PATH"'
  [ "$status" -eq 0 ]
  [ "$output" = "rel-bin:/usr/bin:/bin:/usr/sbin:/sbin" ]
}
