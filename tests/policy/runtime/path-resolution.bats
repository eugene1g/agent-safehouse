#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

path_resolution_run() {
  run /bin/bash -eu -c '
    ROOT_DIR="$1"
    source "$ROOT_DIR/bin/lib/bootstrap/source-manifest.sh"
    for lib in "${SAFEHOUSE_LIB_SOURCE_MANIFEST[@]}"; do
      source "$ROOT_DIR/bin/lib/$lib"
    done
    test_root="$(cd "$SAFEHOUSE_WORKSPACE" && pwd -P)"
    touch "$test_root/target-one"
    mkdir "$test_root/target-two"
    ln -s "$test_root/target-one" "$test_root/one"
    ln -s "$test_root/target-one" "$test_root/alias"
    ln -s "$test_root/target-two" "$test_root/two"
    policy_render_emit_resolved_builtin_path_rule() {
      printf "%s|%s|%s|%s\n" "$2" "$3" "$4" "$5"
    }
    policy_render_emit_resolved_home_path_rule() {
      printf "%s|%s|%s|%s\n" "$2" "$3" "$4" "$5"
    }
    home_profile="$(printf "%s\n" \
      "(allow file-read*" \
      "    (home-literal \"/one\")" \
      "    (home-prefix \"/two\")" \
      "    (home-literal \"/alias\")" \
      "    (home-subpath \"/missing\")" \
      "    (home-literal \"/target-one\")" \
      ")" \
      "(allow file-read* file-write*" \
      "    (home-subpath \"/one\")" \
      ")" \
      "(deny file-write*" \
      "    (home-subpath \"/two\")" \
      ")")"
    eval "$2"
  ' _ "$SAFEHOUSE_REPO_ROOT" "$1"
}

@test "shared batch resolver clears empty results and rejects invalid output array names" {
  path_resolution_run '
    realpath() { echo unexpected-realpath >&2; return 1; }
    resolved=(stale)
    safehouse_resolve_paths_batch resolved
    [[ "${#resolved[@]}" -eq 0 ]]
    if safehouse_resolve_paths_batch "not-an-array" "$test_root/one"; then exit 1; fi
  '
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Invalid collection variable name"
  sft_assert_not_contains "$output" "unexpected-realpath"
}

@test "shared batch resolver preserves empty slots and unchanged paths on fallback" {
  path_resolution_run '
    realpath() {
      if [[ "$#" -gt 1 ]]; then
        return 1
      fi
      [[ "$1" != "$test_root/one" ]] || return 1
      command /bin/realpath "$@"
    }
    resolved=(stale)
    safehouse_resolve_paths_batch resolved "$test_root/one" "$test_root/two" "$test_root/target-one"
    [[ "${#resolved[@]}" -eq 3 ]]
    [[ -z "${resolved[0]}" ]]
    [[ "${resolved[1]}" == "$test_root/target-two" ]]
    [[ "${resolved[2]}" == "$test_root/target-one" ]]
  '
  [ "$status" -eq 0 ]
}

@test "shared batch resolver rejects malformed batches even when result counts match" {
  path_resolution_run '
    realpath() {
      printf "%s\n" "$#" >> "$test_root/calls"
      if [[ "$#" -gt 1 ]]; then
        printf "%s\n" "$invalid_result" "$test_root/target-two"
        return 0
      fi
      command /bin/realpath "$@"
    }
    for invalid_result in relative-path "$(printf "/invalid\tpath")"; do
      : > "$test_root/calls"
      safehouse_resolve_paths_batch resolved "$test_root/one" "$test_root/two"
      [[ "$(cat "$test_root/calls")" == "$(printf "2\n1\n1")" ]]
      [[ "${#resolved[@]}" -eq 2 ]]
      [[ "${resolved[0]}" == "$test_root/target-one" ]]
      [[ "${resolved[1]}" == "$test_root/target-two" ]]
    done
  '
  [ "$status" -eq 0 ]
}

@test "home rules share batching while preserving operations, matchers, order, and deduplication" {
  path_resolution_run '
    policy_req_home_dir="$test_root"
    realpath() {
      printf "%s\n" "$#" >> "$test_root/calls"
      command /bin/realpath "$@"
    }
    policy_render_emit_resolved_home_path_rules profiles/any-agent.sb "$home_profile" > "$test_root/rules"
    [[ "$(cat "$test_root/calls")" == 5 ]]
    expected="$(printf "%s\n" \
      "file-read*|literal|$test_root/one|$test_root/target-one" \
      "file-read*|prefix|$test_root/two|$test_root/target-two" \
      "file-read* file-write*|subpath|$test_root/one|$test_root/target-one")"
    [[ "$(cat "$test_root/rules")" == "$expected" ]]
  '
  [ "$status" -eq 0 ]
}

@test "home batching uses the current HOME and current symlink destinations on each call" {
  path_resolution_run '
    mkdir "$test_root/other-home"
    ln -s "$test_root/target-two" "$test_root/other-home/one"
    for policy_req_home_dir in "$test_root" "$test_root/other-home"; do
      policy_render_emit_resolved_home_path_rules profiles/any-integration.sb "$home_profile" > "$test_root/rules"
      if [[ "$policy_req_home_dir" == "$test_root" ]]; then
        expected="file-read*|literal|$test_root/one|$test_root/target-one"
      else
        expected="file-read*|literal|$test_root/other-home/one|$test_root/target-two"
      fi
      [[ "$(head -n 1 "$test_root/rules")" == "$expected" ]]
    done
    ln -sfn "$test_root/target-one" "$test_root/other-home/one"
    policy_render_emit_resolved_home_path_rules profiles/any-integration.sb "$home_profile" > "$test_root/rules"
    [[ "$(head -n 1 "$test_root/rules")" == "file-read*|literal|$test_root/other-home/one|$test_root/target-one" ]]
  '
  [ "$status" -eq 0 ]
}

@test "built-in path resolution batches candidates while preserving order, matchers, and deduplication" {
  path_resolution_run '
    realpath() {
      printf "%s\n" "$#" >> "$test_root/calls"
      command /bin/realpath "$@"
    }
    policy_render_emit_resolved_builtin_path_candidates profiles/test.sb "file-read*" \
      "literal|$test_root/one" "subpath|$test_root/two" \
      "literal|$test_root/alias" "literal|$test_root/missing" > "$test_root/rules"
    [[ "$(cat "$test_root/calls")" == 3 ]]
    expected="$(printf "%s\n" "literal|$test_root/one|$test_root/target-one|file-read*" "subpath|$test_root/two|$test_root/target-two|file-read*")"
    [[ "$(cat "$test_root/rules")" == "$expected" ]]
    policy_render_emit_resolved_builtin_path_candidates profiles/test.sb "file-read*" \
      "literal|$test_root/one" "literal|$test_root/target-one" > "$test_root/rules"
    [[ ! -s "$test_root/rules" ]]
  '
  [ "$status" -eq 0 ]
}

@test "failed or incomplete realpath batches fall back without losing valid targets" {
  path_resolution_run '
    realpath() {
      printf "%s\n" "$#" >> "$test_root/calls"
      if [[ "$#" -gt 1 ]]; then
        command /bin/realpath "$1"
        return "$batch_status"
      fi
      command /bin/realpath "$@"
    }
    for batch_status in 0 1; do
      : > "$test_root/calls"
      policy_render_emit_resolved_builtin_path_candidates profiles/test.sb "file-read*" \
        "literal|$test_root/one" "subpath|$test_root/two" > "$test_root/rules"
      [[ "$(cat "$test_root/calls")" == "$(printf "2\n1\n1")" ]]
      expected="$(printf "%s\n" "literal|$test_root/one|$test_root/target-one|file-read*" "subpath|$test_root/two|$test_root/target-two|file-read*")"
      [[ "$(cat "$test_root/rules")" == "$expected" ]]
    done
  '
  [ "$status" -eq 0 ]
}

@test "batch output stays paired with its inputs when paths disappear or appear during resolution" {
  path_resolution_run '
    realpath() {
      [[ "$#" -eq 2 ]]
      command /bin/realpath "$@"
      rm "$test_root/one"
      ln -s "$test_root/target-one" "$test_root/missing"
    }
    policy_render_emit_resolved_builtin_path_candidates profiles/test.sb "file-read*" \
      "literal|$test_root/one" "literal|$test_root/missing" "subpath|$test_root/two" > "$test_root/rules"
    expected="$(printf "%s\n" "literal|$test_root/one|$test_root/target-one|file-read*" "subpath|$test_root/two|$test_root/target-two|file-read*")"
    [[ "$(cat "$test_root/rules")" == "$expected" ]]
  '
  [ "$status" -eq 0 ]
}

@test "a disappearing batch operand does not prevent resolving the remaining paths" {
  path_resolution_run '
    realpath() {
      if [[ "$#" -gt 1 ]]; then
        rm "$test_root/one"
      fi
      command /bin/realpath "$@"
    }
    policy_render_emit_resolved_builtin_path_candidates profiles/test.sb "file-read*" \
      "literal|$test_root/one" "subpath|$test_root/two" > "$test_root/rules"
    [[ "$(cat "$test_root/rules")" == "subpath|$test_root/two|$test_root/target-two|file-read*" ]]
  '
  [ "$status" -eq 0 ]
}

@test "built-in symlinks still resolve when realpath is unavailable" {
  path_resolution_run '
    command() {
      if [[ "$#" -eq 2 && "$1" == -v && "$2" == realpath ]]; then
        return 1
      fi
      builtin command "$@"
    }
    policy_render_emit_resolved_builtin_path_candidates profiles/test.sb "file-read*" \
      "literal|$test_root/one" "subpath|$test_root/two" > "$test_root/rules"
    expected="$(printf "%s\n" "literal|$test_root/one|$test_root/target-one|file-read*" "subpath|$test_root/two|$test_root/target-two|file-read*")"
    [[ "$(cat "$test_root/rules")" == "$expected" ]]
  '
  [ "$status" -eq 0 ]
}

@test "batch resolution keeps all xcode-select pointer exclusions" {
  path_resolution_run '
    realpath() {
      printf "%s\n" "$@" >> "$test_root/calls"
      [[ "$#" -eq 1 && "$1" == "$test_root/one" ]] || return 1
      command /bin/realpath "$@"
    }
    policy_render_emit_resolved_builtin_path_candidates profiles/10-system-runtime.sb "file-read*" \
      "literal|/private/var/select/developer_dir" "literal|/var/select/developer_dir" \
      "literal|/private/var/db/xcode_select_link" "literal|/var/db/xcode_select_link" \
      "literal|$test_root/one" > "$test_root/rules"
    [[ "$(cat "$test_root/calls")" == "$test_root/one" ]]
    [[ "$(cat "$test_root/rules")" == "literal|$test_root/one|$test_root/target-one|file-read*" ]]
  '
  [ "$status" -eq 0 ]
}

@test "newline-containing resolved targets cannot be misread as other batch results" {
  path_resolution_run '
    source "$ROOT_DIR/bin/lib/policy/render.sh"
    bad_target="$(printf "%s/target-\nline" "$test_root")"
    touch "$bad_target"
    ln -sf "$bad_target" "$test_root/one"
    policy_render_begin_path_target "$test_root/policy.sb"
    policy_render_emit_resolved_builtin_path_candidates profiles/test.sb "file-read*" \
      "literal|$test_root/one" "subpath|$test_root/two"
  '
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "contains control characters"
}

@test "home batching rejects newline-containing symlink targets before emitting grants" {
  path_resolution_run '
    source "$ROOT_DIR/bin/lib/policy/render.sh"
    policy_req_home_dir="$test_root"
    bad_target="$(printf "%s/target-\nline" "$test_root")"
    touch "$bad_target"
    ln -sf "$bad_target" "$test_root/one"
    policy_render_begin_path_target "$test_root/policy.sb"
    policy_render_emit_resolved_home_path_rules profiles/any-agent.sb "$home_profile"
  '
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "contains control characters"
}

@test "shared batch fallback preserves trailing newlines for caller validation" {
  path_resolution_run '
    printf -v bad_target "%s/target-\n\n" "$test_root"
    touch "$bad_target"
    ln -sf "$bad_target" "$test_root/one"
    for mode in single multiple; do
      if [[ "$mode" == single ]]; then
        safehouse_resolve_paths_batch resolved "$test_root/one"
        [[ "${#resolved[@]}" -eq 1 ]]
      else
        safehouse_resolve_paths_batch resolved "$test_root/one" "$test_root/two"
        [[ "${#resolved[@]}" -eq 2 ]]
        [[ "${resolved[1]}" == "$test_root/target-two" ]]
      fi
      [[ "${resolved[0]}" == "$bad_target" ]]
    done
    source "$ROOT_DIR/bin/lib/policy/render.sh"
    policy_req_home_dir="$test_root"
    policy_render_begin_path_target "$test_root/policy.sb"
    if policy_render_emit_resolved_builtin_path_candidates profiles/test.sb "file-read*" "literal|$test_root/one"; then exit 1; fi
    if policy_render_emit_resolved_home_path_rules profiles/test.sb "$home_profile"; then exit 1; fi
  '
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "contains control characters"
}
