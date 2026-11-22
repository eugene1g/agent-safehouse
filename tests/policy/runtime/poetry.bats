#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Poetry toolchain tests.
#
# Poetry's macOS layout (Poetry 2.x, via platformdirs):
# - ~/Library/Application Support/pypoetry/   Config dir and data dir, which
#                                             coincide on macOS. Itself cannot be
#                                             created or moved in sandbox.
#   - config.toml     User config (repositories, virtualenvs.*, ...).
#                     Read-only in sandbox.
#   - auth.toml       Repository credentials, when keyring is unavailable.
#   - pyproject.toml  Manifest of Poetry's own plugins (`poetry self`).
#   - venv/           Poetry itself, when installed by the official installer.
#                     Read-only in sandbox.
#   - python/         Interpreters installed by `poetry python install`.
#                     Read-only in sandbox.
# - ~/Library/Caches/pypoetry/                Writable.
#   - cache/          Repository metadata cache.
#   - artifacts/      Downloaded wheels and sdists, reused across projects.
#   - virtualenvs/    Project venvs (default location), reused outside sandbox.
# - ~/.local/bin/poetry                       Symlink to Poetry itself, created by
#                                             the official installer or by pipx.
#
# Poetry install types (see Poetry's install docs):
# - (pipx)              pipx install poetry. Recommended by Poetry's docs.
#                       Uses pipx's uv backend when available, since it installs
#                       much faster, else its pip backend. Either backend puts
#                       Poetry in the same places.
# - (official installer) install.python-poetry.org, into the data dir's venv/.
#
load ../../test_helper.bash

# Skip install of any Poetry dependency released in the last N days,
# to reduce exposure to freshly-published supply chain compromises
# NOTE: Duplicated in `pipx install --cooldown=` and `SFT_POETRY_INSTALL_COOLDOWN_DAYS=`
SFT_POETRY_INSTALL_COOLDOWN_DAYS=4

# Minimal test package to install
SFT_POETRY_TEST_PKG="cowsay"
SFT_POETRY_TEST_PKG_VERSION="6.1"

# Minimal Poetry plugin to install, which adds the `poetry export` command
SFT_POETRY_TEST_PLUGIN="poetry-plugin-export"
# TODO: Use the latest floating version that the cooldown allows,
#       rather than a pinned version
# NOTE: Pinned to a release older than SFT_POETRY_INSTALL_COOLDOWN_DAYS,
#       as of the time of writing, 2026-11-22.
SFT_POETRY_TEST_PLUGIN_VERSION="1.10.1"

# Python version to install with `poetry python install`
SFT_POETRY_TEST_PYTHON_VERSION="3.14"

# ------------------------------------------------------------------------------
# Tests

setup_file() {
  # Skip tests if poetry or pipx not installed.
  local poetry_bin pipx_root uv_bin
  poetry_bin="$(command -v poetry || true)"
  [ -n "$poetry_bin" ] || skip "poetry is not installed"
  export SFT_PIPX_BIN
  SFT_PIPX_BIN="$(command -v pipx || true)"
  [ -n "$SFT_PIPX_BIN" ] || skip "pipx is not installed"

  # Share one pip cache across this file's installs outside the sandbox,
  # so that Poetry and its dependencies are only downloaded once
  export SFT_POETRY_PIP_CACHE_DIR="${BATS_FILE_TMPDIR}/pip-cache"

  # Skip compiling .pyc files in per-test installs of Poetry outside the sandbox,
  # which mostly run only a few Poetry commands, to save CPU time
  # NOTE: Not for the copy installed below, which most tests use
  # NOTE: PIP_COMPILE=0 disables compiling. PIP_NO_COMPILE=1 does not:
  #       pip reads it inverted, as with PIP_NO_CACHE_DIR.
  export SFT_POETRY_PIP_COMPILE=0

  # Pick uv backend for per-test installs of Poetry outside the sandbox
  # when possible, else fallback to pip. Share one uv cache across tests.
  # NOTE: Calls to pipx that need uv put SFT_POETRY_UV_DIR back on PATH.
  export SFT_POETRY_PIPX_BACKEND=pip \
    SFT_POETRY_UV_DIR="" \
    SFT_POETRY_UV_CACHE_DIR="${BATS_FILE_TMPDIR}/uv-cache"
  if uv_bin="$(command -v uv)" \
      && "$SFT_PIPX_BIN" install --help 2>/dev/null | grep -q -- '--backend'; then
    SFT_POETRY_PIPX_BACKEND=uv
    SFT_POETRY_UV_DIR="$(dirname "$uv_bin")"
  fi

  # 1. Install a copy of the Poetry on PATH, at the same version,
  #    into BATS_FILE_TMPDIR with pipx.
  #     - Why: The Poetry on PATH may live under the host HOME, which would be
  #       unreadable inside the sandbox's fake HOME
  # 2. Set SFT_POETRY_VERSION to its version and SFT_POETRY_BIN to its path.
  export SFT_POETRY_VERSION
  SFT_POETRY_VERSION="$("$poetry_bin" --version | sed -n 's/^Poetry (version \(.*\))$/\1/p')"
  [ -n "$SFT_POETRY_VERSION" ] || return 1
  pipx_root="${BATS_FILE_TMPDIR}/pipx"
  sft_poetry_pipx_install_into "$pipx_root" || return 1
  export SFT_POETRY_BIN="${pipx_root}/bin/poetry"
  [ -x "$SFT_POETRY_BIN" ] || return 1

  # Freeze the interpreter/dependency versions that the Poetry copy uses,
  # which pipx's cooldown vetted. Tests that run Poetry's official installer
  # will be limited to using the same versions.
  export SFT_POETRY_BASE_PYTHON SFT_POETRY_CONSTRAINTS="${BATS_FILE_TMPDIR}/poetry-constraints.txt"
  SFT_POETRY_BASE_PYTHON="$("${pipx_root}/home/venvs/poetry/bin/python" -c \
    'import sys; print(sys._base_executable)')" || return 1
  "${pipx_root}/home/venvs/poetry/bin/python" -c \
    'import importlib.metadata as m; print("\n".join(sorted({d.metadata["Name"] + "==" + d.version for d in m.distributions()})))' \
    > "$SFT_POETRY_CONSTRAINTS" || return 1
}

teardown() {
  sft_poetry_cleanup_global_install
  sft_poetry_release_global_lock
  sft_teardown_test_env
}

# === Basics ===

@test "[EXECUTION] poetry --version works" {
  safehouse_run -- "$SFT_POETRY_BIN" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_POETRY_VERSION"
}

@test "[EXECUTION] poetry about, cache list, and python list work on a fresh home directory, without creating Poetry's config and data directory" {
  local fake_home poetry_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  poetry_dir="${fake_home}/Library/Application Support/pypoetry"

  # Ensure `poetry about` works
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" about
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Poetry-Core Version"

  # Ensure `poetry cache list` works, reporting no caches
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" cache list
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "No caches found"

  # Ensure `poetry python list` works
  # NOTE: Looks for Poetry-managed interpreters in the data dir's python/,
  #       which does not exist.
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" python list
  [ "$status" -eq 0 ]

  # Ensure none of the above created Poetry's config and data directory
  sft_assert_path_absent "$poetry_dir"
}

@test "[EXECUTION] poetry config and poetry self fail on a fresh home directory" {
  local fake_home poetry_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  poetry_dir="${fake_home}/Library/Application Support/pypoetry"

  # Ensure each fails creating Poetry's config directory,
  # with an error that names the directory the user must create

  # NOTE: `poetry config` creates config.toml even to only read config.
  HOME="$fake_home" safehouse_denied -- "$SFT_POETRY_BIN" config --list
  sft_assert_contains "$output" "Operation not permitted"
  sft_assert_contains "$output" "$poetry_dir"

  HOME="$fake_home" safehouse_denied -- "$SFT_POETRY_BIN" self show
  sft_assert_contains "$output" "Operation not permitted"
  sft_assert_contains "$output" "$poetry_dir"

  sft_assert_path_absent "$poetry_dir"
}

@test "[EXECUTION] Poetry's config and data directory cannot be created inside the sandbox" {
  local fake_home poetry_dir name
  fake_home="$(sft_poetry_fake_home)" || return 1
  poetry_dir="${fake_home}/Library/Application Support/pypoetry"

  # NOTE: Creating a directory is indistinguishable from moving a
  #       pre-filled one into place, which would plant config, plugins,
  #       Poetry itself, or interpreters.

  # Ensure cannot create the directory
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "$poetry_dir"
  sft_assert_path_absent "$poetry_dir"

  # Outside sandbox, create the directory empty
  mkdir "$poetry_dir" || return 1

  # Ensure cannot create the config files Poetry reads,
  # - config.toml can define repositories
  # - auth.toml holds their credentials
  # - pyproject.toml lists plugins that `poetry self` installs into Poetry's
  #   own environment
  for name in config.toml auth.toml pyproject.toml; do
    HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${poetry_dir}/${name}"
  done

  # Ensure cannot create the directories that hold Poetry itself and its interpreters
  for name in venv python; do
    HOME="$fake_home" safehouse_denied -- /bin/mkdir "${poetry_dir}/${name}"
  done
  [ -z "$(ls -A "$poetry_dir")" ]
}

# === Local Installs: Allowed ===

@test "[EXECUTION] poetry new can create a project in the workspace" {
  local fake_home project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "sft-poetry-new-probe")" || return 1

  # Ensure `poetry new` works
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" new --no-interaction "$project_dir"
  sft_assert_file_exists "${project_dir}/pyproject.toml"
  sft_assert_file_exists "${project_dir}/src/sft_poetry_new_probe/__init__.py"
  sft_assert_contains "$(cat "${project_dir}/pyproject.toml")" 'name = "sft-poetry-new-probe"'

  # Ensure the new project is usable
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" check
}

@test "[EXECUTION] poetry install can install project dependencies into an in-project .venv" {
  local fake_home project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_in_project")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-in-project-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1

  # Configure an in-project .venv with project config, as a user would
  # NOTE: Equivalent to POETRY_VIRTUALENVS_IN_PROJECT=true, which the sandbox
  #       does not pass through by default.
  printf '[virtualenvs]\nin-project = true\n' > "${project_dir}/poetry.toml" || return 1

  # Ensure install works
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" install --no-root --no-interaction
  sft_assert_file_exists "${project_dir}/poetry.lock"
  HOME="$fake_home" sft_poetry_assert_test_pkg_installed "${project_dir}/.venv"

  # Ensure Poetry reports the in-project .venv as the project's venv
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" -C "$project_dir" env info --path
  [ "$status" -eq 0 ]
  [ "$output" = "${project_dir}/.venv" ]

  # Ensure installing again against the existing lock file works,
  # which is the path CI and repeat agent runs take
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" install --no-root --no-interaction
}

@test "[EXECUTION] poetry install can install project dependencies into a venv in Poetry's virtualenvs cache" {
  local fake_home project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_cache_venv")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-cache-venv-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1

  # Ensure install works
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" install --no-root --no-interaction
  sft_assert_file_exists "${project_dir}/poetry.lock"
  sft_assert_path_absent "${project_dir}/.venv"

  # Ensure the venv is in Poetry's virtualenvs cache
  local venv_dir
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" -C "$project_dir" env info --path
  [ "$status" -eq 0 ]
  venv_dir="$output"
  [[ "$venv_dir" == "${fake_home}/Library/Caches/pypoetry/virtualenvs/sft-poetry-cache-venv-probe-"* ]]
  HOME="$fake_home" sft_poetry_assert_test_pkg_installed "$venv_dir"

  # Ensure downloads went to Poetry's artifacts cache
  [ -n "$(find "${fake_home}/Library/Caches/pypoetry/artifacts" -name '*.whl' -print -quit)" ]
}

@test "[EXECUTION] poetry install can install the root project in editable mode" {
  local fake_home project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_editable")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-editable-probe" || return 1
  printf '[virtualenvs]\nin-project = true\n' > "${project_dir}/poetry.toml" || return 1

  # Create the root project's package, marked "before"
  mkdir -p "${project_dir}/src/sft_poetry_editable_probe" || return 1
  printf 'VALUE = "before"\n' > "${project_dir}/src/sft_poetry_editable_probe/__init__.py" || return 1

  # Install the root project, which Poetry always installs in editable mode
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" install --no-interaction

  # Ensure installed project has "before" marker
  HOME="$fake_home" safehouse_run -- "${project_dir}/.venv/bin/python" -c \
    "import sft_poetry_editable_probe as m; print(m.VALUE)"
  [ "$status" -eq 0 ]
  [ "$output" = "before" ]

  # Modify project's source to have "after" marker
  printf 'VALUE = "after"\n' > "${project_dir}/src/sft_poetry_editable_probe/__init__.py" || return 1

  # Ensure installed project now has "after" marker, without reinstalling
  HOME="$fake_home" safehouse_run -- "${project_dir}/.venv/bin/python" -c \
    "import sft_poetry_editable_probe as m; print(m.VALUE)"
  [ "$status" -eq 0 ]
  [ "$output" = "after" ]
}

@test "[EXECUTION] poetry add can add a dependency to a project and lock it" {
  local fake_home project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_add")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-add-probe" || return 1
  printf '[virtualenvs]\nin-project = true\n' > "${project_dir}/poetry.toml" || return 1

  # Ensure `poetry add` can rewrite pyproject.toml, write the lock file,
  # and install the dependency into the project's venv
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" add --no-interaction \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}"
  sft_assert_contains "$(cat "${project_dir}/pyproject.toml")" \
    "\"${SFT_POETRY_TEST_PKG} (==${SFT_POETRY_TEST_PKG_VERSION})\""
  sft_assert_contains "$(cat "${project_dir}/poetry.lock")" "name = \"${SFT_POETRY_TEST_PKG}\""
  HOME="$fake_home" sft_poetry_assert_test_pkg_installed "${project_dir}/.venv"
}

@test "[EXECUTION] poetry remove can remove a dependency from a project and its venv" {
  local fake_home project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_remove")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-remove-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1
  printf '[virtualenvs]\nin-project = true\n' > "${project_dir}/poetry.toml" || return 1

  # Install the dependency (outside the sandbox)
  HOME="$fake_home" "$SFT_POETRY_BIN" -C "$project_dir" install --no-root --no-interaction >/dev/null 2>&1 || return 1
  [ -x "${project_dir}/.venv/bin/${SFT_POETRY_TEST_PKG}" ]

  # Ensure `poetry remove` can remove it from pyproject.toml,
  # the lock file and the project's venv
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" remove --no-interaction "$SFT_POETRY_TEST_PKG"
  sft_assert_not_contains "$(cat "${project_dir}/pyproject.toml")" "$SFT_POETRY_TEST_PKG"
  sft_assert_not_contains "$(cat "${project_dir}/poetry.lock")" "name = \"${SFT_POETRY_TEST_PKG}\""
  sft_assert_path_absent "${project_dir}/.venv/bin/${SFT_POETRY_TEST_PKG}"
  HOME="$fake_home" safehouse_denied -- "${project_dir}/.venv/bin/python" -c "import ${SFT_POETRY_TEST_PKG}"
  sft_assert_contains "$output" "No module named '${SFT_POETRY_TEST_PKG}'"
}

@test "[EXECUTION] poetry run can execute a project command" {
  local fake_home project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_run")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-run-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1

  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" install --no-root --no-interaction

  # Ensure `poetry run` can execute a dependency's console script
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" -C "$project_dir" run "$SFT_POETRY_TEST_PKG" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_POETRY_TEST_PKG_VERSION" ]

  # Ensure `poetry run` can execute the venv's interpreter
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" -C "$project_dir" run python -c \
    "import ${SFT_POETRY_TEST_PKG} as pkg; print(pkg.__version__)"
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_POETRY_TEST_PKG_VERSION" ]
}

@test "[EXECUTION] poetry build can build a wheel and sdist into the workspace" {
  local fake_home project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_build")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-build-probe" || return 1
  mkdir -p "${project_dir}/src/sft_poetry_build_probe" || return 1
  printf 'VALUE = "built"\n' > "${project_dir}/src/sft_poetry_build_probe/__init__.py" || return 1

  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" build --no-interaction
  sft_assert_file_exists "${project_dir}/dist/sft_poetry_build_probe-0.0.0-py3-none-any.whl"
  sft_assert_file_exists "${project_dir}/dist/sft_poetry_build_probe-0.0.0.tar.gz"
}

# === Global Installs: Denied ===

@test "[EXECUTION] poetry install with virtualenvs.create=false cannot install a package into the interpreter's global site-packages or bin directory (python.org)" {
  # Targets: /Library/Frameworks/Python.framework/Versions/3.X/{lib/python3.X/site-packages,bin}
  sft_poetry_use_python python.org
  sft_poetry_test_no_venv_install_denied
}
@test "[EXECUTION] poetry install with virtualenvs.create=false cannot install a package into the interpreter's global site-packages or bin directory (Homebrew)" {
  # Targets: $(brew --prefix)/lib/python3.X/site-packages, $(brew --prefix)/bin
  # NOTE: Poetry ignores PEP 668's EXTERNALLY-MANAGED marker, which Homebrew's
  #       interpreter has, so the sandbox is what refuses the install.
  sft_poetry_use_python homebrew
  sft_poetry_test_no_venv_install_denied
}
sft_poetry_test_no_venv_install_denied() {
  local fake_home project_dir poetry_root poetry_bin
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_no_venv")" || return 1

  # Precondition: site-packages is writable unsandboxed
  sft_poetry_require_global_install_target || return 1

  # Install a copy of Poetry that runs on the interpreter under test
  # NOTE: With virtualenvs.create=false and no active venv, Poetry installs
  #       into the base interpreter of the Python that Poetry itself runs on,
  #       regardless of PATH.
  poetry_root="${BATS_TEST_TMPDIR}/pipx"
  sft_poetry_pipx_install_into "$poetry_root" --python "$SFT_POETRY_PYTHON_BIN" || return 1
  poetry_bin="${poetry_root}/bin/poetry"
  [ "$("${poetry_root}/home/venvs/poetry/bin/python" -c 'import sys; print(sys.base_prefix)')" = \
    "$("$SFT_POETRY_PYTHON_BIN" -c 'import sys; print(sys.prefix)')" ]

  # Configure the project to install without a venv
  sft_poetry_write_project "$project_dir" "sft-poetry-no-venv-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1
  printf '[virtualenvs]\ncreate = false\n' > "${project_dir}/poetry.toml" || return 1

  # Ensure cannot install the dependency globally
  SFT_POETRY_GLOBAL_DIRTY=1
  HOME="$fake_home" safehouse_denied -- "$poetry_bin" -C "$project_dir" install --no-root --no-interaction
  sft_assert_contains "$output" "Operation not permitted"
  sft_assert_path_absent "${SFT_POETRY_SITE_PACKAGES}/${SFT_POETRY_TEST_PKG}"
  sft_assert_path_absent "${SFT_POETRY_SCRIPTS_DIR}/${SFT_POETRY_TEST_PKG}"
}

@test "[EXECUTION] poetry self add cannot install a plugin into Poetry's own environment (pipx)" {
  sft_poetry_test_self_add_denied pipx
}
@test "[EXECUTION] poetry self add cannot install a plugin into Poetry's own environment (official installer)" {
  sft_poetry_test_self_add_denied official
}
sft_poetry_test_self_add_denied() {
  local install_type="$1"

  local fake_home venv_dir poetry_bin site_dir config_dir snapshot_before
  fake_home="$(sft_poetry_fake_home)" || return 1
  sft_poetry_install_outside_sandbox "$install_type" "$fake_home" || return 1
  venv_dir="$SFT_POETRY_VENV_DIR"
  poetry_bin="${fake_home}/.local/bin/poetry"
  site_dir="$(sft_poetry_site_packages "$venv_dir")" || return 1
  snapshot_before="$(sft_poetry_snapshot "$venv_dir" "$poetry_bin")" || return 1

  # Precondition: the pre-installed Poetry runs inside the sandbox,
  # so that the denials below are not just a failure to start
  HOME="$fake_home" safehouse_run -- "$poetry_bin" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_POETRY_VERSION"

  # Ensure cannot add a plugin
  # NOTE: `poetry self add` adds any package to Poetry's own environment,
  #       so the test package stands in for a plugin.
  # NOTE: Fails writing to Poetry's config dir, which holds the manifest of
  #       Poetry's own environment, before touching that environment.
  HOME="$fake_home" safehouse_denied -- "$poetry_bin" self add --no-interaction \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}"
  sft_assert_contains "$output" "Operation not permitted"
  sft_assert_contains "$output" "${fake_home}/Library/Application Support/pypoetry"

  # Ensure cannot add a plugin even with Poetry's config dir moved into the
  # workspace, which a sandboxed process can do, so that Poetry gets as far
  # as installing into its own environment
  config_dir="$(sft_workspace_path "poetry_config")" || return 1
  HOME="$fake_home" safehouse_denied -- /usr/bin/env \
    POETRY_CONFIG_DIR="$config_dir" POETRY_DATA_DIR="$config_dir" \
    "$poetry_bin" self add --no-interaction \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}"
  sft_assert_contains "$output" "Operation not permitted"
  sft_assert_contains "$output" "$venv_dir"

  # Ensure nothing changed
  sft_assert_path_absent "${site_dir}/${SFT_POETRY_TEST_PKG}"
  sft_assert_path_absent "${venv_dir}/bin/${SFT_POETRY_TEST_PKG}"
  [ "$(sft_poetry_snapshot "$venv_dir" "$poetry_bin")" = "$snapshot_before" ]
}

@test "[EXECUTION] the official Poetry installer cannot install Poetry globally" {
  local fake_home installer poetry_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  installer="$(sft_poetry_official_installer)" || return 1
  poetry_dir="${fake_home}/Library/Application Support/pypoetry"

  # Ensure ~/.local/bin exists, as it does for many users,
  # so that the installer is not stopped merely by failing to create it
  mkdir -p "${fake_home}/.local/bin" || return 1

  # Ensure cannot install, with no Poetry config and data directory yet
  HOME="$fake_home" safehouse_denied -- /usr/bin/env PIP_CONSTRAINT="$SFT_POETRY_CONSTRAINTS" \
    "$SFT_POETRY_BASE_PYTHON" "$installer" --version "$SFT_POETRY_VERSION" --yes
  sft_assert_contains "$output" "Operation not permitted"
  sft_assert_path_absent "$poetry_dir"
  sft_assert_path_absent "${fake_home}/.local/bin/poetry"

  # Ensure cannot install, with a Poetry config and data directory
  # created outside the sandbox
  mkdir "$poetry_dir" || return 1
  HOME="$fake_home" safehouse_denied -- /usr/bin/env PIP_CONSTRAINT="$SFT_POETRY_CONSTRAINTS" \
    "$SFT_POETRY_BASE_PYTHON" "$installer" --version "$SFT_POETRY_VERSION" --yes
  sft_assert_contains "$output" "Operation not permitted"
  [ -z "$(ls -A "$poetry_dir")" ]
  sft_assert_path_absent "${fake_home}/.local/bin/poetry"
}

# === Pre-Installed Global Tools: Usable, Immutable ===
#
# Setup installs Poetry outside the sandbox, as a user would before starting an agent.

@test "[EXECUTION] a pre-installed Poetry runs (pipx)" {
  sft_poetry_test_preinstalled_runs pipx
}
@test "[EXECUTION] a pre-installed Poetry runs (official installer)" {
  sft_poetry_test_preinstalled_runs official
}
sft_poetry_test_preinstalled_runs() {
  local install_type="$1"

  local fake_home poetry_bin
  fake_home="$(sft_poetry_fake_home)" || return 1
  sft_poetry_install_outside_sandbox "$install_type" "$fake_home" || return 1
  poetry_bin="${fake_home}/.local/bin/poetry"

  # Ensure can run Poetry, via its ~/.local/bin symlink into its venv
  HOME="$fake_home" safehouse_run -- "$poetry_bin" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_POETRY_VERSION"

  # Ensure Poetry can do real work, installing a project's dependencies
  local project_dir
  project_dir="$(sft_workspace_path "poetry_preinstalled_runs")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-preinstalled-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1
  printf '[virtualenvs]\nin-project = true\n' > "${project_dir}/poetry.toml" || return 1
  HOME="$fake_home" safehouse_ok -- "$poetry_bin" -C "$project_dir" install --no-root --no-interaction
  HOME="$fake_home" sft_poetry_assert_test_pkg_installed "${project_dir}/.venv"
}

@test "[EXECUTION] a pre-installed Poetry cannot be modified (pipx)" {
  sft_poetry_test_preinstalled_immutable pipx
}
@test "[EXECUTION] a pre-installed Poetry cannot be modified (official installer)" {
  sft_poetry_test_preinstalled_immutable official
}
sft_poetry_test_preinstalled_immutable() {
  local install_type="$1"

  local fake_home venv_dir root_dir poetry_bin site_dir pkg_dir snapshot_before
  fake_home="$(sft_poetry_fake_home)" || return 1
  sft_poetry_install_outside_sandbox "$install_type" "$fake_home" || return 1
  venv_dir="$SFT_POETRY_VENV_DIR"
  root_dir="$SFT_POETRY_ROOT_DIR"
  poetry_bin="${fake_home}/.local/bin/poetry"
  site_dir="$(sft_poetry_site_packages "$venv_dir")" || return 1
  pkg_dir="${site_dir}/poetry"
  sft_assert_file_exists "${pkg_dir}/__version__.py"
  snapshot_before="$(sft_poetry_snapshot "$venv_dir" "$poetry_bin")" || return 1

  # Ensure cannot modify Poetry with `poetry self` subcommands, with Poetry's
  # config dir moved into the workspace, so that they get as far as Poetry's
  # own environment. (Without the move, they fail earlier, writing to the
  # config dir. See the `poetry self add` tests.)
  # NOTE: May succeed without writing anything, when Poetry and its
  #       dependencies are already at their latest versions.
  #       The snapshot comparison below catches any write.
  # NOTE: `poetry self` subcommands intentionally not tested:
  #       - `poetry self remove`: Needs a plugin to remove, which the `poetry self add`
  #         tests show cannot be added.
  #       - `poetry self lock`: Writes only the config dir.
  local config_dir
  config_dir="$(sft_workspace_path "poetry_config")" || return 1
  HOME="$fake_home" safehouse_run -- /usr/bin/env \
    POETRY_CONFIG_DIR="$config_dir" POETRY_DATA_DIR="$config_dir" \
    "$poetry_bin" self update --no-interaction
  HOME="$fake_home" safehouse_run -- /usr/bin/env \
    POETRY_CONFIG_DIR="$config_dir" POETRY_DATA_DIR="$config_dir" \
    "$poetry_bin" self install --no-interaction

  # Ensure cannot write to Poetry directly,
  # including a sitecustomize.py, which would run on every `poetry` invocation
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${venv_dir}/bin/poetry"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${pkg_dir}/__version__.py"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${site_dir}/sitecustomize.py"
  HOME="$fake_home" safehouse_denied -- /bin/rm "$poetry_bin"

  # Ensure cannot move Poetry out from under the read-only rule,
  # where it could be modified and then moved back
  HOME="$fake_home" safehouse_denied -- /bin/mv "$venv_dir" "$(sft_workspace_path "moved_poetry_venv")"
  HOME="$fake_home" safehouse_denied -- /bin/mv "$root_dir" "$(sft_workspace_path "moved_poetry_root")"

  # Ensure cannot hard link Poetry into the workspace, to modify it there
  HOME="$fake_home" safehouse_denied -- /bin/ln "${pkg_dir}/__version__.py" "$(sft_workspace_path "linked_poetry_version")"

  # Ensure Poetry still runs
  HOME="$fake_home" safehouse_run -- "$poetry_bin" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_POETRY_VERSION"

  # Ensure nothing changed
  sft_assert_path_absent "${site_dir}/sitecustomize.py"
  [ -d "$root_dir" ]
  [ "$(sft_poetry_snapshot "$venv_dir" "$poetry_bin")" = "$snapshot_before" ]
}

@test "[EXECUTION] a Poetry plugin installed outside the sandbox is usable (pipx)" {
  sft_poetry_test_plugin_usable pipx
}
@test "[EXECUTION] a Poetry plugin installed outside the sandbox is usable (official installer)" {
  sft_poetry_test_plugin_usable official
}
sft_poetry_test_plugin_usable() {
  local install_type="$1"

  local fake_home poetry_bin project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  sft_poetry_install_outside_sandbox "$install_type" "$fake_home" || return 1
  poetry_bin="${fake_home}/.local/bin/poetry"
  project_dir="$(sft_workspace_path "poetry_plugin")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-plugin-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1

  # Precondition: Poetry lacks the plugin's command until the plugin is installed
  HOME="$fake_home" safehouse_run -- "$poetry_bin" -C "$project_dir" export --help
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "The requested command export does not exist"

  # Install plugin
  sft_poetry_plugin_install_outside_sandbox "$install_type" "$fake_home" || return 1

  # Ensure can use the plugin's command
  HOME="$fake_home" safehouse_ok -- "$poetry_bin" -C "$project_dir" lock --no-interaction
  HOME="$fake_home" safehouse_run -- "$poetry_bin" -C "$project_dir" export \
    --no-interaction --without-hashes --format requirements.txt
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}"
}

@test "[EXECUTION] a project venv created outside the sandbox in Poetry's virtualenvs cache is usable by poetry run" {
  # NOTE: Models an agent started in a project the user already ran
  #       `poetry install` in.
  local fake_home project_dir venvs_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_preinstalled_venv")" || return 1
  venvs_dir="${fake_home}/Library/Caches/pypoetry/virtualenvs"
  sft_poetry_write_project "$project_dir" "sft-poetry-preinstalled-venv-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1

  # Install the project's dependencies outside the sandbox,
  # into a venv in Poetry's virtualenvs cache
  local venv_dir output
  if ! output="$(HOME="$fake_home" "$SFT_POETRY_BIN" -C "$project_dir" install --no-root --no-interaction 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  venv_dir="$(echo "${venvs_dir}"/sft-poetry-preinstalled-venv-probe-*)"
  [ -d "$venv_dir" ]

  # Ensure `poetry run` uses that venv
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" -C "$project_dir" env info --path
  [ "$status" -eq 0 ]
  [ "$output" = "$venv_dir" ]
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" -C "$project_dir" run "$SFT_POETRY_TEST_PKG" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_POETRY_TEST_PKG_VERSION" ]
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" -C "$project_dir" run python -c \
    "import ${SFT_POETRY_TEST_PKG} as pkg; print(pkg.__version__)"
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_POETRY_TEST_PKG_VERSION" ]

  # Ensure `poetry run` did not create another venv
  [ "$(echo "${venvs_dir}"/*)" = "$venv_dir" ]
}

# === Interpreters ===

@test "[EXECUTION] poetry python install cannot install a shared Python interpreter" {
  local fake_home poetry_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  poetry_dir="${fake_home}/Library/Application Support/pypoetry"

  # Ensure cannot install, with no Poetry config and data directory yet
  HOME="$fake_home" safehouse_denied -- "$SFT_POETRY_BIN" python install --no-interaction \
    "$SFT_POETRY_TEST_PYTHON_VERSION"
  sft_assert_contains "$output" "Operation not permitted"
  sft_assert_path_absent "$poetry_dir"

  # Ensure cannot install, with a Poetry config and data directory
  # created outside the sandbox, as by Poetry's official installer
  mkdir "$poetry_dir" || return 1
  HOME="$fake_home" safehouse_denied -- "$SFT_POETRY_BIN" python install --no-interaction \
    "$SFT_POETRY_TEST_PYTHON_VERSION"
  sft_assert_contains "$output" "Operation not permitted"
  [ -z "$(ls -A "$poetry_dir")" ]
}

@test "[EXECUTION] a Poetry-managed interpreter installed outside the sandbox is usable by poetry env use and poetry install" {
  local fake_home python_dir python_bin
  fake_home="$(sft_poetry_fake_home)" || return 1
  sft_poetry_python_install_outside_sandbox "$fake_home" || return 1
  python_dir="$SFT_POETRY_MANAGED_PYTHON_DIR"
  python_bin="$SFT_POETRY_MANAGED_PYTHON_BIN"

  # Ensure Poetry finds the interpreter
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" python list
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$python_bin"

  # Ensure can create a project venv on the interpreter and install into it
  # NOTE: Names the interpreter by path, not by version, since another
  #       interpreter of the same version may be on PATH.
  local project_dir
  project_dir="$(sft_workspace_path "poetry_managed_python")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-managed-python-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1
  printf '[virtualenvs]\nin-project = true\n' > "${project_dir}/poetry.toml" || return 1
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" env use --no-interaction "$python_bin"
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" install --no-root --no-interaction
  HOME="$fake_home" sft_poetry_assert_test_pkg_installed "${project_dir}/.venv"

  # Ensure the venv runs on the interpreter
  HOME="$fake_home" safehouse_run -- "${project_dir}/.venv/bin/python" -c 'import sys; print(sys.base_prefix)'
  [ "$status" -eq 0 ]
  [ "$output" = "$python_dir" ]
}

@test "[EXECUTION] a Poetry-managed interpreter cannot be modified" {
  # NOTE: A Poetry-managed interpreter is the Python home of every venv created from
  #       it, including project venvs that run outside the sandbox. So a write to it
  #       (e.g. a sitecustomize.py in its stdlib) would run inside all of them.

  local fake_home poetry_dir python_dir python_bin stdlib_dir snapshot_before
  fake_home="$(sft_poetry_fake_home)" || return 1
  sft_poetry_python_install_outside_sandbox "$fake_home" || return 1
  poetry_dir="${fake_home}/Library/Application Support/pypoetry"
  python_dir="$SFT_POETRY_MANAGED_PYTHON_DIR"
  python_bin="$SFT_POETRY_MANAGED_PYTHON_BIN"
  stdlib_dir="${python_dir}/lib/python${SFT_POETRY_TEST_PYTHON_VERSION}"
  sft_assert_file_exists "${stdlib_dir}/os.py"
  snapshot_before="$(sft_poetry_snapshot "$python_dir")" || return 1

  # Ensure cannot modify the interpreter with `poetry python` subcommands
  HOME="$fake_home" safehouse_denied -- "$SFT_POETRY_BIN" python install --no-interaction \
    --reinstall "$SFT_POETRY_TEST_PYTHON_VERSION"
  sft_assert_contains "$output" "Operation not permitted"
  # NOTE: `poetry python remove` requires an exact X.Y.Z version,
  #       which python_dir ends in, after the "@".
  # NOTE: Exits 0 even when removal fails, after printing "Failed".
  #       The snapshot comparison below catches any write.
  #       Prints the failure's cause only with -v.
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" -v python remove --no-interaction \
    "${python_dir##*@}"
  sft_assert_contains "$output" "Operation not permitted"

  # Ensure cannot write to the interpreter directly
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "$python_bin"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${stdlib_dir}/os.py"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${stdlib_dir}/sitecustomize.py"

  # Ensure cannot move the interpreter out from under the read-only rule,
  # where it could be modified and then moved back
  HOME="$fake_home" safehouse_denied -- /bin/mv "$python_dir" "$(sft_workspace_path "moved_python")"
  HOME="$fake_home" safehouse_denied -- /bin/mv "${poetry_dir}/python" "$(sft_workspace_path "moved_pythons")"
  HOME="$fake_home" safehouse_denied -- /bin/mv "$poetry_dir" "$(sft_workspace_path "moved_poetry_root")"

  # Ensure cannot hard link the interpreter into the workspace, to modify it there
  HOME="$fake_home" safehouse_denied -- /bin/ln "${stdlib_dir}/os.py" "$(sft_workspace_path "linked_os_py")"

  # Ensure the interpreter still runs
  HOME="$fake_home" safehouse_run -- "$python_bin" -c 'import sys; print(sys.prefix)'
  [ "$status" -eq 0 ]
  [ "$output" = "$python_dir" ]

  # Ensure nothing changed
  sft_assert_path_absent "${stdlib_dir}/sitecustomize.py"
  [ "$(sft_poetry_snapshot "$python_dir")" = "$snapshot_before" ]
}

# === Config & Credentials ===

@test "[EXECUTION] poetry can read user config but not write it" {
  # NOTE: config.toml can define repositories, so a write would repoint
  #       where Poetry fetches from.

  local fake_home poetry_dir config_file
  fake_home="$(sft_poetry_fake_home)" || return 1
  poetry_dir="${fake_home}/Library/Application Support/pypoetry"
  config_file="${poetry_dir}/config.toml"

  # Write user config outside the sandbox, as `poetry config` would
  local config_before
  mkdir "$poetry_dir" || return 1
  printf '%s\n' \
    '[virtualenvs]' \
    'prompt = "sft-probe-prompt"' \
    '' \
    '[repositories.sft]' \
    'url = "https://sft-probe.invalid/simple/"' \
    > "$config_file" || return 1
  config_before="$(cat "$config_file")" || return 1

  # Ensure can read user config
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" config virtualenvs.prompt
  [ "$status" -eq 0 ]
  [ "$output" = "sft-probe-prompt" ]
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" config --list
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "https://sft-probe.invalid/simple/"

  # Ensure cannot write user config with `poetry config`
  HOME="$fake_home" safehouse_denied -- "$SFT_POETRY_BIN" config virtualenvs.prompt "sft-changed"
  sft_assert_contains "$output" "Operation not permitted"
  HOME="$fake_home" safehouse_denied -- "$SFT_POETRY_BIN" config repositories.sft \
    "https://sft-attacker.invalid/simple/"
  sft_assert_contains "$output" "Operation not permitted"
  HOME="$fake_home" safehouse_denied -- "$SFT_POETRY_BIN" config --unset repositories.sft
  sft_assert_contains "$output" "Operation not permitted"

  # Ensure cannot write, replace or move user config directly
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "$config_file"
  HOME="$fake_home" safehouse_denied -- /bin/rm "$config_file"
  HOME="$fake_home" safehouse_denied -- /bin/mv "$poetry_dir" "$(sft_workspace_path "moved_poetry_root")"

  # Ensure nothing changed
  [ "$(cat "$config_file")" = "$config_before" ]
}

@test "[EXECUTION] poetry config --local can write project config in the workspace" {
  local fake_home project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_local_config")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-local-config-probe" || return 1

  # Create an empty user config outside the sandbox
  # NOTE: Every `poetry config` command, even with --local, first creates the
  #       user config.toml if it is missing, which the sandbox denies. So
  #       `poetry config --local` works only once the user has run
  #       `poetry config` outside the sandbox.
  mkdir "${fake_home}/Library/Application Support/pypoetry" || return 1
  : > "${fake_home}/Library/Application Support/pypoetry/config.toml" || return 1

  # Ensure can write project config
  HOME="$fake_home" safehouse_ok -- "$SFT_POETRY_BIN" -C "$project_dir" config --local \
    virtualenvs.in-project true
  sft_assert_contains "$(cat "${project_dir}/poetry.toml")" "in-project = true"

  # Ensure Poetry reads it back
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" -C "$project_dir" config virtualenvs.in-project
  [ "$status" -eq 0 ]
  [ "$output" = "true" ]
}

@test "[EXECUTION] poetry cannot read or write stored repository credentials" {
  # NOTE: Credentials live in the macOS keychain, or in auth.toml
  #       when keyring is unavailable or disabled.
  # NOTE: In the sandbox, Poetry finds keyring unavailable and falls back to
  #       auth.toml. So this test exercises auth.toml.

  local fake_home poetry_dir auth_file auth_before
  fake_home="$(sft_poetry_fake_home)" || return 1
  poetry_dir="${fake_home}/Library/Application Support/pypoetry"
  auth_file="${poetry_dir}/auth.toml"

  # Store credentials outside the sandbox, as `poetry config http-basic.sft`
  # does when keyring is unavailable
  mkdir "$poetry_dir" || return 1
  printf '[repositories.sft]\nurl = "https://sft-probe.invalid/simple/"\n' \
    > "${poetry_dir}/config.toml" || return 1
  printf '[http-basic.sft]\nusername = "sft-user"\npassword = "sft-secret"\n' \
    > "$auth_file" || return 1
  auth_before="$(cat "$auth_file")" || return 1

  # Ensure cannot read stored credentials
  HOME="$fake_home" safehouse_denied -- /bin/cat "$auth_file"
  sft_assert_not_contains "$output" "sft-secret"

  # Ensure cannot write stored credentials, with `poetry config` or directly
  HOME="$fake_home" safehouse_denied -- "$SFT_POETRY_BIN" config http-basic.sft "sft-user2" "sft-secret2"
  sft_assert_contains "$output" "Operation not permitted"
  sft_assert_contains "$output" "$auth_file"
  # NOTE: Exits 0 without writing anything, since Poetry cannot read the
  #       stored username, so finds no credentials to remove.
  #       The comparison below catches any write.
  HOME="$fake_home" safehouse_run -- "$SFT_POETRY_BIN" config --unset http-basic.sft
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "$auth_file"

  # Ensure nothing changed
  [ "$(cat "$auth_file")" = "$auth_before" ]
}

# === Cache Poisoning: Accepted Risk ===

# NOTE: Test characterizes current behavior. Ideal behavior would disallow tampering.
@test "[EXECUTION] can tamper with a project venv in Poetry's virtualenvs cache to place a binary where it will run outside sandbox" {
  local fake_home project_dir
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_tampered_venv")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-tampered-venv-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1

  # Outside sandbox, install the project's dependencies
  # into a venv in Poetry's virtualenvs cache
  local output
  if ! output="$(HOME="$fake_home" "$SFT_POETRY_BIN" -C "$project_dir" install --no-root --no-interaction 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi

  # Locate the venv's console script
  # (at ~/Library/Caches/pypoetry/virtualenvs/<name>-<hash>-py<X.Y>/bin/<pkg>)
  local venv_dirs venv_dir cached_bin
  venv_dirs=("${fake_home}/Library/Caches/pypoetry/virtualenvs/sft-poetry-tampered-venv-probe-"*)
  [ "${#venv_dirs[@]}" -eq 1 ]
  venv_dir="${venv_dirs[0]}"
  cached_bin="${venv_dir}/bin/${SFT_POETRY_TEST_PKG}"
  sft_assert_file_exists "$cached_bin"

  # Inside sandbox, replace the console script
  local fake_bin
  fake_bin="$(sft_workspace_path "fake_cowsay")" || return 1
  printf '%s\n' '#!/bin/sh' "echo \"I'm not cowsay\"" > "$fake_bin"
  HOME="$fake_home" safehouse_ok -- /bin/cp "$fake_bin" "$cached_bin"

  # Outside sandbox, run the console script through Poetry.
  # Ensure the venv ran the replaced script.
  HOME="$fake_home" run "$SFT_POETRY_BIN" -C "$project_dir" run "$SFT_POETRY_TEST_PKG" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "I'm not cowsay"
}

@test "[EXECUTION] a tampered wheel in Poetry's artifacts cache is rejected by a later poetry install outside sandbox" {
  local fake_home project_dir venvs_dir cached_wheels cached_wheel tampered_wheel marker output
  fake_home="$(sft_poetry_fake_home)" || return 1
  project_dir="$(sft_workspace_path "poetry_tampered_wheel")" || return 1
  venvs_dir="${fake_home}/Library/Caches/pypoetry/virtualenvs"
  marker="$(sft_workspace_path "planted_pth_ran")" || return 1
  sft_poetry_write_project "$project_dir" "sft-poetry-tampered-wheel-probe" \
    "${SFT_POETRY_TEST_PKG}==${SFT_POETRY_TEST_PKG_VERSION}" || return 1

  # Outside sandbox, install the project's dependencies,
  # which downloads the test package's wheel into Poetry's artifacts cache
  if ! output="$(HOME="$fake_home" "$SFT_POETRY_BIN" -C "$project_dir" install --no-root --no-interaction 2>&1)"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  sft_assert_contains "$(cat "${project_dir}/poetry.lock")" "sha256:"

  # Locate the cached wheel
  # (at ~/Library/Caches/pypoetry/artifacts/<xx>/<xx>/<xx>/<hash>/<wheel>)
  cached_wheels="$(find "${fake_home}/Library/Caches/pypoetry/artifacts" \
    -name "${SFT_POETRY_TEST_PKG}-${SFT_POETRY_TEST_PKG_VERSION}-*.whl")" || return 1
  [ -n "$cached_wheels" ]
  [ "$(printf '%s\n' "$cached_wheels" | wc -l)" -eq 1 ]
  cached_wheel="$cached_wheels"

  # Make a tampered copy of the wheel, which stays a valid wheel,
  # with an added .pth file that runs on every start of the venv's interpreter
  tampered_wheel="$(sft_workspace_path "tampered.whl")" || return 1
  cp "$cached_wheel" "$tampered_wheel" || return 1
  "$SFT_POETRY_BASE_PYTHON" -c '
import sys, zipfile
with zipfile.ZipFile(sys.argv[1], "a") as whl:
    whl.writestr("sft_tampered.pth", "import os; open(%r, \"w\").close()\n" % sys.argv[2])
' "$tampered_wheel" "$marker" || return 1

  # Inside sandbox, replace the cached wheel
  HOME="$fake_home" safehouse_ok -- /bin/cp "$tampered_wheel" "$cached_wheel"

  # Outside sandbox, remove the project's venv, as `poetry env remove` would,
  # so that the next install reinstalls the wheel from the artifacts cache
  rm -rf "$venvs_dir"/sft-poetry-tampered-wheel-probe-* || return 1

  # Outside sandbox, install the project's dependencies again.
  # Ensure Poetry rejects the cached wheel, because its hash is not in poetry.lock.
  HOME="$fake_home" run "$SFT_POETRY_BIN" -C "$project_dir" install --no-root --no-interaction
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "not found in known hashes"

  # Ensure the planted .pth file was neither installed nor run
  sft_assert_path_absent "$marker"
  [ -z "$(find "$venvs_dir" -name 'sft_tampered.pth' -print -quit)" ]
}

# ------------------------------------------------------------------------------
# Utility

# Prints a new fake home, laid out as on a fresh macOS user account.
sft_poetry_fake_home() {
  local fake_home
  fake_home="$(sft_fake_home)" || return 1
  mkdir -p \
    "${fake_home}/Library/Application Support" \
    "${fake_home}/Library/Caches" || return 1
  printf '%s\n' "$fake_home"
}

# Installs a copy of the Poetry on PATH, at the same version, with pipx,
# into the pipx home, bin dir and man dir under $1.
# Passes any further args to `pipx install`.
sft_poetry_pipx_install_into() {
  local pipx_root="$1"
  shift
  PIPX_HOME="${pipx_root}/home" \
  PIPX_BIN_DIR="${pipx_root}/bin" \
  PIPX_MAN_DIR="${pipx_root}/man" \
    sft_poetry_pipx_install "$@"
}

# Installs a copy of the Poetry on PATH, at the same version, with pipx,
# into the locations PIPX_HOME, PIPX_BIN_DIR, and PIPX_MAN_DIR name.
# Passes any args to `pipx install`.
#
# NOTE: Defaults to the pip backend, so that the venv's interpreter is the one
#       pipx runs on, and not a uv-managed one under the host HOME.
#       Callers that override with `--backend uv` must also pass `--python`.
sft_poetry_pipx_install() {
  local pipx_output
  if ! pipx_output="$(
    PIPX_DEFAULT_BACKEND=pip PIP_CACHE_DIR="$SFT_POETRY_PIP_CACHE_DIR" \
      "$SFT_PIPX_BIN" install --quiet \
        --cooldown "$SFT_POETRY_INSTALL_COOLDOWN_DAYS" \
        "$@" \
        "poetry==${SFT_POETRY_VERSION}" 2>&1
  )"; then
    printf '%s\n' "$pipx_output" >&2
    # If the Poetry on PATH is newer than the cooldown allows,
    # suggest replacing it with an older one
    if [[ "$pipx_output" == *"No matching distribution found for poetry==${SFT_POETRY_VERSION}"* ]]; then
      printf '%s\n' \
        "" \
        "ERROR: The Poetry on PATH ($(command -v poetry)) is version ${SFT_POETRY_VERSION}," \
        "       which was released less than ${SFT_POETRY_INSTALL_COOLDOWN_DAYS} days ago, so poetry.bats" \
        "       cannot install a copy of it. Install an older Poetry, such as with:" \
        "" \
        "         pipx install --force --cooldown=${SFT_POETRY_INSTALL_COOLDOWN_DAYS} poetry" \
        >&2
    fi
    return 1
  fi
}

# Installs a copy of the Poetry on PATH with pipx outside the sandbox,
# into $fake_home's default pipx locations, as a user would.
#
# Global paths created, inside $fake_home:
# - ~/Library/Application Support/pipx/venvs/poetry
# - ~/.local/bin/poetry, a symlink into it
#
# NOTE: Skips compiling .pyc files, to save time. See SFT_POETRY_PIP_COMPILE.
# NOTE: Uses the backend that SFT_POETRY_PIPX_BACKEND names.
sft_poetry_pipx_install_outside_sandbox() {
  local fake_home="$1"
  local -a backend_args=()
  if [ "$SFT_POETRY_PIPX_BACKEND" = uv ]; then
    backend_args=(--backend uv --python "$SFT_POETRY_BASE_PYTHON")
  fi
  PATH="${SFT_POETRY_UV_DIR:+${SFT_POETRY_UV_DIR}:}${PATH}" \
  PIP_COMPILE="$SFT_POETRY_PIP_COMPILE" \
  UV_CACHE_DIR="$SFT_POETRY_UV_CACHE_DIR" \
  HOME="$fake_home" \
  PIPX_HOME="${fake_home}/Library/Application Support/pipx" \
  PIPX_BIN_DIR="${fake_home}/.local/bin" \
  PIPX_MAN_DIR="${fake_home}/.local/share/man" \
    sft_poetry_pipx_install ${backend_args[@]+"${backend_args[@]}"}
}

# Installs a copy of the Poetry on PATH with Poetry's official installer
# outside the sandbox, into $fake_home, as a user would.
#
# Global paths created, inside $fake_home:
# - ~/Library/Application Support/pypoetry/venv
# - ~/.local/bin/poetry, a symlink into it
#
# NOTE: Constrains Poetry's dependencies to the versions pipx's cooldown
#       vetted in setup_file, since the installer has no cooldown of its own.
# NOTE: Skips compiling .pyc files, to save time. See SFT_POETRY_PIP_COMPILE.
sft_poetry_official_install_outside_sandbox() {
  local fake_home="$1" installer output
  installer="$(sft_poetry_official_installer)" || return 1
  if ! output="$(
    HOME="$fake_home" PIP_CONSTRAINT="$SFT_POETRY_CONSTRAINTS" PIP_CACHE_DIR="$SFT_POETRY_PIP_CACHE_DIR" \
    PIP_COMPILE="$SFT_POETRY_PIP_COMPILE" \
      "$SFT_POETRY_BASE_PYTHON" "$installer" --version "$SFT_POETRY_VERSION" --yes 2>&1
  )"; then
    printf '%s\n' "$output" >&2
    return 1
  fi
  [ -x "${fake_home}/.local/bin/poetry" ]
}

# 1. Install a copy of the Poetry on PATH outside the sandbox, into $fake_home,
#    with the given install type: pipx or official (installer).
# 2. Set SFT_POETRY_VENV_DIR to Poetry's own venv, and SFT_POETRY_ROOT_DIR to
#    the directory holding it.
sft_poetry_install_outside_sandbox() {
  local install_type="$1" fake_home="$2"
  case "$install_type" in
    pipx)
      sft_poetry_pipx_install_outside_sandbox "$fake_home" || return 1
      SFT_POETRY_ROOT_DIR="${fake_home}/Library/Application Support/pipx"
      SFT_POETRY_VENV_DIR="${SFT_POETRY_ROOT_DIR}/venvs/poetry"
      ;;
    official)
      sft_poetry_official_install_outside_sandbox "$fake_home" || return 1
      SFT_POETRY_ROOT_DIR="${fake_home}/Library/Application Support/pypoetry"
      SFT_POETRY_VENV_DIR="${SFT_POETRY_ROOT_DIR}/venv"
      ;;
    *)
      echo "unknown Poetry install type: $install_type" >&2
      return 1
      ;;
  esac
}

# Installs the test plugin outside the sandbox, into the Poetry that
# sft_poetry_install_outside_sandbox installed.
#
# NOTE: Avoids `poetry self add`, which re-resolves Poetry's own dependencies
#       to their latest versions, with no cooldown. Instead uses:
#       - (pipx) `pipx inject`, as Poetry's docs suggest for pipx installs.
#       - (official) pip in Poetry's venv, constrained to the versions
#         pipx's cooldown vetted in setup_file.
sft_poetry_plugin_install_outside_sandbox() {
  local install_type="$1" fake_home="$2" output
  local plugin="${SFT_POETRY_TEST_PLUGIN}==${SFT_POETRY_TEST_PLUGIN_VERSION}"
  case "$install_type" in
    pipx)
      output="$(
        PATH="${SFT_POETRY_UV_DIR:+${SFT_POETRY_UV_DIR}:}${PATH}" \
        HOME="$fake_home" \
        PIPX_HOME="${fake_home}/Library/Application Support/pipx" \
        PIPX_BIN_DIR="${fake_home}/.local/bin" \
        PIPX_MAN_DIR="${fake_home}/.local/share/man" \
        PIP_CACHE_DIR="$SFT_POETRY_PIP_CACHE_DIR" UV_CACHE_DIR="$SFT_POETRY_UV_CACHE_DIR" \
          "$SFT_PIPX_BIN" inject --quiet --cooldown "$SFT_POETRY_INSTALL_COOLDOWN_DAYS" \
            poetry "$plugin" 2>&1
      )"
      ;;
    official)
      output="$(
        HOME="$fake_home" PIP_CACHE_DIR="$SFT_POETRY_PIP_CACHE_DIR" \
          "${SFT_POETRY_VENV_DIR}/bin/python" -m pip install --quiet \
            --constraint "$SFT_POETRY_CONSTRAINTS" "$plugin" 2>&1
      )"
      ;;
    *)
      echo "unknown Poetry install type: $install_type" >&2
      return 1
      ;;
  esac || {
    printf '%s\n' "$output" >&2
    return 1
  }
}

# 1. Install a Poetry-managed interpreter outside the sandbox, into $fake_home,
#    with `poetry python install`, as a user would.
# 2. Set SFT_POETRY_MANAGED_PYTHON_DIR to its install directory,
#    and SFT_POETRY_MANAGED_PYTHON_BIN to its python executable.
#
# Global paths created, inside $fake_home:
# - ~/Library/Application Support/pypoetry/python/cpython@X.Y.Z
sft_poetry_python_install_outside_sandbox() {
  local fake_home="$1"

  # Try to install Poetry-managed interpreter outside the sandbox,
  # up to 3 times, to reduce flakiness from Poetry's hard-coded 5s timeout
  # per network operation with no internal retries.
  local attempt output
  local pythons_dir="${fake_home}/Library/Application Support/pypoetry/python"
  for attempt in 1 2 3; do
    if output="$(HOME="$fake_home" "$SFT_POETRY_BIN" python install --no-interaction \
        "$SFT_POETRY_TEST_PYTHON_VERSION" 2>&1)"; then
      break
    fi
    printf 'poetry python install: attempt %s of 3 failed:\n%s\n' "$attempt" "$output" >&2
    [ "$attempt" -lt 3 ] || return 1
    # Remove any partial install, so that the next attempt starts clean
    rm -rf "${pythons_dir:?}/cpython@${SFT_POETRY_TEST_PYTHON_VERSION}".* || return 1
  done

  # Locate installed interpreter
  local python_dir
  for python_dir in "${fake_home}/Library/Application Support/pypoetry/python/cpython@${SFT_POETRY_TEST_PYTHON_VERSION}".*; do
    [ -d "$python_dir" ] || continue
    SFT_POETRY_MANAGED_PYTHON_DIR="$python_dir"
    SFT_POETRY_MANAGED_PYTHON_BIN="${python_dir}/bin/python${SFT_POETRY_TEST_PYTHON_VERSION}"
    [ -x "$SFT_POETRY_MANAGED_PYTHON_BIN" ]
    return
  done
  echo "no Poetry-managed Python ${SFT_POETRY_TEST_PYTHON_VERSION} under ${fake_home}" >&2
  return 1
}

# Prints the path of Poetry's official installer script,
# downloading it once per file.
sft_poetry_official_installer() {
  local installer="${BATS_FILE_TMPDIR}/install-poetry.py"
  if [ ! -f "$installer" ]; then
    curl -fsSL https://install.python-poetry.org -o "${installer}.$$" || return 1
    mv "${installer}.$$" "$installer" || return 1
  fi
  printf '%s\n' "$installer"
}

# Writes a minimal Poetry project to the given directory,
# depending on the given requirements.
sft_poetry_write_project() {
  local project_dir="$1" name="$2" dep deps=""
  shift 2
  for dep in "$@"; do
    deps="${deps:+${deps}, }\"${dep}\""
  done
  mkdir -p "$project_dir" || return 1
  cat > "${project_dir}/pyproject.toml" <<EOF
[project]
name = "${name}"
version = "0.0.0"
requires-python = ">=3.9"
dependencies = [${deps}]

[build-system]
requires = ["poetry-core>=2.0.0,<3.0.0"]
build-backend = "poetry.core.masonry.api"
EOF
}

# Asserts the test package imports and its console script runs
# inside the sandbox, from the given venv.
# NOTE: Call with the HOME that created the venv. A venv under one fake home
#       is unreadable in a sandbox whose HOME is another.
sft_poetry_assert_test_pkg_installed() {
  local venv_dir="$1"

  safehouse_run -- "${venv_dir}/bin/python" -c \
    "import ${SFT_POETRY_TEST_PKG} as pkg; print(pkg.__version__)"
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_POETRY_TEST_PKG_VERSION" ]

  safehouse_run -- "${venv_dir}/bin/${SFT_POETRY_TEST_PKG}" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_POETRY_TEST_PKG_VERSION" ]
}

# 1. Skip the current test if the requested Python install type is absent.
# 2. Set SFT_POETRY_PYTHON_BIN to that install's python3.
#
# NOTE: Duplicate logic in: sft_pip_use_python, sft_uv_use_system_python,
#       sft_poetry_use_python
sft_poetry_use_python() {
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

  export SFT_POETRY_PYTHON_BIN="$python_bin"
}

# 1. Set SFT_POETRY_SITE_PACKAGES and SFT_POETRY_SCRIPTS_DIR to where a global
#    (non-venv) install into SFT_POETRY_PYTHON_BIN lands.
# 2. Hold that interpreter's global-site lock until teardown.
# Skips the test when it cannot be exercised faithfully, since a sandbox
# denial proves nothing there: when the test package was already installed
# globally, or when site-packages is not writable unsandboxed.
#
# NOTE: Duplicate logic in: sft_pip_lock_global_site, sft_poetry_require_global_install_target
sft_poetry_require_global_install_target() {
  SFT_POETRY_SITE_PACKAGES="$("$SFT_POETRY_PYTHON_BIN" -c \
    'import sysconfig; print(sysconfig.get_path("purelib"))')" || return 1
  SFT_POETRY_SCRIPTS_DIR="$("$SFT_POETRY_PYTHON_BIN" -c \
    'import sysconfig; print(sysconfig.get_path("scripts"))')" || return 1

  sft_poetry_acquire_global_lock || return 1

  # Skip if package appears to have been installed before test run started,
  # so that we do NOT adopt it and do NOT uninstall it later.
  [ ! -e "${SFT_POETRY_SITE_PACKAGES}/${SFT_POETRY_TEST_PKG}" ] \
    || skip "${SFT_POETRY_TEST_PKG} is already installed globally"

  [ -w "$SFT_POETRY_SITE_PACKAGES" ] && [ -w "$SFT_POETRY_SCRIPTS_DIR" ] \
    || skip "global site-packages/bin not writable by this user (${SFT_POETRY_SITE_PACKAGES})"
}

# Serializes tests that use one interpreter's global site-packages,
# across pip.bats, uv.bats and poetry.bats in the same bats run.
#
# NOTE: Same lock path used by: sft_pip_acquire_global_lock, sft_uv_acquire_system_lock,
#       sft_poetry_acquire_global_lock
#
# Released by sft_poetry_release_global_lock in teardown.
sft_poetry_acquire_global_lock() {
  local timeout=600 key lock_dir waited=0
  key="$(printf '%s' "$SFT_POETRY_SITE_PACKAGES" | cksum | cut -d' ' -f1)"
  lock_dir="${BATS_RUN_TMPDIR}/sft-pip-global-${key}.lock"

  until mkdir "$lock_dir" 2>/dev/null; do
    if [ "$waited" -ge "$timeout" ]; then
      echo "timed out after ${timeout}s waiting for ${lock_dir}" >&2
      return 1
    fi
    sleep 1
    waited=$((waited + 1))
  done

  SFT_POETRY_GLOBAL_LOCK="$lock_dir"
}

sft_poetry_release_global_lock() {
  [ -n "${SFT_POETRY_GLOBAL_LOCK:-}" ] || return 0
  rmdir "$SFT_POETRY_GLOBAL_LOCK" 2>/dev/null || true
  SFT_POETRY_GLOBAL_LOCK=""
}

# Uninstalls the test package from the global site-packages, in case a test
# that set SFT_POETRY_GLOBAL_DIRTY=1 installed it there despite the sandbox.
sft_poetry_cleanup_global_install() {
  [ "${SFT_POETRY_GLOBAL_DIRTY:-}" = 1 ] || return 0
  "$SFT_POETRY_PYTHON_BIN" -m pip uninstall -y --break-system-packages \
    "$SFT_POETRY_TEST_PKG" >/dev/null 2>&1 || true
  SFT_POETRY_GLOBAL_DIRTY=0
}

# Prints the site-packages directory of the venv at $venv_dir.
#
# NOTE: Duplicate logic in: sft_pipx_site_packages, sft_poetry_site_packages
sft_poetry_site_packages() {
  local venv_dir="$1" site_dir

  for site_dir in "$venv_dir"/lib/python*/site-packages; do
    [ -d "$site_dir" ] || continue
    printf '%s\n' "$site_dir"
    return 0
  done
  echo "no site-packages under ${venv_dir}" >&2
  return 1
}

# Prints a digest of the names, modes, inodes and change times of every path
# under the given paths, without following symlinks.
#
# NOTE: Duplicate logic in: sft_pipx_snapshot, sft_poetry_snapshot
sft_poetry_snapshot() {
  find "$@" -exec /usr/bin/stat -f '%N %Sp %i %z %m' {} + | LC_ALL=C sort | shasum
}
