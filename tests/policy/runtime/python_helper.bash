#!/usr/bin/env bash
# Helpers shared by the Python package manager suites:
# pip.bats, pipx.bats, uv.bats, and poetry.bats.
#
# Load after test_helper.bash.

# 1. Skip the current test if the requested Python install type is absent.
# 2. Set SFT_PY_PYTHON_BIN to that install's python3.
# 3. Set SFT_PY_PEP668_FLAG to --break-system-packages for Homebrew, else empty.
#    - Homebrew marks its interpreter EXTERNALLY-MANAGED, so installers refuse
#      system-wide and --user installs unless told otherwise. Tests that target
#      those locations pass this so that the sandbox, not the marker, decides.
#
# Install types: python.org, homebrew
sft_py_use_python() {
  local install_type="$1" python_bin brew_prefix

  case "$install_type" in
    python.org)
      python_bin="/Library/Frameworks/Python.framework/Versions/Current/bin/python3"
      ;;
    homebrew)
      brew_prefix="$(brew --prefix 2>/dev/null || true)"
      [ -n "$brew_prefix" ] || skip "Homebrew is not installed"
      python_bin="${brew_prefix}/bin/python3"
      ;;
    *)
      echo "unknown Python install type: $install_type" >&2
      return 1
      ;;
  esac
  [ -x "$python_bin" ] || skip "${install_type} Python is not installed"

  export SFT_PY_PYTHON_BIN="$python_bin"
  export SFT_PY_PEP668_FLAG=""
  [ "$install_type" != "homebrew" ] || SFT_PY_PEP668_FLAG="--break-system-packages"
}

# 1. Set SFT_PY_SITE_PACKAGES and SFT_PY_SCRIPTS_DIR to where a global
#    (non-venv, non-user) install into SFT_PY_PYTHON_BIN lands.
# 2. Hold that interpreter's global-site lock until teardown.
# 3. Skip the test if package $1 was already installed globally before the
#    test run started, so that the test does NOT adopt it and does NOT
#    uninstall it later.
#
# Needed by any test whose result depends on whether the package is in the
# global site-packages, including --user tests. Notably:
# - pip treats `install --user` as "Requirement already satisfied" if
#   package already installed in global site-packages and installs nothing
# - An import of the package would resolve to a copy installed in the
#   global site-packages if present, even if a --user installed copy
#   was the intended target.
sft_py_lock_global_site() {
  local pkg="$1" key

  SFT_PY_SITE_PACKAGES="$("$SFT_PY_PYTHON_BIN" -c \
    'import sysconfig; print(sysconfig.get_path("purelib"))')" || return 1
  SFT_PY_SCRIPTS_DIR="$("$SFT_PY_PYTHON_BIN" -c \
    'import sysconfig; print(sysconfig.get_path("scripts"))')" || return 1

  # Serialize tests that use this interpreter's global site-packages, across
  # all suites. Parallel tests would otherwise install, see, and uninstall
  # each other's package.
  key="$(printf '%s' "$SFT_PY_SITE_PACKAGES" | cksum | cut -d' ' -f1)"
  sft_acquire_run_lock "pip-global-${key}" || return 1

  [ ! -e "${SFT_PY_SITE_PACKAGES}/${pkg}" ] \
    || skip "${pkg} is already installed globally"
}

# Same as sft_py_lock_global_site, but also skips the test when a global
# install cannot be exercised faithfully, since a sandbox denial proves
# nothing there: when site-packages is not writable unsandboxed.
sft_py_require_global_install_target() {
  local pkg="$1"

  sft_py_lock_global_site "$pkg" || return 1

  [ -w "$SFT_PY_SITE_PACKAGES" ] && [ -w "$SFT_PY_SCRIPTS_DIR" ] \
    || skip "global site-packages/bin not writable by this user (${SFT_PY_SITE_PACKAGES})"
}

# Prints the site-packages directory of the venv at $1.
sft_py_venv_site_packages() {
  local venv_dir="$1" site_dir

  for site_dir in "$venv_dir"/lib/python*/site-packages; do
    [ -d "$site_dir" ] || continue
    printf '%s\n' "$site_dir"
    return 0
  done
  echo "no site-packages under ${venv_dir}" >&2
  return 1
}
