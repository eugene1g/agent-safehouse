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
    source "$1/bin/lib/support/collections.sh"
    source "$1/bin/lib/runtime/environment.sh"
    runtime_build_sanitized_exec_path "$2" /h
  ' _ "${SAFEHOUSE_REPO_ROOT}" "$1"
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

# ------------------------------------------------------------------------------
# Sandboxed lookup probe (stubbed): drops entries that lookups fail through with EPERM

# Like run_sanitize_exec_path, but replaces the sandboxed probe with a stub that
# reports "denied" for paths containing "denied" or equal to /opt/homebrew/sbin,
# and "ok" otherwise (as it does for missing directories).
# Set PROBE_MODE=fail to make the probe itself fail.
run_sanitize_exec_path_with_stub_probe() {
  run --separate-stderr /bin/bash -c '
    source "$1/bin/lib/support/collections.sh"
    source "$1/bin/lib/runtime/environment.sh"
    runtime_probe_exec_path_dirs() {
      local dir
      shift
      runtime_exec_path_probe_results=()
      [ "$PROBE_MODE" != fail ] || return 1
      for dir in "$@"; do
        case "$dir" in
          *denied* | /opt/homebrew/sbin) runtime_exec_path_probe_results+=(denied) ;;
          *) runtime_exec_path_probe_results+=(ok) ;;
        esac
      done
    }
    runtime_build_sanitized_exec_path "$2" /h /stub/policy.sb
  ' _ "${SAFEHOUSE_REPO_ROOT}" "$1"
}

@test "sandbox-denied PATH entries are dropped with a warning; missing ones are kept" {
  PROBE_MODE=ok run_sanitize_exec_path_with_stub_probe "/a/missing:/b:/c/denied:/d"
  [ "$status" -eq 0 ]
  [ "$output" = "/a/missing:/b:/d:/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:/h/.local/bin" ]
  [ "$stderr" = "safehouse: Dropped sandbox-denied path from PATH: /c/denied" ]
}

@test "sandbox-denied appended common dev paths are dropped without a warning" {
  PROBE_MODE=ok run_sanitize_exec_path_with_stub_probe "/a"
  [ "$status" -eq 0 ]
  [ "$output" = "/a:/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:/h/.local/bin" ]
  [ -z "$stderr" ]
}

@test "a sandbox-denied common dev path that the caller listed is dropped with a warning" {
  PROBE_MODE=ok run_sanitize_exec_path_with_stub_probe "/a:/opt/homebrew/sbin"
  [ "$status" -eq 0 ]
  [ "$output" = "/a:/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:/h/.local/bin" ]
  [ "$stderr" = "safehouse: Dropped sandbox-denied path from PATH: /opt/homebrew/sbin" ]
}

@test "a PATH whose entries are all sandbox-denied keeps only the appended common dev paths" {
  # The default-PATH fallback applies only when no absolute entries remain
  # before the sandboxed lookup check.
  PROBE_MODE=ok run_sanitize_exec_path_with_stub_probe "/denied1:/denied2"
  [ "$status" -eq 0 ]
  [ "$output" = "/usr/local/bin:/usr/local/sbin:/opt/homebrew/bin:/h/.local/bin" ]
  [ "$stderr" = "$(printf '%s\n' \
    "safehouse: Dropped sandbox-denied path from PATH: /denied1" \
    "safehouse: Dropped sandbox-denied path from PATH: /denied2")" ]
}

@test "PATH entries are kept unchecked with a warning when the sandboxed probe fails" {
  PROBE_MODE=fail run_sanitize_exec_path_with_stub_probe "/a/denied:/b"
  [ "$status" -eq 0 ]
  [ "$output" = "/a/denied:/b:${APPENDED_DEV_PATHS}" ]
  [ "$stderr" = "safehouse: Could not check for unreadable PATH directories inside the sandbox" ]
}

# ------------------------------------------------------------------------------
# Sandboxed lookup probe (real)

@test "[EXECUTION] default sanitized mode keeps a missing PATH directory, which lookups skip with ENOENT" {
  local missing_dir="${SAFEHOUSE_WORKSPACE}/does-not-exist"

  run --separate-stderr safehouse_ok_env PATH="${missing_dir}:/usr/bin:/bin:/usr/sbin:/sbin" -- \
    -- /bin/sh -c 'printf "%s\n" "$PATH"'
  [ "$status" -eq 0 ]
  [ "${output%%:*}" = "$missing_dir" ]
  sft_assert_not_contains "$stderr" "from PATH"
}

@test "[EXECUTION] default sanitized mode keeps a plain sandbox-denied PATH directory, which lookups skip with ENOENT" {
  local denied_dir
  denied_dir="$(sft_external_dir "path-denied")"

  run --separate-stderr safehouse_ok_env PATH="${denied_dir}:/usr/bin:/bin:/usr/sbin:/sbin" -- \
    -- /bin/sh -c 'printf "%s\n" "$PATH"'
  [ "$status" -eq 0 ]
  [ "${output%%:*}" = "$denied_dir" ]
  sft_assert_not_contains "$stderr" "from PATH"
}

@test "[EXECUTION] default sanitized mode keeps a PATH directory granted by --add-dirs-ro" {
  local granted_dir
  granted_dir="$(sft_external_dir "path-granted")"

  run --separate-stderr safehouse_ok_env PATH="${granted_dir}:/usr/bin:/bin:/usr/sbin:/sbin" -- \
    --add-dirs-ro="$granted_dir" -- /bin/sh -c 'printf "%s\n" "$PATH"'
  [ "$status" -eq 0 ]
  [ "${output%%:*}" = "$granted_dir" ]
  sft_assert_not_contains "$stderr" "from PATH"
}

@test "[EXECUTION] the test environment's PATH launches without PATH warnings" {
  # Guards sft_isolate_path_from_host_home in test_helper.bash. Host-home PATH
  # entries are denied under the fake HOME, and warnings for any dropped ones
  # would leak into every test that captures stderr.
  run --separate-stderr safehouse_ok -- /usr/bin/true
  [ "$status" -eq 0 ]
  sft_assert_not_contains "$stderr" "from PATH"
}

# A PATH entry that is a symlink in a denied location makes every PATH lookup
# through it fail with EPERM, since resolving the link is itself denied. libuv
# stops its PATH search there. This is the shape that reproduces #205.
create_denied_symlink_to_usr_bin() {
  local denied_dir
  denied_dir="$(sft_external_dir "path-denied-symlink")" || return 1
  ln -s /usr/bin "${denied_dir}/bin" || return 1
  printf '%s\n' "${denied_dir}/bin"
}

NODE_SPAWN_LS='const r = require("child_process").spawnSync("ls", ["-d", "/"]); console.log(r.error ? r.error.code : "ok")'

@test "[EXECUTION] a denied symlink first in an unsanitized PATH breaks Node's PATH search (#205 repro)" {
  local node_bin link
  sft_command_path_or_skip node_bin node
  link="$(create_denied_symlink_to_usr_bin)"

  # --env-pass=PATH skips sanitization, so this shows the unfixed behavior. If
  # this stops failing, the fixture no longer reproduces #205 and the next test
  # proves nothing.
  run --separate-stderr safehouse_ok_env HOME="$SAFEHOUSE_HOST_HOME" PATH="${link}:/usr/bin:/bin" -- \
    --env-pass=PATH -- "$node_bin" -e "$NODE_SPAWN_LS"
  [ "$status" -eq 0 ]
  [ "$output" = "EPERM" ]
}

@test "[EXECUTION] a denied symlink first in the caller PATH is dropped, so Node's PATH search works" { # https://github.com/eugene1g/agent-safehouse/issues/205
  local node_bin link
  sft_command_path_or_skip node_bin node
  link="$(create_denied_symlink_to_usr_bin)"

  run --separate-stderr safehouse_ok_env HOME="$SAFEHOUSE_HOST_HOME" PATH="${link}:/usr/bin:/bin" -- \
    -- "$node_bin" -e "$NODE_SPAWN_LS"
  [ "$status" -eq 0 ]
  [ "$output" = "ok" ]
  sft_assert_contains "$stderr" "safehouse: Dropped sandbox-denied path from PATH: ${link}"
}

# ------------------------------------------------------------------------------
