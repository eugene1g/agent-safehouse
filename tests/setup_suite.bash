#
# Suite-scoped setup:
# - Verifies the host can run Safehouse tests.
# - Stages dist/safehouse.sh into a suite-scoped temp root once per bats run.
# - Removes only the exact suite-scoped root it created.
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

sft_setup_suite() {
  local source_dist_safehouse

  source_dist_safehouse="$(sft_source_dist_path)"

  export SAFEHOUSE_SUITE_ROOT DIST_SAFEHOUSE

  SAFEHOUSE_SUITE_ROOT="$(mktemp -d /tmp/safehouse-bats-suite.XXXXXX)"
  DIST_SAFEHOUSE="${SAFEHOUSE_SUITE_ROOT}/safehouse.sh"

  cp "$source_dist_safehouse" "$DIST_SAFEHOUSE"
  chmod 755 "$DIST_SAFEHOUSE"
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

setup_suite() {
  if ! sft_require_host; then
    echo "ERROR: bats suite requires macOS, sandbox-exec, dist/safehouse.sh, and an unsandboxed terminal session." >&2
    return 1
  fi

  sft_setup_suite
}

teardown_suite() {
  sft_teardown_suite
}
