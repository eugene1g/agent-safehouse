#
# Per-test helper:
# - Runs suite setup (sft_setup_suite) itself when bats did not run setup_suite.bash,
#   as when running a single file with `bats <file>.bats`.
# - Creates a per-test workspace root and a separate per-test external root.
# - Exposes helpers used by individual .bats files.
# - Removes only exact per-test roots created here.
#

source "$(dirname "${BASH_SOURCE[0]}")/suite_helper.bash"

sft_setup_test_env() {
  local helper_dir

  helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

  [[ "$(uname -s)" == "Darwin" ]] || skip "requires macOS"
  command -v sandbox-exec >/dev/null 2>&1 || skip "sandbox-exec is required"

  # Run suite setup if bats did not (no setup_suite.bash found for this run).
  # This test then owns the suite root, and its teardown removes it.
  #
  # NOTE: Runs before the exports below, which sft_sanitize_env would remove.
  if [ "${SFT_SUITE_SETUP_DONE:-}" != 1 ]; then
    # NOTE: Not `|| return 1`: that would disable errexit inside the function
    sft_setup_suite
    SFT_TEST_OWNS_SUITE=1
  fi

  export SAFEHOUSE_WORKSPACE_ROOT
  export SAFEHOUSE_EXTERNAL_ROOT
  export SAFEHOUSE_FAKE_HOME_ROOT
  export SAFEHOUSE_HOST_HOME
  export SAFEHOUSE_DEFAULT_FAKE_HOME
  export SAFEHOUSE_WORKSPACE
  export SAFEHOUSE_REPO_ROOT

  SAFEHOUSE_REPO_ROOT="$(cd "${helper_dir}/.." && pwd -P)"
  SAFEHOUSE_HOST_HOME="${HOME:?}"

  # Holds the default workspace available to tests that want explicit current-workdir behavior.
  SAFEHOUSE_WORKSPACE_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR}/safehouse-workspace-root.XXXXXX")"
  # Holds paths whose access should depend on policy grants rather than broad /tmp access.
  SAFEHOUSE_EXTERNAL_ROOT="$(mktemp -d "${SAFEHOUSE_HOST_HOME}/.safehouse-bats-external.XXXXXX")"
  # Holds fake HOME directories for deterministic home-scoped policy behavior.
  SAFEHOUSE_FAKE_HOME_ROOT="$(mktemp -d "${SAFEHOUSE_HOST_HOME}/.safehouse-bats-home-root.XXXXXX")"
  # Default HOME for tests; host HOME usage should be explicit and rare.
  SAFEHOUSE_DEFAULT_FAKE_HOME="$(mktemp -d "${SAFEHOUSE_FAKE_HOME_ROOT}/home.XXXXXX")"
  # Default cwd for tests that exercise "current workspace" behavior.
  SAFEHOUSE_WORKSPACE="$(mktemp -d "${SAFEHOUSE_WORKSPACE_ROOT}/workspace.XXXXXX")"
  export HOME="${SAFEHOUSE_DEFAULT_FAKE_HOME}"
  sft_isolate_path_from_host_home

  cd "$SAFEHOUSE_WORKSPACE" || return 1
}

# Removes PATH entries that point inside the host HOME,
# keeping the original PATH in SAFEHOUSE_HOST_PATH.
# 
# While tests are running HOME is swapped for a fake one and the sandbox denies
# host-home directories such as ~/.cargo/bin. Without the isolation performed by
# this function, every Safehouse call performed by tests would print a warning
# to stderr for each dropped denied home-home PATH entry, which would pollute
# the test output and possibly cause the test to fail.
# 
# Tool discovery (sft_require_cmd_or_skip, sft_command_path_or_skip) still
# searches SAFEHOUSE_HOST_PATH, so tools installed under the host HOME are found.
# 
# Anything that runs as the host user with HOME="$SAFEHOUSE_HOST_HOME" should
# also set PATH="$SAFEHOUSE_HOST_PATH" so that bare tool names resolve.
sft_isolate_path_from_host_home() {
  local entry rest isolated_path=""

  export SAFEHOUSE_HOST_PATH="${SAFEHOUSE_HOST_PATH:-$PATH}"

  rest="$SAFEHOUSE_HOST_PATH"
  while :; do
    entry="${rest%%:*}"
    case "$entry" in
      "$SAFEHOUSE_HOST_HOME" | "$SAFEHOUSE_HOST_HOME"/*) ;;
      *) isolated_path="${isolated_path:+${isolated_path}:}${entry}" ;;
    esac
    [[ "$rest" == *:* ]] || break
    rest="${rest#*:}"
  done

  export PATH="$isolated_path"
}

sft_teardown_test_env() {
  sft_release_run_locks

  cd "${BATS_TEST_DIRNAME:-/}" || return 1
  sft_remove_test_root "${SAFEHOUSE_FAKE_HOME_ROOT:-}" || return 1
  sft_remove_test_root "${SAFEHOUSE_EXTERNAL_ROOT:-}" || return 1
  sft_remove_test_root "${SAFEHOUSE_WORKSPACE_ROOT:-}" || return 1

  if [ "${SFT_TEST_OWNS_SUITE:-}" = 1 ]; then
    sft_teardown_suite || return 1
  fi
}

setup() {
  sft_setup_test_env
}

teardown() {
  sft_teardown_test_env
}

sft_remove_test_root() {
  local path="$1"

  [[ -z "$path" ]] && return 0

  case "$path" in
    "${BATS_TEST_TMPDIR}"/safehouse-workspace-root.* | \
    "${SAFEHOUSE_HOST_HOME}"/.safehouse-bats-home-root.* | \
    "${SAFEHOUSE_HOST_HOME}"/.safehouse-bats-external.*)
      # Restore write permission first, since some tools leave read-only
      # directories behind, which rm cannot empty.
      # e.g. virtualenv's wheel cache, ~/Library/Caches/virtualenv/wheel/
      [ ! -e "$path" ] || chmod -R u+w "$path" || return 1
      rm -rf -- "$path"
      ;;
    *)
      printf 'refusing to remove unsafe test path: %s\n' "$path" >&2
      return 1
      ;;
  esac
}

safehouse_ok() {
  "$DIST_SAFEHOUSE" "$@"
}

safehouse_run() {
  run "$DIST_SAFEHOUSE" "$@"
}

safehouse_ok_env() {
  local -a env_args=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --)
        shift
        break
        ;;
      *)
        env_args+=("$1")
        shift
        ;;
    esac
  done

  env "${env_args[@]}" "$DIST_SAFEHOUSE" "$@"
}

safehouse_run_env() {
  run safehouse_ok_env "$@"
}

safehouse_ok_in_dir() {
  local dir="$1"
  shift

  (cd "$dir" && "$DIST_SAFEHOUSE" "$@")
}

safehouse_denied() {
  run safehouse_ok "$@"
  [ "$status" -ne 0 ]
}

safehouse_denied_env() {
  run safehouse_ok_env "$@"
  [ "$status" -ne 0 ]
}

safehouse_denied_in_dir() {
  run safehouse_ok_in_dir "$@"
  [ "$status" -ne 0 ]
}

safehouse_profile() {
  "$DIST_SAFEHOUSE" --stdout "$@"
}

safehouse_profile_env() {
  local -a env_args=()

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --)
        shift
        break
        ;;
      *)
        env_args+=("$1")
        shift
        ;;
    esac
  done

  env "${env_args[@]}" "$DIST_SAFEHOUSE" --stdout "$@"
}

safehouse_profile_in_dir() {
  local dir="$1"
  shift

  (cd "$dir" && "$DIST_SAFEHOUSE" --stdout "$@")
}

sft_require_cmd_or_skip() {
  local cmd="$1"

  PATH="${SAFEHOUSE_HOST_PATH:-$PATH}" command -v "$cmd" >/dev/null 2>&1 || skip "${cmd} is not installed"
}

sft_require_env_or_skip() {
  local var_name="$1"
  local value="${!var_name:-}"

  [[ -n "$value" ]] || skip "${var_name} is not set"
}

# Assigns the resolved path of <cmd> to the caller variable <var_name>,
# or skips the test when the command is unavailable.
sft_command_path_or_skip() {
  local var_name="$1" cmd="$2" path

  path="$(PATH="${SAFEHOUSE_HOST_PATH:-$PATH}" command -v "$cmd" || true)"
  [ -n "$path" ] || skip "${cmd} is not installed"

  printf -v "$var_name" '%s' "$path"
}

sft_assert_contains() {
  local haystack="$1" needle="$2"

  [[ "$haystack" == *"$needle"* ]] && return 0

  printf 'expected output to contain: %s\n' "$needle" >&2
  return 1
}

sft_assert_not_contains() {
  local haystack="$1" needle="$2"

  [[ "$haystack" != *"$needle"* ]] && return 0

  printf 'expected output NOT to contain: %s\n' "$needle" >&2
  return 1
}

sft_source_marker() {
  local source_path="$1"

  printf ';; Source: %s' "$source_path"
}

sft_assert_includes_source() {
  local haystack="$1" source_path="$2"

  sft_assert_contains "$haystack" "$(sft_source_marker "$source_path")"
}

sft_assert_omits_source() {
  local haystack="$1" source_path="$2"

  sft_assert_not_contains "$haystack" "$(sft_source_marker "$source_path")"
}

# Extract only the lines emitted for a single source section, i.e. from that
# section's "Source:" marker up to (but excluding) the next section marker.
# Useful for asserting a rule lives in a specific profile rather than merely
# somewhere in the assembled output (deny and allow blocks can share strings).
sft_profile_source_section() {
  local haystack="$1" source_path="$2" marker
  marker="$(sft_source_marker "$source_path")"

  printf '%s\n' "$haystack" | awk -v marker="$marker" '
    index($0, ";; Source: ") == 1 { insec = (index($0, marker) > 0) }
    insec { print }
  '
}

sft_assert_order() {
  local haystack="$1" first="$2" second="$3"
  local first_line second_line

  first_line="$(awk -v needle="$first" 'index($0, needle) { print NR; exit }' <<<"$haystack")"
  second_line="$(awk -v needle="$second" 'index($0, needle) { print NR; exit }' <<<"$haystack")"

  if [[ -z "$first_line" || -z "$second_line" ]]; then
    printf 'expected both markers to be present: %s ; %s\n' "$first" "$second" >&2
    return 1
  fi

  if [[ "$first_line" -lt "$second_line" ]]; then
    return 0
  fi

  printf 'expected marker order: %s before %s\n' "$first" "$second" >&2
  return 1
}

sft_assert_file_exists() {
  local path="$1"

  [ -f "$path" ] && return 0

  printf 'expected file to exist: %s\n' "$path" >&2
  return 1
}

sft_assert_file_content() {
  local path="$1" expected="$2" actual

  sft_assert_file_exists "$path" || return 1

  actual="$(cat "$path")" || return 1
  [ "$actual" = "$expected" ] && return 0

  printf 'unexpected file content for %s\nexpected: %s\nactual: %s\n' "$path" "$expected" "$actual" >&2
  return 1
}

sft_assert_file_contains() {
  local path="$1" needle="$2" content

  sft_assert_file_exists "$path" || return 1
  content="$(cat "$path")" || return 1
  sft_assert_contains "$content" "$needle"
}

sft_assert_file_includes_source() {
  local path="$1" source_path="$2"

  sft_assert_file_contains "$path" "$(sft_source_marker "$source_path")"
}

sft_assert_file_not_contains() {
  local path="$1" needle="$2" content

  sft_assert_file_exists "$path" || return 1
  content="$(cat "$path")" || return 1
  sft_assert_not_contains "$content" "$needle"
}

sft_assert_file_omits_source() {
  local path="$1" source_path="$2"

  sft_assert_file_not_contains "$path" "$(sft_source_marker "$source_path")"
}

# Fails if $path exists, including as a dangling symlink.
sft_assert_path_absent() {
  local path="$1"

  [ ! -e "$path" ] && [ ! -L "$path" ] && return 0

  printf 'expected path to be absent: %s\n' "$path" >&2
  return 1
}

sft_external_dir() {
  local label="$1"

  # Path rooted outside the workspace so access semantics depend on Safehouse policy.
  mktemp -d "${SAFEHOUSE_EXTERNAL_ROOT}/${label}.XXXXXX"
}

# Creates a new fake home and prints its path. Options add standard dirs that
# a real home would already have, and that a sandboxed tool may be unable to
# create itself:
# --macos-dirs: See sft_create_macos_home_dirs.
# --xdg-dirs:   See sft_create_xdg_home_dirs.
sft_fake_home() {
  local fake_home opt
  fake_home="$(mktemp -d "${SAFEHOUSE_FAKE_HOME_ROOT}/home.XXXXXX")" || return 1
  for opt in "$@"; do
    case "$opt" in
      --macos-dirs) sft_create_macos_home_dirs "$fake_home" || return 1 ;;
      --xdg-dirs)   sft_create_xdg_home_dirs "$fake_home" || return 1 ;;
      *) printf 'sft_fake_home: unknown option: %s\n' "$opt" >&2; return 1 ;;
    esac
  done
  printf '%s\n' "$fake_home"
}

# Creates the ~/Library directories that macOS creates for every new user,
# where many tools put their default config, data, cache and logs.
sft_create_macos_home_dirs() {
  local home="$1"
  mkdir -p \
    "${home}/Library/Application Support" \
    "${home}/Library/Caches" \
    "${home}/Library/Logs"
}

# Creates the default XDG roots, which XDG-style tools write under. A real home
# has them once any such tool has run outside the sandbox.
sft_create_xdg_home_dirs() {
  local home="$1"
  mkdir -p \
    "${home}/.cache" \
    "${home}/.local/share"
}

# Prints a digest of the names, modes, inodes and change times of every path
# under the given paths, without following symlinks. Compare digests taken
# before and after an action to assert that it left those trees unchanged.
sft_tree_snapshot() {
  find "$@" -exec /usr/bin/stat -f '%N %Sp %i %z %m' {} + | LC_ALL=C sort | shasum
}

# Holds a lock named $1, shared by all tests in the bats run, until
# sft_release_run_locks. Waits up to 600s for another test to release it.
# Serializes tests that use one shared resource outside the fake home,
# such as an interpreter's global site-packages.
sft_acquire_run_lock() {
  local name="$1" timeout=600 lock_dir waited=0
  # BATS_RUN_TMPDIR is shared by all parallel workers of the same bats run,
  # and is discarded with the run.
  lock_dir="${BATS_RUN_TMPDIR}/sft-${name}.lock"

  until mkdir "$lock_dir" 2>/dev/null; do
    if [ "$waited" -ge "$timeout" ]; then
      echo "timed out after ${timeout}s waiting for ${lock_dir}" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  SFT_RUN_LOCKS+=("$lock_dir")
}

# Releases every lock this test holds. Called by sft_teardown_test_env.
sft_release_run_locks() {
  local lock_dir
  for lock_dir in ${SFT_RUN_LOCKS[@]+"${SFT_RUN_LOCKS[@]}"}; do
    rmdir "$lock_dir" 2>/dev/null || true
  done
  SFT_RUN_LOCKS=()
}

sft_workspace_path() {
  local name="$1"

  printf '%s/%s\n' "$SAFEHOUSE_WORKSPACE" "$name"
}

sft_external_path() {
  local label="$1" name="$2" dir

  dir="$(sft_external_dir "$label")" || return 1
  printf '%s/%s\n' "$dir" "$name"
}

sft_make_fake_command() {
  local path="$1"

  mkdir -p "$(dirname "$path")" || return 1
  cp /usr/bin/true "$path" || return 1
  chmod 755 "$path" || return 1
}
