#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "--explain reports the effective workdir and normalized grants" {
  local explain_log workdir ro_dir rw_dir

  explain_log="$(sft_workspace_path "explain.log")"
  workdir="$(sft_external_dir "explain-workdir")" || return 1
  ro_dir="$(sft_external_dir "explain-ro")" || return 1
  rw_dir="$(sft_external_dir "explain-rw")" || return 1

  safehouse_ok --explain --stdout --workdir="$workdir" --add-dirs-ro="$ro_dir" --add-dirs="$rw_dir" >/dev/null 2>"$explain_log"

  sft_assert_file_contains "$explain_log" "safehouse explain:"
  sft_assert_file_contains "$explain_log" "policy file: (stdout)"
  sft_assert_file_contains "$explain_log" "effective workdir: ${workdir} (source: --workdir)"
  sft_assert_file_contains "$explain_log" "add-dirs-ro (normalized): ${ro_dir}"
  sft_assert_file_contains "$explain_log" "add-dirs (normalized): ${rw_dir}"
}

@test "--explain reports environment mode and profile env defaults" {
  local env_log pass_log profile_log env_file

  env_log="$(sft_workspace_path "explain-env.log")"
  pass_log="$(sft_workspace_path "explain-pass.log")"
  profile_log="$(sft_workspace_path "explain-profile.log")"
  env_file="$(sft_workspace_path "explain.env")"

  printf '%s\n' 'SAFEHOUSE_TEST_SECRET=file-secret' > "$env_file"

  safehouse_ok --env="$env_file" --explain --stdout >/dev/null 2>"$env_log"
  safehouse_ok --env-pass=SAFEHOUSE_TEST_EXPLAIN --explain --stdout >/dev/null 2>"$pass_log"
  safehouse_ok --enable=playwright-chrome --explain --stdout >/dev/null 2>"$profile_log"

  sft_assert_file_contains "$env_log" "execution environment: sanitized allowlist + file overrides ("
  sft_assert_file_contains "$pass_log" "execution environment: sanitized allowlist + named host vars (SAFEHOUSE_TEST_EXPLAIN)"
  sft_assert_file_contains "$profile_log" "profile env defaults: PLAYWRIGHT_MCP_SANDBOX=false"
}

@test "--explain reports explicitly enabled keychain integration as included" {
  local explain_log

  explain_log="$(sft_workspace_path "explain-keychain.log")"

  safehouse_ok --enable=keychain --explain --stdout -- /usr/bin/true >/dev/null 2>"$explain_log"

  sft_assert_file_contains "$explain_log" "optional integrations explicitly enabled: keychain"
  sft_assert_file_contains "$explain_log" "keychain integration: included"
}

@test "--explain reports command resolution details and debug hints" {
  local explain_log fake_cmd fake_cmd_name

  explain_log="$(sft_workspace_path "explain-command.log")"
  mkdir -p "${HOME}/.local/bin" || return 1
  fake_cmd="$(mktemp "${HOME}/.local/bin/explain-cmd.XXXXXX")" || return 1
  fake_cmd_name="$(basename "$fake_cmd")"

  sft_make_fake_command "$fake_cmd"

  safehouse_ok --explain --stdout -- "$fake_cmd_name" >/dev/null 2>"$explain_log"

  sft_assert_file_contains "$explain_log" "invoked command: ${fake_cmd_name}"
  sft_assert_file_contains "$explain_log" "profile target command: ${fake_cmd_name}"
  sft_assert_file_contains "$explain_log" "host PATH matches: (none)"
  sft_assert_file_contains "$explain_log" "execution PATH: "
  sft_assert_file_contains "$explain_log" "execution PATH matches: ${fake_cmd}"
  sft_assert_file_contains "$explain_log" "shell wrapper note: interactive-shell aliases/functions are not introspected; run \`type -a ${fake_cmd_name}\` in your shell if wrapper resolution may matter"
  sft_assert_file_contains "$explain_log" "sandbox denial log hint: /usr/bin/log show --last 2m --style compact --predicate 'eventMessage CONTAINS \"Sandbox:\" AND eventMessage CONTAINS \"deny(\"'"
}

@test "--explain reports default git worktree common-dir and sibling read grants" {
  local explain_log repo_root worktree_parent linked_worktree sibling_worktree git_common_dir

  sft_require_cmd_or_skip git

  explain_log="$(sft_workspace_path "explain-worktree.log")"
  repo_root="$(sft_external_dir "explain-git-worktree")" || return 1
  worktree_parent="$(dirname "$repo_root")"
  linked_worktree="${worktree_parent}/feature-worktree"
  sibling_worktree="${worktree_parent}/review-worktree"

  git -C "$repo_root" init -q || return 1
  printf '%s\n' "tracked" > "${repo_root}/tracked.txt"
  git -C "$repo_root" add tracked.txt || return 1
  git -C "$repo_root" -c user.name=test -c user.email=test@example.com commit -q -m init || return 1
  git -C "$repo_root" branch feature || return 1
  git -C "$repo_root" branch review || return 1
  git -C "$repo_root" worktree add -q "$linked_worktree" feature || return 1
  git -C "$repo_root" worktree add -q "$sibling_worktree" review || return 1
  git_common_dir="$(git -C "$linked_worktree" rev-parse --path-format=absolute --git-common-dir)"

  safehouse_ok_in_dir "$linked_worktree" --explain --stdout >/dev/null 2>"$explain_log"

  sft_assert_file_contains "$explain_log" "git worktree common dir grant: ${git_common_dir}"
  sft_assert_file_contains "$explain_log" "git linked worktree read grants: ${repo_root} ${sibling_worktree}"
}

@test "--explain skips stale linked worktree admin entries without surfacing realpath errors" {
  local explain_log repo_root worktree_parent stale_worktree sibling_worktree

  sft_require_cmd_or_skip git

  explain_log="$(sft_workspace_path "explain-stale-worktree.log")"
  repo_root="$(sft_external_dir "explain-stale-git-worktree")" || return 1
  worktree_parent="$(dirname "$repo_root")"
  stale_worktree="${worktree_parent}/stale-worktree"
  sibling_worktree="${worktree_parent}/review-worktree"

  git -C "$repo_root" init -q || return 1
  printf '%s\n' "tracked" > "${repo_root}/tracked.txt"
  git -C "$repo_root" add tracked.txt || return 1
  git -C "$repo_root" -c user.name=test -c user.email=test@example.com commit -q -m init || return 1
  git -C "$repo_root" branch stale || return 1
  git -C "$repo_root" branch review || return 1
  git -C "$repo_root" worktree add -q "$stale_worktree" stale || return 1
  git -C "$repo_root" worktree add -q "$sibling_worktree" review || return 1
  rm -rf "$stale_worktree" || return 1

  safehouse_ok_in_dir "$repo_root" --explain --stdout >/dev/null 2>"$explain_log"

  sft_assert_file_not_contains "$explain_log" "realpath:"
  sft_assert_file_contains "$explain_log" "git linked worktree read grants: ${sibling_worktree}"
  sft_assert_file_not_contains "$explain_log" "$stale_worktree"
}
