#
# Suite-scoped helpers, shared by:
# - setup_suite.bash, which calls them once per bats run (`bats -r tests`).
# - test_helper.bash, which calls them once per test when bats did not run
#   setup_suite.bash (e.g. `bats tests/policy/runtime/pip.bats`).
#
# Kept apart from setup_suite.bash because bats warns (BW03) when a test file
# can see a setup_suite function it did not run.
#

sft_require_host() {
  local preflight_policy source_dist_safehouse

  [[ "$(uname -s)" == "Darwin" ]] || return 1
  command -v sandbox-exec >/dev/null 2>&1 || return 1

  source_dist_safehouse="$(sft_source_dist_path)"
  [ -x "$source_dist_safehouse" ] || return 1

  preflight_policy="$(mktemp /tmp/safehouse-bats-preflight.XXXXXX)"
  printf '(version 1)\n(allow default)\n' > "$preflight_policy"

  if ! sandbox-exec -f "$preflight_policy" -- /bin/echo preflight-ok >/dev/null 2>&1; then
    rm -f "$preflight_policy"
    return 1
  fi

  rm -f "$preflight_policy"
}

sft_source_dist_path() {
  local suite_dir repo_root

  suite_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd -P)"
  repo_root="$(cd "${suite_dir}/.." && pwd -P)"
  printf '%s/dist/safehouse.sh\n' "$repo_root"
}

# 1. Verify the host can run Safehouse tests.
# 2. Stage dist/safehouse.sh into a suite-scoped temp root.
# 3. Set SFT_SUITE_SETUP_DONE=1 to signal that steps 1-2 ran.
sft_setup_suite() {
  local source_dist_safehouse

  if ! sft_require_host; then
    echo "ERROR: bats suite requires macOS, sandbox-exec, dist/safehouse.sh, and an unsandboxed terminal session." >&2
    return 1
  fi

  source_dist_safehouse="$(sft_source_dist_path)"

  export SAFEHOUSE_SUITE_ROOT DIST_SAFEHOUSE SFT_SUITE_SETUP_DONE

  SAFEHOUSE_SUITE_ROOT="$(mktemp -d /tmp/safehouse-bats-suite.XXXXXX)"
  DIST_SAFEHOUSE="${SAFEHOUSE_SUITE_ROOT}/safehouse.sh"

  cp "$source_dist_safehouse" "$DIST_SAFEHOUSE"
  chmod 755 "$DIST_SAFEHOUSE"

  SFT_SUITE_SETUP_DONE=1
}

sft_teardown_suite() {
  local path="${SAFEHOUSE_SUITE_ROOT:-}"

  case "$path" in
    /tmp/safehouse-bats-suite.*)
      rm -rf -- "$path"
      ;;
    *)
      printf 'refusing to remove unsafe suite path: %s\n' "$path" >&2
      return 1
      ;;
  esac
}
