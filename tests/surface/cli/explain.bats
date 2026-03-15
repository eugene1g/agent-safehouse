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
