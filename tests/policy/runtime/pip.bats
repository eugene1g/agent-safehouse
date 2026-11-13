#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# pip toolchain tests.
#
# Each behavior runs once per supported Python install type (see python.sb):
# - (python.org)  /Library/Frameworks/Python.framework/Versions/Current/bin/python3
# - (Homebrew)    $(brew --prefix)/bin/python3
# A variant skips when its install type is not present.
#
load ../../test_helper.bash

# Minimal test package to install
SFT_PIP_TEST_PKG="cowsay"
SFT_PIP_TEST_PKG_VERSION="6.1"

# ------------------------------------------------------------------------------
# Tests

teardown() {
  sft_pip_cleanup_global_install
  sft_pip_release_global_lock
  sft_teardown_test_env
}

# === Local Installs: Allowed ===

@test "[EXECUTION] pip --version works (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_version
}
@test "[EXECUTION] pip --version works (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_version
}
sft_pip_test_version() {
  safehouse_run -- "$SFT_PIP_PYTHON_BIN" -m pip --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "pip "
}

@test "[EXECUTION] python -m venv can create a venv with pip (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_venv
}
@test "[EXECUTION] python -m venv can create a venv with pip (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_venv
}
sft_pip_test_venv() {
  local venv_dir
  venv_dir="$(sft_workspace_path "pip_venv")" || return 1

  # Create venv
  safehouse_ok -- "$SFT_PIP_PYTHON_BIN" -m venv "$venv_dir"
  [ -x "${venv_dir}/bin/python" ]
  [ -x "${venv_dir}/bin/pip" ]

  # Ensure venv's pip runs
  safehouse_run -- "${venv_dir}/bin/pip" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$venv_dir"
}

@test "[EXECUTION] pip install can install a package from PyPI into a venv (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_install_pypi
}
@test "[EXECUTION] pip install can install a package from PyPI into a venv (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_install_pypi
}
sft_pip_test_install_pypi() {
  local venv_dir
  venv_dir="$(sft_workspace_path "pip_pypi_venv")" || return 1

  # Ensure ~/Library/Caches exists, as it does for every real macOS user,
  # but not ~/Library/Caches/pip, as on a fresh machine
  mkdir -p "${HOME}/Library/Caches" || return 1

  # Create venv
  safehouse_ok -- "$SFT_PIP_PYTHON_BIN" -m venv "$venv_dir"

  # Download/install test package in venv
  safehouse_ok -- "${venv_dir}/bin/pip" install \
    "${SFT_PIP_TEST_PKG}==${SFT_PIP_TEST_PKG_VERSION}"

  # Ensure the installed package imports inside the sandbox
  sft_pip_assert_pkg_imports "${venv_dir}/bin/python"

  # Ensure the console script in the venv's bin/ runs inside the sandbox
  safehouse_run -- "${venv_dir}/bin/${SFT_PIP_TEST_PKG}" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_PIP_TEST_PKG_VERSION" ]

  # Ensure the download wrote to pip's cache
  local cache_dir
  cache_dir="$(safehouse_ok -- "${venv_dir}/bin/pip" cache dir)" || return 1
  [ -n "$(find "$cache_dir" -type f -print -quit)" ]
}

@test "[EXECUTION] pip install -r can install requirements into a venv (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_install_requirements
}
@test "[EXECUTION] pip install -r can install requirements into a venv (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_install_requirements
}
sft_pip_test_install_requirements() {
  local venv_dir
  venv_dir="$(sft_workspace_path "pip_req_venv")" || return 1

  # Create project directory with a requirements.txt
  local project_dir
  project_dir="$(sft_workspace_path "pip_req_project")" || return 1
  mkdir -p "$project_dir" || return 1
  printf '%s==%s\n' "$SFT_PIP_TEST_PKG" "$SFT_PIP_TEST_PKG_VERSION" \
    > "${project_dir}/requirements.txt"

  # Ensure can install requirements to a venv
  safehouse_ok -- "$SFT_PIP_PYTHON_BIN" -m venv "$venv_dir"
  safehouse_ok -- "${venv_dir}/bin/pip" install -r "${project_dir}/requirements.txt"

  # Ensure the installed package imports inside the sandbox
  sft_pip_assert_pkg_imports "${venv_dir}/bin/python"
}

@test "[EXECUTION] pip install -e can install a workspace project in editable mode (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_install_editable
}
@test "[EXECUTION] pip install -e can install a workspace project in editable mode (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_install_editable
}
sft_pip_test_install_editable() {
  local venv_dir
  venv_dir="$(sft_workspace_path "pip_editable_venv")" || return 1

  # Create project directory with a pyproject.toml and a .py file marked "before"
  # NOTE: Exercises PEP 517 build isolation: pip will download the build backend
  #       into a temp build env.
  local project_dir
  project_dir="$(sft_workspace_path "pip_editable_project")" || return 1
  mkdir -p "$project_dir" || return 1
  cat > "${project_dir}/pyproject.toml" <<'EOF'
[build-system]
requires = ["setuptools>=64"]
build-backend = "setuptools.build_meta"

[project]
name = "sft-pip-editable-probe"
version = "0.0.0"

[tool.setuptools]
py-modules = ["sft_pip_editable_probe"]
EOF
  printf 'VALUE = "before"\n' > "${project_dir}/sft_pip_editable_probe.py"

  # Install project as editable inside venv
  safehouse_ok -- "$SFT_PIP_PYTHON_BIN" -m venv "$venv_dir"
  safehouse_ok -- "${venv_dir}/bin/pip" install -e "$project_dir"

  # Ensure installed project has "before" marker
  safehouse_run -- "${venv_dir}/bin/python" -c \
    "import sft_pip_editable_probe as m; print(m.VALUE)"
  [ "$status" -eq 0 ]
  [ "$output" = "before" ]

  # Modify project directory's .py file to have "after" marker
  printf 'VALUE = "after"\n' > "${project_dir}/sft_pip_editable_probe.py"

  # Ensure installed project now has "after" marker, without reinstalling,
  # which is how "editable" installs are supposed to behave
  safehouse_run -- "${venv_dir}/bin/python" -c \
    "import sft_pip_editable_probe as m; print(m.VALUE)"
  [ "$status" -eq 0 ]
  [ "$output" = "after" ]
}

@test "[EXECUTION] pip install --target can install a package into a workspace directory (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_install_target
}
@test "[EXECUTION] pip install --target can install a package into a workspace directory (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_install_target
}
sft_pip_test_install_target() {
  local target_dir
  target_dir="$(sft_workspace_path "pip_target")" || return 1

  # Install package directly to target directory, without any venv
  safehouse_ok -- "$SFT_PIP_PYTHON_BIN" -m pip install \
    --target "$target_dir" \
    "${SFT_PIP_TEST_PKG}==${SFT_PIP_TEST_PKG_VERSION}"
  [ -d "${target_dir}/${SFT_PIP_TEST_PKG}" ]

  # Ensure can import installed package, when PYTHONPATH=<target>
  # NOTE: Safehouse sanitizes the environment, so PYTHONPATH must be passed explicitly
  PYTHONPATH="$target_dir" safehouse_run --env-pass=PYTHONPATH -- "$SFT_PIP_PYTHON_BIN" -c \
    "import ${SFT_PIP_TEST_PKG} as pkg; print(pkg.__version__)"
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_PIP_TEST_PKG_VERSION" ]
}

@test "[EXECUTION] pip uninstall can remove a package from a venv (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_uninstall
}
@test "[EXECUTION] pip uninstall can remove a package from a venv (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_uninstall
}
sft_pip_test_uninstall() {
  local venv_dir
  venv_dir="$(sft_workspace_path "pip_uninstall_venv")" || return 1

  # Create venv with package installed (outside the sandbox)
  "$SFT_PIP_PYTHON_BIN" -m venv "$venv_dir" || return 1
  "${venv_dir}/bin/pip" install \
    "${SFT_PIP_TEST_PKG}==${SFT_PIP_TEST_PKG_VERSION}" || return 1
  [ -x "${venv_dir}/bin/${SFT_PIP_TEST_PKG}" ]

  # Ensure can uninstall package
  safehouse_ok -- "${venv_dir}/bin/pip" uninstall -y "$SFT_PIP_TEST_PKG"
  [ ! -e "${venv_dir}/bin/${SFT_PIP_TEST_PKG}" ]
  safehouse_denied -- "${venv_dir}/bin/python" -c "import ${SFT_PIP_TEST_PKG}"
}

# === Global Installs: Denied ===
#
# Homebrew variants pass --break-system-packages via $SFT_PIP_PEP668_FLAG
# so that the sandbox, not PEP 668's EXTERNALLY-MANAGED marker, is what refuses
# the install.

@test "[EXECUTION] pip install --user cannot install a package to the user site or its bin directory (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_user_install_denied
}
@test "[EXECUTION] pip install --user cannot install a package to the user site or its bin directory (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_user_install_denied
}
sft_pip_test_user_install_denied() {
  # Prevent a concurrent global install of the package
  # from being detected as "already installed" by `install --user`
  sft_pip_lock_global_site || return 1

  local user_base user_site
  sft_pip_user_dirs || return 1
  user_base="$SFT_PIP_USER_BASE"
  user_site="$SFT_PIP_USER_SITE"

  # Ensure ~/Library exists, as it does for every real macOS user.
  # Otherwise pip fails to create ~/Library/Python for a reason unrelated to the sandbox.
  mkdir -p "${HOME}/Library" || return 1

  # Ensure cannot install --user package
  # shellcheck disable=SC2086  # intentionally unquoted: empty or one flag
  safehouse_denied -- "$SFT_PIP_PYTHON_BIN" -m pip install --user $SFT_PIP_PEP668_FLAG \
    "${SFT_PIP_TEST_PKG}==${SFT_PIP_TEST_PKG_VERSION}"
  [ ! -e "${user_site}/${SFT_PIP_TEST_PKG}" ]
  [ ! -e "${user_base}/bin/${SFT_PIP_TEST_PKG}" ]
}

@test "[EXECUTION] pip install cannot install a package into the interpreter's global site-packages or bin directory (python.org)" {
  # Targets: /Library/Frameworks/Python.framework/Versions/3.X/{lib/python3.X/site-packages,bin}
  sft_pip_use_python python.org
  sft_pip_test_global_install_denied
}
@test "[EXECUTION] pip install cannot install a package into the interpreter's global site-packages or bin directory (Homebrew)" {
  # Targets: $(brew --prefix)/lib/python3.X/site-packages, $(brew --prefix)/bin
  sft_pip_use_python homebrew
  sft_pip_test_global_install_denied
}
sft_pip_test_global_install_denied() {
  # Precondition: site-packages is writable unsandboxed
  sft_pip_require_global_install_target || return 1

  # Ensure cannot install global package
  SFT_PIP_GLOBAL_DIRTY=1
  # shellcheck disable=SC2086
  safehouse_denied -- "$SFT_PIP_PYTHON_BIN" -m pip install $SFT_PIP_PEP668_FLAG \
    "${SFT_PIP_TEST_PKG}==${SFT_PIP_TEST_PKG_VERSION}"
  [ ! -e "${SFT_PIP_SITE_PACKAGES}/${SFT_PIP_TEST_PKG}" ]
  [ ! -e "${SFT_PIP_SCRIPTS_DIR}/${SFT_PIP_TEST_PKG}" ]
}

# === Pre-Installed Global Packages: Usable, Immutable ===
#
# Setup installs outside the sandbox, as a user would before starting an agent.
# --user installs go under a fake HOME;
# global installs touch the real interpreter, so teardown uninstalls them.

@test "[EXECUTION] a pip global installed binary runs (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_global_binary_runs
}
@test "[EXECUTION] a pip global installed binary runs (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_global_binary_runs
}
sft_pip_test_global_binary_runs() {
  # Install package from outside sandbox
  sft_pip_require_global_install_target || return 1
  sft_pip_global_install_outside_sandbox || return 1

  # Ensure package's console script runs
  safehouse_run -- "${SFT_PIP_SCRIPTS_DIR}/${SFT_PIP_TEST_PKG}" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_PIP_TEST_PKG_VERSION" ]
}

@test "[EXECUTION] a pip global installed binary cannot be modified (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_global_binary_immutable
}
@test "[EXECUTION] a pip global installed binary cannot be modified (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_global_binary_immutable
}
sft_pip_test_global_binary_immutable() {
  # Install package from outside sandbox
  local script_path package_dir
  sft_pip_require_global_install_target || return 1
  sft_pip_global_install_outside_sandbox || return 1
  script_path="${SFT_PIP_SCRIPTS_DIR}/${SFT_PIP_TEST_PKG}"
  package_dir="${SFT_PIP_SITE_PACKAGES}/${SFT_PIP_TEST_PKG}"
  [ -e "$script_path" ]
  [ -d "$package_dir" ]

  # Ensure cannot modify installed binary
  sft_pip_assert_installed_pkg_immutable "$script_path" "$package_dir" ""
}

# Run ${user_base}/bin/${SFT_PIP_TEST_PKG} --version inside the sandbox.
@test "[EXECUTION] a pip --user installed global binary runs (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_user_binary_runs
}
@test "[EXECUTION] a pip --user installed global binary runs (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_user_binary_runs
}
sft_pip_test_user_binary_runs() {
  # Prevent a concurrent global install of the package
  # from competing with a --user install when locating the package's binary
  sft_pip_lock_global_site || return 1

  # Install package from outside sandbox, with --user
  sft_pip_user_dirs || return 1
  sft_pip_user_install_outside_sandbox || return 1

  # Ensure binary runs
  safehouse_run -- "${SFT_PIP_USER_BASE}/bin/${SFT_PIP_TEST_PKG}" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_PIP_TEST_PKG_VERSION" ]
}

@test "[EXECUTION] a pip --user installed global package imports from the base interpreter (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_user_package_imports
}
@test "[EXECUTION] a pip --user installed global package imports from the base interpreter (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_user_package_imports
}
sft_pip_test_user_package_imports() {
  # Prevent a concurrent global install of the package
  # from competing with a --user install when importing the package
  sft_pip_lock_global_site || return 1

  # Install package from outside sandbox, with --user
  sft_pip_user_dirs || return 1
  sft_pip_user_install_outside_sandbox || return 1

  # Ensure the installed package imports inside the sandbox
  sft_pip_assert_pkg_imports "$SFT_PIP_PYTHON_BIN"
}

@test "[EXECUTION] a pip --user installed global binary cannot be modified (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_user_binary_immutable
}
@test "[EXECUTION] a pip --user installed global binary cannot be modified (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_user_binary_immutable
}
sft_pip_test_user_binary_immutable() {
  # Prevent a concurrent global install of the package
  # from competing with a --user install when attempting to (re)install its binary
  sft_pip_lock_global_site || return 1

  # Install binary from outside sandbox, with --user
  sft_pip_user_dirs || return 1
  sft_pip_user_install_outside_sandbox || return 1
  [ -e "${SFT_PIP_USER_BASE}/bin/${SFT_PIP_TEST_PKG}" ]
  [ -d "${SFT_PIP_USER_SITE}/${SFT_PIP_TEST_PKG}" ]

  # Ensure cannot modify installed binary
  sft_pip_assert_installed_pkg_immutable \
    "${SFT_PIP_USER_BASE}/bin/${SFT_PIP_TEST_PKG}" \
    "${SFT_PIP_USER_SITE}/${SFT_PIP_TEST_PKG}" \
    "--user"
}

# === Config ===

@test "[EXECUTION] pip can read user config but not write it (python.org)" {
  sft_pip_use_python python.org
  sft_pip_test_config
}
@test "[EXECUTION] pip can read user config but not write it (Homebrew)" {
  sft_pip_use_python homebrew
  sft_pip_test_config
}
sft_pip_test_config() {
  local conf_path
  # For each pip per-user config location on macOS...
  for conf_path in \
    "${HOME}/.config/pip/pip.conf" \
    "${HOME}/.pip/pip.conf"
  do
    # NOTE: Not `|| return 1`: that would disable errexit inside the function
    sft_pip_assert_config_readonly "$conf_path"
  done
}

# Writes a pip config at $1 (as a user would, outside the sandbox), then
# asserts pip honors it and the sandbox cannot modify or remove it.
sft_pip_assert_config_readonly() {
  local conf_path="$1"

  local cache_dir
  # NOTE: pip prints the physical path (/private/var/...), not the /var symlink
  cache_dir="$(cd "$SAFEHOUSE_WORKSPACE" && pwd -P)/pip_configured_cache_$(basename "$(dirname "$conf_path")")"

  # Set configured cache dir location
  mkdir -p "$(dirname "$conf_path")" || return 1
  printf '[global]\ncache-dir = %s\n' "$cache_dir" > "$conf_path"

  # Ensure pip reads it
  # NOTE: Private index location (which may embed a token) lives in pip config,
  #       and must continue to be readable. Docs tell users to put only
  #       read-scoped tokens here.
  safehouse_run -- "$SFT_PIP_PYTHON_BIN" -m pip cache dir
  [ "$status" -eq 0 ]
  [ "$output" = "$cache_dir" ]

  # Ensure cannot rewrite, delete, or extend it
  # NOTE: index-url lives in pip config, so a write would repoint where pip fetches from.
  safehouse_denied -- /bin/sh -c \
    "printf '[global]\nindex-url = https://hijacked.invalid/\n' > '${conf_path}'"
  safehouse_denied -- /bin/rm -f "$conf_path"
  safehouse_denied -- "$SFT_PIP_PYTHON_BIN" -m pip config --user set global.index-url \
    "https://hijacked.invalid/"

  # Ensure unchanged and still honored
  sft_assert_file_contains "$conf_path" "$cache_dir"
  safehouse_run -- "$SFT_PIP_PYTHON_BIN" -m pip cache dir
  [ "$status" -eq 0 ]
  [ "$output" = "$cache_dir" ]

  rm -f "$conf_path"
}

# === Special Permission Checks ===

# Ensure python.sb grants file-write-data on the ~/Library/Caches literal only,
# so pip's cache-dir ownership check (os.access W_OK on the nearest existing
# ancestor) passes on a fresh machine.
@test "[EXECUTION] pip: user cache directory literal is writable but its contents are not broadly" {
  local caches_dir="${HOME}/Library/Caches"
  mkdir -p "$caches_dir"

  # Ensure ~/Library/Caches passes access(W_OK) inside the sandbox
  safehouse_ok -- /bin/sh -c '[ -w "$1" ]' _ "$caches_dir"

  # Ensure creating a sibling of pip/ in ~/Library/Caches is denied
  safehouse_denied -- /bin/mkdir "${caches_dir}/pip-sibling"
  [ ! -e "${caches_dir}/pip-sibling" ]
}

# ------------------------------------------------------------------------------
# Utility

# 1. Skip the current test if the requested Python install type is absent.
# 2. Set SFT_PIP_PYTHON_BIN to that install's python3.
#
# NOTE: pip is driven as `"$SFT_PIP_PYTHON_BIN" -m pip` so the interpreter
#       under test is explicit, regardless of which python3 is first on PATH.
sft_pip_use_python() {
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

  export SFT_PIP_PYTHON_BIN="$python_bin"

  # PEP 668: Homebrew marks its interpreter EXTERNALLY-MANAGED, so pip refuses
  # system-wide and --user installs unless told otherwise. Tests that target
  # those locations pass this so that the sandbox, not the marker, decides.
  export SFT_PIP_PEP668_FLAG=""
  [ "$install_type" != "homebrew" ] || SFT_PIP_PEP668_FLAG="--break-system-packages"
}

# Asserts the test package imports and reports the expected version,
# running under the sandbox with whichever interpreter is given.
sft_pip_assert_pkg_imports() {
  local python_bin="$1"

  safehouse_run -- "$python_bin" -c \
    "import ${SFT_PIP_TEST_PKG} as pkg; print(pkg.__version__)"
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_PIP_TEST_PKG_VERSION" ]
}

# Sets SFT_PIP_USER_BASE and SFT_PIP_USER_SITE for the test's (fake) HOME.
# Computed outside the sandbox by the interpreter under test.
sft_pip_user_dirs() {
  SFT_PIP_USER_BASE="$("$SFT_PIP_PYTHON_BIN" -m site --user-base)" || return 1
  SFT_PIP_USER_SITE="$("$SFT_PIP_PYTHON_BIN" -m site --user-site)" || return 1
  case "$SFT_PIP_USER_BASE" in
    "$HOME"/*) ;;
    *) printf 'user base not under test HOME: %s\n' "$SFT_PIP_USER_BASE" >&2; return 1 ;;
  esac
}

# Sets SFT_PIP_SITE_PACKAGES and SFT_PIP_SCRIPTS_DIR to where a global
# (non-venv, non-user) install lands. Skips the test when it cannot be
# exercised faithfully, since a sandbox denial proves nothing there.
sft_pip_require_global_install_target() {
  # 1. Set SFT_PIP_SITE_PACKAGES and SFT_PIP_SCRIPTS_DIR
  # 2. Acquire global-site lock
  sft_pip_lock_global_site || return 1

  [ -w "$SFT_PIP_SITE_PACKAGES" ] && [ -w "$SFT_PIP_SCRIPTS_DIR" ] \
    || skip "global site-packages/bin not writable by this user (${SFT_PIP_SITE_PACKAGES})"
}

# Sets SFT_PIP_SITE_PACKAGES and SFT_PIP_SCRIPTS_DIR, then holds the
# interpreter's global-site lock until teardown. Skips if the test package
# was already installed globally before the test run started.
#
# Needed by any test whose result depends on whether the test package is in
# the global site-packages, including --user tests. Notably:
# - pip treats `install --user` as "Requirement already satisfied" if
#   package already installed in global site-packages and installs nothing
# - An import of the package would resolve to a copy installed in the
#   global site-packages if present, even if a --user installed copy
#   was the intended target.
sft_pip_lock_global_site() {
  SFT_PIP_SITE_PACKAGES="$("$SFT_PIP_PYTHON_BIN" -c \
    'import sysconfig; print(sysconfig.get_path("purelib"))')" || return 1
  SFT_PIP_SCRIPTS_DIR="$("$SFT_PIP_PYTHON_BIN" -c \
    'import sysconfig; print(sysconfig.get_path("scripts"))')" || return 1

  sft_pip_acquire_global_lock || return 1

  # Skip if package appears to have been installed before test run started,
  # so that we do NOT adopt it and do NOT uninstall it later.
  [ ! -e "${SFT_PIP_SITE_PACKAGES}/${SFT_PIP_TEST_PKG}" ] \
    || skip "${SFT_PIP_TEST_PKG} is already installed globally"
}

# Serializes tests that use one interpreter's global site-packages.
#
# Tests running in parallel targeting the same interpreter would otherwise
# install, see, and uninstall each other's package.
#
# Released by sft_pip_release_global_lock in teardown.
sft_pip_acquire_global_lock() {
  local timeout=600

  local key lock_dir
  key="$(printf '%s' "$SFT_PIP_SITE_PACKAGES" | cksum | cut -d' ' -f1)"
  lock_dir="${BATS_RUN_TMPDIR}/sft-pip-global-${key}.lock"

  # Wait for directory-based lock inside BATS_RUN_TMPDIR (until timeout),
  # which is shared by all parallel workers of the same bats run and which is
  # discarded with the run.
  local waited=0
  until mkdir "$lock_dir" 2>/dev/null; do
    if [ "$waited" -ge "$timeout" ]; then
      echo "timed out after ${timeout}s waiting for ${lock_dir}" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  SFT_PIP_GLOBAL_LOCK="$lock_dir"
}

sft_pip_release_global_lock() {
  [ -n "${SFT_PIP_GLOBAL_LOCK:-}" ] || return 0
  rmdir "$SFT_PIP_GLOBAL_LOCK" 2>/dev/null || true
  SFT_PIP_GLOBAL_LOCK=""
}

# Installs the test package into the interpreter's global site-packages and
# bin, as a user would before starting a sandboxed agent.
# Undone by sft_pip_cleanup_global_install (teardown).
sft_pip_global_install_outside_sandbox() {
  SFT_PIP_GLOBAL_DIRTY=1
  # shellcheck disable=SC2086
  "$SFT_PIP_PYTHON_BIN" -m pip install $SFT_PIP_PEP668_FLAG \
    "${SFT_PIP_TEST_PKG}==${SFT_PIP_TEST_PKG_VERSION}"
}

sft_pip_cleanup_global_install() {
  [ "${SFT_PIP_GLOBAL_DIRTY:-}" = 1 ] || return 0
  # shellcheck disable=SC2086
  "$SFT_PIP_PYTHON_BIN" -m pip uninstall -y $SFT_PIP_PEP668_FLAG \
    "$SFT_PIP_TEST_PKG" >/dev/null 2>&1 || true
  SFT_PIP_GLOBAL_DIRTY=0
}

# Installs the test package under the test's (fake) HOME user base.
sft_pip_user_install_outside_sandbox() {
  # shellcheck disable=SC2086
  "$SFT_PIP_PYTHON_BIN" -m pip install --user $SFT_PIP_PEP668_FLAG \
    "${SFT_PIP_TEST_PKG}==${SFT_PIP_TEST_PKG_VERSION}"
}

# Asserts that an installed package (console script + package dir) cannot be
# removed, reinstalled, or written to from inside the sandbox.
# $3 is "--user" for a user-site install, else empty.
sft_pip_assert_installed_pkg_immutable() {
  local script_path="$1" package_dir="$2" scope="$3"

  local init_file
  init_file="$(find "$package_dir" -maxdepth 1 -name '*.py' -print -quit)"
  [ -n "$init_file" ] || return 1

  # pip uninstall -> denied
  # shellcheck disable=SC2086
  safehouse_denied -- "$SFT_PIP_PYTHON_BIN" -m pip uninstall -y $scope $SFT_PIP_PEP668_FLAG \
    "$SFT_PIP_TEST_PKG"

  # pip install --force-reinstall -> denied
  # shellcheck disable=SC2086
  safehouse_denied -- "$SFT_PIP_PYTHON_BIN" -m pip install --force-reinstall $scope $SFT_PIP_PEP668_FLAG \
    "${SFT_PIP_TEST_PKG}==${SFT_PIP_TEST_PKG_VERSION}"

  # Touch the console script / package files -> denied
  safehouse_denied -- /usr/bin/touch "$script_path"
  safehouse_denied -- /usr/bin/touch "$init_file"
  safehouse_denied -- /usr/bin/touch "${package_dir}/sft_new_file.py"
  safehouse_denied -- /bin/rm -f "$script_path"

  # Still installed and intact
  [ -e "$script_path" ]
  [ -d "$package_dir" ]
  [ ! -e "${package_dir}/sft_new_file.py" ]
}

# ------------------------------------------------------------------------------
