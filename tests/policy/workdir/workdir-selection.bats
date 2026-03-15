#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

sft_setup_linked_git_worktree_fixture() {
  local git_common_dir=""

  sft_require_cmd_or_skip git

  git_worktree_fixture_root="$(sft_external_dir "git-worktree")" || return 1
  git_worktree_main_repo="${git_worktree_fixture_root}/main-repo"
  git_linked_worktree="${git_worktree_fixture_root}/feature-worktree"
  git_sibling_worktree="${git_worktree_fixture_root}/review-worktree"
  git_worktree_common_dir=""

  mkdir -p "$git_worktree_main_repo" || return 1
  git -C "$git_worktree_main_repo" init -q || return 1

  printf '%s\n' "tracked" > "${git_worktree_main_repo}/tracked.txt"
  git -C "$git_worktree_main_repo" add tracked.txt || return 1
  git -C "$git_worktree_main_repo" -c user.name=test -c user.email=test@example.com commit -q -m init || return 1
  git -C "$git_worktree_main_repo" branch feature || return 1
  git -C "$git_worktree_main_repo" branch review || return 1
  git -C "$git_worktree_main_repo" worktree add -q "$git_linked_worktree" feature || return 1
  git -C "$git_worktree_main_repo" worktree add -q "$git_sibling_worktree" review || return 1

  git_worktree_common_dir="$(
    cd "$git_linked_worktree" || exit 1
    git_common_dir="$(git rev-parse --git-common-dir)" || exit 1
    if [[ "$git_common_dir" == /* ]]; then
      printf '%s\n' "$git_common_dir"
    else
      cd "$git_common_dir" || exit 1
      pwd -P
    fi
  )" || return 1
}

@test "[EXECUTION] explicit workdir allows writes there and still blocks unrelated paths" {
  local explicit_dir allowed_file blocked_file

  explicit_dir="$(sft_external_dir "explicit-workdir")" || return 1
  allowed_file="${explicit_dir}/explicit-workdir-ok.txt"
  blocked_file="$(sft_external_path "explicit-workdir-blocked" "blocked.txt")" || return 1

  safehouse_ok --workdir "$explicit_dir" -- /bin/sh -c "printf '%s' ok > '$allowed_file'"
  sft_assert_file_content "$allowed_file" "ok"

  safehouse_denied --workdir "$explicit_dir" -- /bin/sh -c "touch '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}

@test "[EXECUTION] git root is auto-detected when invoked from a nested repo path" {
  sft_require_cmd_or_skip git

  local repo_root nested_dir repo_file nested_file blocked_file
  repo_root="$(sft_workspace_path "repo")" || return 1
  nested_dir="${repo_root}/nested/work"
  repo_file="${repo_root}/git-root-ok.txt"
  nested_file="${nested_dir}/git-subdir-ok.txt"
  blocked_file="$(sft_external_path "git-root-blocked" "blocked.txt")" || return 1

  mkdir -p "$nested_dir"
  /bin/sh -c "cd '$repo_root' && git init -q" || return 1

  safehouse_ok_in_dir "$nested_dir" -- /bin/sh -c "touch '$repo_file' '$nested_file'"
  sft_assert_file_exists "$repo_file"
  sft_assert_file_exists "$nested_file"

  safehouse_denied_in_dir "$nested_dir" -- /bin/sh -c "touch '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}

@test "[EXECUTION] linked git worktrees can write shared git metadata without manual extra grants" { # https://github.com/eugene1g/agent-safehouse/issues/37
  sft_setup_linked_git_worktree_fixture || return 1

  safehouse_ok_in_dir "$git_linked_worktree" -- /bin/sh -c "git branch sandbox-branch"

  git -C "$git_worktree_main_repo" rev-parse --verify sandbox-branch >/dev/null
}

@test "[EXECUTION] linked git worktrees can read sibling trees but not write them by default" { # https://github.com/eugene1g/agent-safehouse/issues/37
  local blocked_file

  sft_setup_linked_git_worktree_fixture || return 1
  blocked_file="$(sft_external_path "git-worktree-blocked" "blocked.txt")" || return 1

  safehouse_ok_in_dir "$git_linked_worktree" -- /bin/sh -c "cat '$git_worktree_main_repo/tracked.txt' '$git_sibling_worktree/tracked.txt' >/dev/null"
  safehouse_denied_in_dir "$git_linked_worktree" -- /bin/sh -c "printf '%s' blocked > '$git_sibling_worktree/blocked.txt'"
  sft_assert_path_absent "${git_sibling_worktree}/blocked.txt"

  safehouse_denied_in_dir "$git_linked_worktree" -- /bin/sh -c "touch '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}
