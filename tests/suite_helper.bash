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

# Host environment variables that tests may inherit. All others are removed
# by sft_sanitize_env, so that variables such as XDG_DATA_HOME, UV_CACHE_DIR,
# or PIP_INDEX_URL cannot redirect where tools under test read or write.
# Tests that need such a variable set it explicitly.
SFT_ENV_ALLOWED_NAMES=(
  # Process basics
  HOME PATH USER LOGNAME SHELL TMPDIR PWD OLDPWD SHLVL
  # Terminal and locale (LC_* below)
  TERM COLORTERM TERM_PROGRAM TERM_PROGRAM_VERSION LANG TZ
  __CF_USER_TEXT_ENCODING
  # Network
  HTTP_PROXY HTTPS_PROXY NO_PROXY http_proxy https_proxy no_proxy
  NODE_EXTRA_CA_CERTS
  # Host integrations exercised by specific tests
  SSH_AUTH_SOCK  # ssh.bats: launchd listener socket
  SDKROOT
  JAVA_HOME      # toolchains.bats: java test (set on GitHub runners)
  # E2E agent credentials
  ANTHROPIC_API_KEY OPENAI_API_KEY GEMINI_API_KEY
)
SFT_ENV_ALLOWED_PREFIXES=(
  BATS_       # bats internals
  PARALLEL_   # GNU parallel, used by bats --jobs
  SAFEHOUSE_  # test configuration, e.g. SAFEHOUSE_AGENT_TUI_*, SAFEHOUSE_BATS_JOBS
  SFT_        # test helpers
  LC_
)

sft_env_name_allowed() {
  local name="$1" allowed prefix

  for allowed in "${SFT_ENV_ALLOWED_NAMES[@]}"; do
    [ "$name" = "$allowed" ] && return 0
  done
  for prefix in "${SFT_ENV_ALLOWED_PREFIXES[@]}"; do
    case "$name" in "$prefix"*) return 0 ;; esac
  done
  return 1
}

# Removes exported variables not allowed by SFT_ENV_ALLOWED_NAMES/_PREFIXES.
sft_sanitize_env() {
  local name

  while IFS= read -r name; do
    sft_env_name_allowed "$name" || unset "$name" 2>/dev/null || true
  done < <(compgen -e)
}

# 1. Filter the environment to an allowlist.
# 2. Verify the host can run Safehouse tests.
# 3. Stage dist/safehouse.sh into a suite-scoped temp root.
# 4. Set SFT_SUITE_SETUP_DONE=1 to signal that steps 1-3 ran.
sft_setup_suite() {
  local source_dist_safehouse

  sft_sanitize_env

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
