# shellcheck shell=bash

# Purpose: Resolve Git repo/worktree metadata for Safehouse startup.
#
# Why this lives in its own module:
# - The native/canonical way to answer these questions is to shell out to
#   `git rev-parse ...`.
# - Safehouse originally did that on every startup, but these subprocesses sit
#   on the default no-arg path and added measurable latency to simple launches.
# - For the default case we only need a few narrow answers:
#   1. what directory should be treated as the repo/worktree root?
#   2. if that root is a linked worktree, where is its shared git common dir?
#   3. what other existing worktrees belong to this repository?
#
# Why a filesystem fast path is acceptable here:
# - Git documents the relevant on-disk layout in `gitrepository-layout(5)` and
#   `git-worktree(1)`.
# - A linked worktree uses a top-level `.git` file that points at a private
#   worktree admin dir, and that admin dir may contain `commondir` pointing
#   back to the shared repository metadata.
# - Reading those documented files is enough for Safehouse's default-case
#   policy decision and avoids spawning Git subprocesses on every launch.
#
# Why we still keep Git fallback:
# - `git rev-parse` remains the native source of truth for unusual layouts,
#   malformed/stale metadata, or future Git behavior that still resolves
#   correctly via the CLI but no longer matches our narrow fast path.
# - The native enumeration path for worktrees is `git worktree list`; Safehouse
#   keeps that as the fallback when the filesystem shape is incomplete or odd.

safehouse_git_command_available() {
  command -v git >/dev/null 2>&1
}

safehouse_git_normalize_discovery_cwd() {
  local cwd="$1"

  if [[ "$cwd" == /* ]]; then
    printf '%s\n' "$cwd"
    return 0
  fi

  safehouse_normalize_abs_path "$cwd"
}

safehouse_git_marker_path_is_repo_root() {
  local marker_path="$1"
  local first_line=""
  local git_dir=""
  local marker_dir=""

  if [[ -d "$marker_path" ]]; then
    [[ -f "${marker_path}/HEAD" ]] || return 1
    [[ -d "${marker_path}/objects" ]] || return 1
    [[ -d "${marker_path}/refs" ]] || return 1
    return 0
  fi

  if [[ ! -f "$marker_path" ]]; then
    return 1
  fi

  IFS= read -r first_line < "$marker_path" || true
  [[ "$first_line" == gitdir:\ * ]] || return 1

  git_dir="${first_line#gitdir: }"
  [[ -n "$git_dir" ]] || return 1

  marker_dir="${marker_path%/*}"
  if [[ "$git_dir" == /* ]]; then
    [[ -d "$git_dir" && -f "${git_dir}/HEAD" ]]
    return $?
  fi

  (
    cd "$marker_dir" || exit 1
    cd "$git_dir" || exit 1
    [[ -f "$(pwd -P)/HEAD" ]]
  )
}

safehouse_git_find_root_from_filesystem() {
  local cwd="$1"
  local probe_dir marker_path

  probe_dir="$(safehouse_git_normalize_discovery_cwd "$cwd")" || return 1

  while [[ -n "$probe_dir" ]]; do
    marker_path="${probe_dir%/}/.git"
    if safehouse_git_marker_path_is_repo_root "$marker_path"; then
      printf '%s\n' "$probe_dir"
      return 0
    fi

    if [[ "$probe_dir" == "/" ]]; then
      break
    fi

    probe_dir="${probe_dir%/*}"
    [[ -n "$probe_dir" ]] || probe_dir="/"
  done

  return 1
}

safehouse_find_git_root_via_git() {
  local cwd="$1"
  local git_root=""

  safehouse_git_command_available || return 1

  git_root="$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null || true)"
  if [[ -n "$git_root" && -d "$git_root" ]]; then
    printf '%s\n' "$git_root"
    return 0
  fi

  return 1
}

safehouse_find_git_root() {
  local cwd="$1"

  # Prefer the documented on-disk marker walk on the default startup path.
  # Fall back to `git rev-parse --show-toplevel` for unusual layouts.
  safehouse_git_find_root_from_filesystem "$cwd" && return 0
  safehouse_find_git_root_via_git "$cwd"
}

safehouse_git_resolve_path_from_base_dir() {
  local base_dir="$1"
  local raw_path="$2"

  if [[ "$raw_path" == /* ]]; then
    safehouse_normalize_abs_path "$raw_path"
    return 0
  fi

  (
    cd "$base_dir" || exit 1
    cd "$raw_path" || exit 1
    pwd -P
  )
}

safehouse_git_resolve_worktree_gitdir_from_marker() {
  local repo_root="$1"
  local marker_path="${repo_root%/}/.git"
  local git_dir_line="" git_dir=""

  [[ -f "$marker_path" ]] || return 1

  IFS= read -r git_dir_line < "$marker_path" || true
  [[ "$git_dir_line" == gitdir:\ * ]] || return 1

  git_dir="${git_dir_line#gitdir: }"
  [[ -n "$git_dir" ]] || return 1

  safehouse_git_resolve_path_from_base_dir "$repo_root" "$git_dir"
}

safehouse_git_find_worktree_common_dir_from_filesystem() {
  local cwd="$1"
  local repo_root="" git_dir="" git_common_dir_rel="" git_common_dir=""

  repo_root="$(safehouse_git_find_root_from_filesystem "$cwd" || true)"
  [[ -n "$repo_root" ]] || return 1

  git_dir="$(safehouse_git_resolve_worktree_gitdir_from_marker "$repo_root" || true)"
  [[ -n "$git_dir" && -d "$git_dir" ]] || return 1
  [[ -f "${git_dir}/commondir" ]] || return 1

  IFS= read -r git_common_dir_rel < "${git_dir}/commondir" || true
  [[ -n "$git_common_dir_rel" ]] || return 1

  git_common_dir="$(safehouse_git_resolve_path_from_base_dir "$git_dir" "$git_common_dir_rel" || true)"
  if [[ -n "$git_common_dir" && -d "$git_common_dir" && "$git_common_dir" != "$git_dir" ]]; then
    printf '%s\n' "$git_common_dir"
    return 0
  fi

  return 1
}

safehouse_git_resolve_main_worktree_root_from_common_dir() {
  local common_dir="$1"
  local main_root=""

  main_root="${common_dir%/*}"
  [[ -n "$main_root" && "$main_root" != "$common_dir" ]] || return 1
  [[ -d "${main_root}/.git" ]] || return 1

  safehouse_normalize_abs_path "$main_root"
}

safehouse_find_git_worktree_common_dir_via_git() {
  local cwd="$1"
  local output="" git_dir="" git_common_dir=""

  safehouse_git_command_available || return 1

  output="$(git -C "$cwd" rev-parse --path-format=absolute --git-dir --git-common-dir 2>/dev/null || true)"
  [[ -n "$output" ]] || return 1

  git_dir="${output%%$'\n'*}"
  if [[ "$output" == *$'\n'* ]]; then
    git_common_dir="${output#*$'\n'}"
    git_common_dir="${git_common_dir%%$'\n'*}"
  fi

  [[ -n "$git_dir" && -n "$git_common_dir" ]] || return 1
  git_dir="$(safehouse_normalize_abs_path "$git_dir")" || return 1
  git_common_dir="$(safehouse_normalize_abs_path "$git_common_dir")" || return 1

  if [[ -d "$git_dir" && -d "$git_common_dir" && "$git_dir" != "$git_common_dir" ]]; then
    printf '%s\n' "$git_common_dir"
    return 0
  fi

  return 1
}

safehouse_find_git_worktree_common_dir() {
  local cwd="$1"

  # Prefer the linked-worktree `.git` + `commondir` files on the default path.
  # Fall back to the native `git rev-parse --git-dir --git-common-dir` query
  # when the filesystem shape is missing or suspicious.
  safehouse_git_find_worktree_common_dir_from_filesystem "$cwd" && return 0
  safehouse_find_git_worktree_common_dir_via_git "$cwd"
}

safehouse_emit_git_worktree_paths_from_filesystem() {
  local cwd="$1"
  local repo_root="" common_dir="" main_worktree_root=""
  local entry_dir="" gitdir_path="" worktree_path=""
  local normalized_path=""

  repo_root="$(safehouse_git_find_root_from_filesystem "$cwd" || true)"
  [[ -n "$repo_root" ]] || return 1

  if [[ -d "${repo_root}/.git" ]]; then
    common_dir="$(safehouse_normalize_abs_path "${repo_root}/.git")" || return 1
  else
    common_dir="$(safehouse_git_find_worktree_common_dir_from_filesystem "$cwd" || true)"
  fi
  [[ -n "$common_dir" && -d "$common_dir" ]] || return 1

  if [[ "$common_dir" != "${repo_root}/.git" ]]; then
    main_worktree_root="$(safehouse_git_resolve_main_worktree_root_from_common_dir "$common_dir" || true)"
    [[ -n "$main_worktree_root" ]] || return 1
    printf '%s\n' "$main_worktree_root"
  fi

  for entry_dir in "${common_dir}/worktrees"/*; do
    [[ -d "$entry_dir" ]] || continue
    [[ -f "${entry_dir}/gitdir" ]] || continue

    IFS= read -r gitdir_path < "${entry_dir}/gitdir" || true
    [[ -n "$gitdir_path" ]] || continue

    if [[ "$gitdir_path" == /* ]]; then
      [[ -e "$gitdir_path" ]] || continue
    else
      gitdir_path="${entry_dir%/}/${gitdir_path}"
      [[ -e "$gitdir_path" ]] || continue
    fi

    gitdir_path="$(safehouse_normalize_abs_path "$gitdir_path")" || return 1
    worktree_path="${gitdir_path%/*}"
    [[ -n "$worktree_path" && -d "$worktree_path" ]] || continue

    normalized_path="$(safehouse_normalize_abs_path "$worktree_path")" || return 1
    printf '%s\n' "$normalized_path"
  done
}

safehouse_emit_git_worktree_paths_via_git() {
  local cwd="$1"
  local line=""
  local worktree_path=""
  local normalized_path=""

  safehouse_git_command_available || return 1

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      "worktree "*) worktree_path="${line#worktree }" ;;
      *) continue ;;
    esac

    [[ -n "$worktree_path" ]] || continue
    if [[ "$worktree_path" != /* ]]; then
      worktree_path="${cwd%/}/${worktree_path}"
    fi
    if [[ ! -d "$worktree_path" ]]; then
      continue
    fi

    normalized_path="$(safehouse_normalize_abs_path "$worktree_path")" || continue
    printf '%s\n' "$normalized_path"
  done < <(git -C "$cwd" worktree list --porcelain 2>/dev/null || true)
}

safehouse_emit_git_worktree_paths() {
  local cwd="$1"

  safehouse_emit_git_worktree_paths_from_filesystem "$cwd" && return 0
  safehouse_emit_git_worktree_paths_via_git "$cwd"
}
