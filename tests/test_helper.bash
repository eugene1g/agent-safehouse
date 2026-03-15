#
# Per-test helper:
# - Assumes setup_suite.bash already staged dist/safehouse.sh for the full bats run.
# - Creates a per-test workspace root and a separate per-test external root.
# - Exposes helpers used by individual .bats files.
# - Removes only exact per-test roots created here.
#

sft_setup_test_env() {
  local helper_dir source_dist_safehouse

  helper_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"

  [[ "$(uname -s)" == "Darwin" ]] || skip "requires macOS"
  command -v sandbox-exec >/dev/null 2>&1 || skip "sandbox-exec is required"

  export SAFEHOUSE_WORKSPACE_ROOT
  export SAFEHOUSE_EXTERNAL_ROOT
  export SAFEHOUSE_FAKE_HOME_ROOT
  export SAFEHOUSE_HOST_HOME
  export SAFEHOUSE_DEFAULT_FAKE_HOME
  export SAFEHOUSE_WORKSPACE
  export SAFEHOUSE_TEST_DIST_ROOT
  export SAFEHOUSE_REPO_ROOT

  SAFEHOUSE_REPO_ROOT="$(cd "${helper_dir}/.." && pwd -P)"
  SAFEHOUSE_HOST_HOME="${HOME:?}"

  if [ ! -x "${DIST_SAFEHOUSE:-}" ]; then
    source_dist_safehouse="${SAFEHOUSE_REPO_ROOT}/dist/safehouse.sh"
    [ -x "$source_dist_safehouse" ] || skip "dist/safehouse.sh is not available"

    SAFEHOUSE_TEST_DIST_ROOT="$(mktemp -d "${BATS_TEST_TMPDIR}/safehouse-test-dist-root.XXXXXX")"
    DIST_SAFEHOUSE="${SAFEHOUSE_TEST_DIST_ROOT}/safehouse.sh"
    cp "$source_dist_safehouse" "$DIST_SAFEHOUSE"
    chmod 755 "$DIST_SAFEHOUSE"
  fi

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

  cd "$SAFEHOUSE_WORKSPACE" || return 1
}

sft_teardown_test_env() {
  cd "${BATS_TEST_DIRNAME:-/}" || return 1
  sft_remove_test_root "${SAFEHOUSE_FAKE_HOME_ROOT:-}" || return 1
  sft_remove_test_root "${SAFEHOUSE_EXTERNAL_ROOT:-}" || return 1
  sft_remove_test_root "${SAFEHOUSE_WORKSPACE_ROOT:-}" || return 1
  sft_remove_test_root "${SAFEHOUSE_TEST_DIST_ROOT:-}" || return 1
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
    "${BATS_TEST_TMPDIR}"/safehouse-test-dist-root.*)
      rm -rf -- "$path"
      ;;
    "${BATS_TEST_TMPDIR}"/safehouse-workspace-root.*)
      rm -rf -- "$path"
      ;;
    "${SAFEHOUSE_HOST_HOME}"/.safehouse-bats-home-root.*)
      rm -rf -- "$path"
      ;;
    "${SAFEHOUSE_HOST_HOME}"/.safehouse-bats-external.*)
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

  command -v "$cmd" >/dev/null 2>&1 || skip "${cmd} is not installed"
}

sft_require_env_or_skip() {
  local var_name="$1"
  local value="${!var_name:-}"

  [[ -n "$value" ]] || skip "${var_name} is not set"
}

sft_command_path_or_skip() {
  local cmd="$1" path

  path="$(command -v "$cmd" || true)"
  [ -n "$path" ] || skip "${cmd} is not installed"

  printf '%s\n' "$path"
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

sft_assert_path_absent() {
  local path="$1"

  [ ! -e "$path" ] && return 0

  printf 'expected path to be absent: %s\n' "$path" >&2
  return 1
}

sft_external_dir() {
  local label="$1"

  # Path rooted outside the workspace so access semantics depend on Safehouse policy.
  mktemp -d "${SAFEHOUSE_EXTERNAL_ROOT}/${label}.XXXXXX"
}

sft_fake_home() {
  mktemp -d "${SAFEHOUSE_FAKE_HOME_ROOT}/home.XXXXXX"
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
