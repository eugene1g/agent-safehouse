#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# uv toolchain tests.
#
load ../../test_helper.bash

# Minimal test package to install
SFT_UV_TEST_PKG="cowsay"
SFT_UV_TEST_PKG_VERSION="6.1"

# Interpreter version to provision: Newest 3.13.x
SFT_UV_TEST_PYTHON_VERSION="3.13"

# Fake private index credential to store via `uv auth login`
SFT_UV_TEST_SERVICE="https://index.safehouse-test.invalid/simple"
SFT_UV_TEST_TOKEN="sft-not-a-real-token"

# ------------------------------------------------------------------------------
# Tests

setup() {
  sft_setup_test_env
  # Setup the default fake $HOME
  sft_create_xdg_home_dirs "$HOME"
}

# 1. Skip tests if uv not installed.
# 2. Set SFT_UV_BIN to uv's path.
setup_file() {
  export SFT_UV_BIN
  SFT_UV_BIN="$(command -v uv || true)"
  [ -n "$SFT_UV_BIN" ] || skip "uv is not installed"
}

teardown() {
  sft_uv_cleanup_system_install
  sft_teardown_test_env
}

# === Basics ===

@test "[EXECUTION] uv --version works" {
  safehouse_ok -- "$SFT_UV_BIN" --version
}

@test "[EXECUTION] uv tool list and uv tool dir work on a fresh home directory, without creating uv's data directories" {
  local fake_home uv_data_dir
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  uv_data_dir="${fake_home}/.local/share/uv"

  # Ensure `uv tool list` works, reporting no tools
  HOME="$fake_home" safehouse_run -- "$SFT_UV_BIN" tool list
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "No tools installed"

  # Ensure `uv tool dir` works, naming the directory without creating it
  HOME="$fake_home" safehouse_run -- "$SFT_UV_BIN" tool dir
  [ "$status" -eq 0 ]
  [ "$output" = "${uv_data_dir}/tools" ]

  # Ensure neither command created uv's data directories
  # NOTE: Only `uvx`, `uv tool run` and `uv tool install` create them,
  #       which the sandbox denies.
  [ ! -e "$uv_data_dir" ]
}

@test "[EXECUTION] uvx and uv tool run fail on a fresh home directory, with uv's own error" {
  local fake_home
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1

  # Ensure fails creating ~/.local/share/uv/tools,
  # with an error that names the directory the user must create
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" tool run \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}" --version
  sft_assert_contains "$output" "failed to create directory"
  sft_assert_contains "$output" "/.local/share/uv/tools"
  sft_assert_contains "$output" "Operation not permitted"
}

@test "[EXECUTION] uv's data directories cannot be created inside the sandbox" {
  local fake_home uv_data_dir
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  uv_data_dir="${fake_home}/.local/share/uv"

  # NOTE: Creating a directory is indistinguishable from moving a
  #       pre-filled one into place, which would plant tools or interpreters.

  # Ensure cannot create ~/.local/share/uv
  mkdir -p "${fake_home}/.local/share" || return 1
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "$uv_data_dir"
  [ ! -e "$uv_data_dir" ]

  # Ensure cannot create its tools/ or python/
  mkdir -p "$uv_data_dir" || return 1
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "${uv_data_dir}/tools"
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "${uv_data_dir}/python"
  [ -z "$(ls -A "$uv_data_dir")" ]
}

# === Local Installs: Allowed ===

@test "[EXECUTION] uv venv can create a venv" {
  local venv_dir
  venv_dir="$(sft_workspace_path "uv_venv")" || return 1

  # Ensure `uv venv` can create a virtualenv
  safehouse_ok -- "$SFT_UV_BIN" venv "$venv_dir"
  [ -d "$venv_dir/bin" ]
  [ -x "$venv_dir/bin/python" ]
}

@test "[EXECUTION] uv pip install can install a package from PyPI into a venv" {
  local venv_dir cache_dir
  venv_dir="$(sft_workspace_path "uv_pypi_venv")" || return 1

  safehouse_ok -- "$SFT_UV_BIN" venv "$venv_dir"

  # Download/install test package (in this tests's fresh HOME)
  safehouse_ok -- "$SFT_UV_BIN" pip install \
    --python "${venv_dir}/bin/python" \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"

  # Ensure the installed module imports and runs inside the sandbox.
  safehouse_run -- "${venv_dir}/bin/python" -c \
    "import ${SFT_UV_TEST_PKG} as pkg; print(pkg.__version__)"
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_UV_TEST_PKG_VERSION" ]

  # Ensure the console script in the venv's bin/ runs inside the sandbox.
  safehouse_run -- "${venv_dir}/bin/${SFT_UV_TEST_PKG}" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_UV_TEST_PKG_VERSION" ]
  
  # Ensure download wrote to uv's cache
  cache_dir="$(safehouse_ok -- "$SFT_UV_BIN" cache dir)" || return 1
  [ -n "$(find "$cache_dir" -type f -print -quit)" ]
}

@test "[EXECUTION] uv pip install -e can install a workspace project in editable mode" {
  local venv_dir project_dir
  venv_dir="$(sft_workspace_path "uv_editable_venv")" || return 1
  project_dir="$(sft_workspace_path "uv_editable_project")" || return 1

  # Create project directory with a pyproject.toml and a .py file marked "before"
  # NOTE: Exercises PEP 517 build isolation: uv will download the build backend
  #       into a temp build env.
  mkdir -p "$project_dir" || return 1
  cat > "${project_dir}/pyproject.toml" <<'EOF'
[build-system]
requires = ["setuptools>=64"]
build-backend = "setuptools.build_meta"

[project]
name = "sft-uv-editable-probe"
version = "0.0.0"

[tool.setuptools]
py-modules = ["sft_uv_editable_probe"]
EOF
  printf 'VALUE = "before"\n' > "${project_dir}/sft_uv_editable_probe.py"

  # Install project as editable inside venv
  safehouse_ok -- "$SFT_UV_BIN" venv "$venv_dir"
  safehouse_ok -- "$SFT_UV_BIN" pip install \
    --python "${venv_dir}/bin/python" \
    -e "$project_dir"

  # Ensure installed project has "before" marker
  safehouse_run -- "${venv_dir}/bin/python" -c \
    "import sft_uv_editable_probe as m; print(m.VALUE)"
  [ "$status" -eq 0 ]
  [ "$output" = "before" ]

  # Modify project directory's .py file to have "after" marker
  printf 'VALUE = "after"\n' > "${project_dir}/sft_uv_editable_probe.py"

  # Ensure installed project now has "after" marker, without reinstalling,
  # which is how "editable" installs are supposed to behave
  safehouse_run -- "${venv_dir}/bin/python" -c \
    "import sft_uv_editable_probe as m; print(m.VALUE)"
  [ "$status" -eq 0 ]
  [ "$output" = "after" ]
}

@test "[EXECUTION] uv pip uninstall can remove a package from a venv" {
  local venv_dir
  venv_dir="$(sft_workspace_path "uv_uninstall_venv")" || return 1

  # Create venv with package installed (outside the sandbox)
  "$SFT_UV_BIN" venv "$venv_dir" >/dev/null 2>&1 || return 1
  "$SFT_UV_BIN" pip install --python "${venv_dir}/bin/python" \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}" >/dev/null 2>&1 || return 1
  [ -x "${venv_dir}/bin/${SFT_UV_TEST_PKG}" ]

  # Ensure can uninstall package
  safehouse_ok -- "$SFT_UV_BIN" pip uninstall \
    --python "${venv_dir}/bin/python" \
    "$SFT_UV_TEST_PKG"
  [ ! -e "${venv_dir}/bin/${SFT_UV_TEST_PKG}" ]
  safehouse_denied -- "${venv_dir}/bin/python" -c "import ${SFT_UV_TEST_PKG}"
}

@test "[EXECUTION] uv sync can install project dependencies" {
  local project_dir
  project_dir="$(sft_workspace_path "uv_sync_project")" || return 1
  mkdir -p "$project_dir" || return 1

  cat > "${project_dir}/pyproject.toml" <<EOF
[project]
name = "sft-uv-sync-probe"
version = "0.0.0"
requires-python = ">=3.9"
dependencies = ["${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"]
EOF

  # `uv sync` resolves, writes the lockfile and materializes .venv without
  # running anything. The usual first step in a fresh project checkout.
  safehouse_ok -- "$SFT_UV_BIN" sync --project "$project_dir"
  sft_assert_file_exists "${project_dir}/uv.lock"
  [ -x "${project_dir}/.venv/bin/python" ]

  # Ensure the synced dependency imports from the project venv
  safehouse_run -- "${project_dir}/.venv/bin/python" -c \
    "import ${SFT_UV_TEST_PKG} as pkg; print(pkg.__version__)"
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_UV_TEST_PKG_VERSION" ]

  # Ensure syncing again against the existing lockfile works,
  # which is the path CI and repeat agent runs take.
  safehouse_ok -- "$SFT_UV_BIN" sync --project "$project_dir"
}

@test "[EXECUTION] uv add can add a dependency to a project and lock it" {
  local project_dir
  project_dir="$(sft_workspace_path "uv_add_project")" || return 1
  mkdir -p "$project_dir" || return 1

  # Create project with no dependencies
  cat > "${project_dir}/pyproject.toml" <<EOF
[project]
name = "sft-uv-add-probe"
version = "0.0.0"
requires-python = ">=3.9"
dependencies = []
EOF

  # Ensure `uv add` can rewrite pyproject.toml, write the lockfile,
  # and install the dependency into .venv
  safehouse_ok -- "$SFT_UV_BIN" add --project "$project_dir" \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"
  sft_assert_file_contains "${project_dir}/pyproject.toml" \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"
  sft_assert_file_contains "${project_dir}/uv.lock" "name = \"${SFT_UV_TEST_PKG}\""

  # Ensure the added dependency imports from the project venv
  safehouse_run -- "${project_dir}/.venv/bin/python" -c \
    "import ${SFT_UV_TEST_PKG} as pkg; print(pkg.__version__)"
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_UV_TEST_PKG_VERSION" ]
}

@test "[EXECUTION] uv run can execute a project command" {
  local project_dir
  project_dir="$(sft_workspace_path "uv_run_project")" || return 1
  mkdir -p "$project_dir" || return 1

  cat > "${project_dir}/pyproject.toml" <<EOF
[project]
name = "sft-uv-run-probe"
version = "0.0.0"
requires-python = ">=3.9"
dependencies = ["${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"]
EOF

  # Ensure `uv run` can resolve, lock, create .venv, install dependency, and exec it
  safehouse_run -- "$SFT_UV_BIN" run --project "$project_dir" \
    python -c "import ${SFT_UV_TEST_PKG} as pkg; print(pkg.__version__)"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_UV_TEST_PKG_VERSION"

  # Ensure the venv and lockfile landed in the workspace, not in HOME
  sft_assert_file_exists "${project_dir}/uv.lock"
  [ -x "${project_dir}/.venv/bin/python" ]
}

# === Ephemeral Runs: Allowed ===

@test "[EXECUTION] uvx and uv tool run can run an ephemeral tool" {
  local fake_home
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  sft_uv_prepare_home_outside_sandbox "$fake_home" || return 1

  # Ensure `uvx` (an alias for `uv tool run`) can resolve, create .venv
  # under ~/.cache/uv, install dependency, and exec it
  HOME="$fake_home" safehouse_run -- "$SFT_UV_BIN" tool run \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_UV_TEST_PKG_VERSION"

  # Ensure installed nothing persistent to PATH
  [ ! -e "${fake_home}/.local/share/uv/tools/${SFT_UV_TEST_PKG}" ]
  [ ! -e "${fake_home}/.local/bin/${SFT_UV_TEST_PKG}" ]
}

@test "[EXECUTION] uv run --script can run a script with inline dependencies" {
  local script_path cache_dir
  script_path="$(sft_workspace_path "uv_inline_deps.py")" || return 1
  sft_uv_write_inline_deps_script "$script_path" || return 1

  # Ensure `uv run --script` can resolve the inline dependencies,
  # create an environment under ~/.cache/uv, install them, and run the script
  safehouse_run -- "$SFT_UV_BIN" run --script "$script_path"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "${SFT_UV_TEST_PKG} ${SFT_UV_TEST_PKG_VERSION}"

  # Ensure the environment landed in uv's cache
  cache_dir="$(safehouse_ok -- "$SFT_UV_BIN" cache dir)" || return 1
  [ -n "$(find "${cache_dir}/environments-v2" -mindepth 1 -maxdepth 1 -print -quit)" ]
}

@test "[EXECUTION] uv run --with can run a command with an ephemeral dependency" {
  local work_dir
  work_dir="$(sft_workspace_path "uv_with_dir")" || return 1
  mkdir -p "$work_dir" || return 1

  # Ensure `uv run --with` can install the dependency into an ephemeral
  # environment layered over the base interpreter, and run a command in it
  # NOTE: --no-project keeps uv from searching for a project to sync.
  safehouse_run -- "$SFT_UV_BIN" run --directory "$work_dir" --no-project \
    --with "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}" -- \
    python -c "import ${SFT_UV_TEST_PKG} as pkg; print(pkg.__version__)"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_UV_TEST_PKG_VERSION"

  # Ensure no project venv or lockfile was left behind
  [ ! -e "${work_dir}/.venv" ]
  [ ! -e "${work_dir}/uv.lock" ]
}

# === Global Installs: Denied ===

@test "[EXECUTION] uv tool install cannot install a global binary" {
  local fake_home
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  sft_uv_prepare_home_outside_sandbox "$fake_home" || return 1

  # Ensure cannot write payload (under ~/.local/share/uv/tools)
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" tool install \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"
  [ ! -e "${fake_home}/.local/share/uv/tools/${SFT_UV_TEST_PKG}" ]
  [ ! -e "${fake_home}/.local/bin/${SFT_UV_TEST_PKG}" ]
}

@test "[EXECUTION] uv pip install --system cannot install a package into the interpreter's global site-packages or bin directory (python.org)" {
  # Targets: /Library/Frameworks/Python.framework/Versions/3.X/{lib/python3.X/site-packages,bin}
  sft_uv_use_system_python python.org
  sft_uv_test_system_install_denied
}
@test "[EXECUTION] uv pip install --system cannot install a package into the interpreter's global site-packages or bin directory (Homebrew)" {
  # Targets: $(brew --prefix)/lib/python3.X/site-packages, $(brew --prefix)/bin
  sft_uv_use_system_python homebrew
  sft_uv_test_system_install_denied
}
sft_uv_test_system_install_denied() {
  # Precondition: site-packages is writable unsandboxed
  sft_uv_require_system_install_target || return 1

  # Ensure cannot install global package
  SFT_UV_SYSTEM_DIRTY=1
  # shellcheck disable=SC2086  # intentionally unquoted: empty or one flag
  safehouse_denied -- "$SFT_UV_BIN" pip install --system \
    --python "$SFT_UV_SYSTEM_PYTHON_BIN" $SFT_UV_PEP668_FLAG \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"
  [ ! -e "${SFT_UV_SITE_PACKAGES}/${SFT_UV_TEST_PKG}" ]
  [ ! -e "${SFT_UV_SCRIPTS_DIR}/${SFT_UV_TEST_PKG}" ]
}

# === Pre-Installed Global Tools: Usable, Immutable ===

@test "[EXECUTION] a uv-installed global binary runs" {
  local fake_home
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1

  sft_uv_tool_install_outside_sandbox "$fake_home" || return 1

  # Ensure can run binary, via the ~/.local/share/uv and ~/.local/bin read grants
  HOME="$fake_home" safehouse_run -- "${fake_home}/.local/bin/${SFT_UV_TEST_PKG}" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_UV_TEST_PKG_VERSION" ]
}

@test "[EXECUTION] a uv-installed global binary cannot be modified" {
  local fake_home uv_data_dir tools_dir payload_bin bin_link snapshot_before
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  uv_data_dir="${fake_home}/.local/share/uv"
  tools_dir="${uv_data_dir}/tools"
  payload_bin="${tools_dir}/${SFT_UV_TEST_PKG}/bin/${SFT_UV_TEST_PKG}"
  bin_link="${fake_home}/.local/bin/${SFT_UV_TEST_PKG}"

  sft_uv_tool_install_outside_sandbox "$fake_home" || return 1
  sft_assert_file_exists "$payload_bin"
  snapshot_before="$(sft_tree_snapshot "$tools_dir" "$bin_link")" || return 1

  # Ensure cannot reinstall/upgrade/uninstall binary
  # NOTE: These subcommands try to rewrite the payload in place
  # NOTE: A plain `uv tool upgrade` is a no-op for a tool installed with an
  #       exact version pin, so --reinstall forces it to rewrite the payload.
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" tool install \
    --reinstall "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" tool upgrade \
    --reinstall "$SFT_UV_TEST_PKG"
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" tool uninstall "$SFT_UV_TEST_PKG"
  
  # Ensure cannot write to binary directly,
  # including to its __pycache__ which a Python tool writes on first run
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${payload_bin}"
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "$(dirname "$payload_bin")/__pycache__"
  HOME="$fake_home" safehouse_denied -- /bin/rm "$bin_link"

  # Ensure cannot move the payload out from under the read-only rule,
  # where it could be modified and then moved back
  HOME="$fake_home" safehouse_denied -- /bin/mv "$tools_dir" "$(sft_workspace_path "moved_tools")"
  HOME="$fake_home" safehouse_denied -- /bin/mv "$uv_data_dir" "$(sft_workspace_path "moved_uv")"

  # Ensure cannot hard link the payload into the workspace, to modify it there
  HOME="$fake_home" safehouse_denied -- /bin/ln "$payload_bin" "$(sft_workspace_path "linked_bin")"

  # Ensure nothing changed
  [ "$(sft_tree_snapshot "$tools_dir" "$bin_link")" = "$snapshot_before" ]
}

# === Interpreters ===

@test "[EXECUTION] uv venv cannot provision a uv-managed Python interpreter" {
  local fake_home venv_dir python_dir
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  venv_dir="$(sft_workspace_path "uv_managed_venv")" || return 1
  python_dir="${fake_home}/.local/share/uv/python"

  # Create python/ outside the sandbox,
  # as it would be for a user who has installed a uv-managed interpreter before
  mkdir -p "$python_dir" || return 1

  # Ensure `uv venv` cannot download an interpreter into python/
  # NOTE: `only-managed` stops uv adopting a system interpreter,
  #       so it must download one.
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" venv \
    --python-preference only-managed \
    --python "$SFT_UV_TEST_PYTHON_VERSION" \
    "$venv_dir"
  [ -z "$(ls -A "$python_dir")" ]
}

@test "[EXECUTION] uv python install cannot install a shared Python interpreter" {
  local fake_home global_bin python_dir
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  global_bin="${fake_home}/.local/bin"
  python_dir="${fake_home}/.local/share/uv/python"

  # Create ~/.local/bin and python/ outside the sandbox, as they would be for a real user
  mkdir -p "$global_bin" "$python_dir" || return 1

  # Ensure cannot install a shared interpreter (under ~/.local/share/uv/python),
  # nor put it on the global PATH (under ~/.local/bin)
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" python install \
    "$SFT_UV_TEST_PYTHON_VERSION"
  [ -z "$(ls -A "$python_dir")" ]
  [ -z "$(ls -A "$global_bin")" ]
}

@test "[EXECUTION] a uv-managed interpreter installed outside the sandbox is usable by uv venv, uv run --script and uvx" {
  local fake_home python_dir venv_dir script_path snapshot_before
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  python_dir="${fake_home}/.local/share/uv/python"
  venv_dir="$(sft_workspace_path "uv_preinstalled_python_venv")" || return 1

  sft_uv_python_install_outside_sandbox "$fake_home" || return 1
  sft_uv_prepare_home_outside_sandbox "$fake_home" || return 1
  snapshot_before="$(sft_tree_snapshot "$python_dir")" || return 1

  # NOTE: `only-managed` stops uv adopting a system interpreter,
  #       so each command below must use the preinstalled one.

  # Ensure `uv venv` can create a venv from the interpreter
  HOME="$fake_home" safehouse_ok -- "$SFT_UV_BIN" venv \
    --python-preference only-managed \
    --python "$SFT_UV_TEST_PYTHON_VERSION" \
    "$venv_dir"
  HOME="$fake_home" safehouse_run -- "${venv_dir}/bin/python" -c \
    'import sys; print(sys.version.split()[0], sys.base_prefix)'
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "${SFT_UV_TEST_PYTHON_VERSION}."
  sft_assert_contains "$output" "/.local/share/uv/python/cpython-${SFT_UV_TEST_PYTHON_VERSION}."

  # Ensure `uv run --script` can run a script with inline dependencies on the interpreter
  script_path="$(sft_workspace_path "uv_inline_deps.py")" || return 1
  sft_uv_write_inline_deps_script "$script_path" || return 1
  HOME="$fake_home" safehouse_run -- "$SFT_UV_BIN" run \
    --python-preference only-managed \
    --python "$SFT_UV_TEST_PYTHON_VERSION" \
    --script "$script_path"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "${SFT_UV_TEST_PKG} ${SFT_UV_TEST_PKG_VERSION}"
  sft_assert_contains "$output" "/.local/share/uv/python/cpython-${SFT_UV_TEST_PYTHON_VERSION}."

  # Ensure `uvx` can run an ephemeral tool on the interpreter
  HOME="$fake_home" safehouse_run -- "$SFT_UV_BIN" tool run \
    --python-preference only-managed \
    --python "$SFT_UV_TEST_PYTHON_VERSION" \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_UV_TEST_PKG_VERSION"

  # Ensure nothing changed
  [ "$(sft_tree_snapshot "$python_dir")" = "$snapshot_before" ]
}

@test "[EXECUTION] a uv-managed interpreter cannot be modified" {
  local fake_home uv_data_dir python_dir interp_dir minor_link stdlib_dir snapshot_before
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  uv_data_dir="${fake_home}/.local/share/uv"
  python_dir="${uv_data_dir}/python"

  sft_uv_python_install_outside_sandbox "$fake_home" || return 1
  interp_dir="$(find "$python_dir" -maxdepth 1 -type d \
    -name "cpython-${SFT_UV_TEST_PYTHON_VERSION}.*" -print -quit)"
  [ -n "$interp_dir" ]
  stdlib_dir="${interp_dir}/lib/python${SFT_UV_TEST_PYTHON_VERSION}"
  sft_assert_file_exists "${stdlib_dir}/site.py"
  # uv 0.8+ links cpython-X.Y-<platform> to the newest cpython-X.Y.Z-<platform>,
  # and venvs use the link as their Python home
  minor_link="$(find "$python_dir" -maxdepth 1 -type l \
    -name "cpython-${SFT_UV_TEST_PYTHON_VERSION}-*" -print -quit)"
  snapshot_before="$(sft_tree_snapshot "$python_dir")" || return 1

  # Ensure cannot modify the interpreter with uv subcommands
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" python install \
    --reinstall "$SFT_UV_TEST_PYTHON_VERSION"
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" python uninstall \
    "$SFT_UV_TEST_PYTHON_VERSION"

  # Ensure cannot write to the interpreter directly,
  # including planting a sitecustomize.py that every venv built on it would run
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${stdlib_dir}/sitecustomize.py"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${stdlib_dir}/site.py"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${interp_dir}/bin/python${SFT_UV_TEST_PYTHON_VERSION}"
  if [ -n "$minor_link" ]; then
    HOME="$fake_home" safehouse_denied -- /bin/ln -sfh \
      "$(sft_workspace_path "fake_interp")" "$minor_link"
  fi

  # Ensure cannot move the interpreter out from under the read-only rule,
  # where it could be modified and then moved back
  HOME="$fake_home" safehouse_denied -- /bin/mv "$interp_dir" "$(sft_workspace_path "moved_interp")"
  HOME="$fake_home" safehouse_denied -- /bin/mv "$python_dir" "$(sft_workspace_path "moved_python")"
  HOME="$fake_home" safehouse_denied -- /bin/mv "$uv_data_dir" "$(sft_workspace_path "moved_uv")"

  # Ensure cannot hard link the interpreter into the workspace, to modify it there
  HOME="$fake_home" safehouse_denied -- /bin/ln "${stdlib_dir}/site.py" "$(sft_workspace_path "linked_site.py")"

  # Ensure the interpreter still runs
  HOME="$fake_home" safehouse_run -- "${interp_dir}/bin/python${SFT_UV_TEST_PYTHON_VERSION}" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Python ${SFT_UV_TEST_PYTHON_VERSION}."

  # Ensure nothing changed
  [ ! -e "${stdlib_dir}/sitecustomize.py" ]
  [ "$(sft_tree_snapshot "$python_dir")" = "$snapshot_before" ]
}

@test "[EXECUTION] a uv-managed interpreter's ~/.local/bin/pythonX.Y link cannot be modified" {
  local fake_home bin_link snapshot_before
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  bin_link="${fake_home}/.local/bin/python${SFT_UV_TEST_PYTHON_VERSION}"

  # NOTE: `uv python install` (uv 0.8+) links ~/.local/bin/pythonX.Y
  #       to the interpreter, putting it on the user's PATH.
  sft_uv_python_install_outside_sandbox "$fake_home" || return 1
  [ -L "$bin_link" ]
  snapshot_before="$(sft_tree_snapshot "$bin_link")" || return 1

  # Ensure the link runs the interpreter inside the sandbox
  HOME="$fake_home" safehouse_run -- "$bin_link" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Python ${SFT_UV_TEST_PYTHON_VERSION}."

  # Ensure cannot remove the link or repoint it at a planted interpreter
  HOME="$fake_home" safehouse_denied -- /bin/rm "$bin_link"
  HOME="$fake_home" safehouse_denied -- /bin/ln -sfh \
    "$(sft_workspace_path "fake_interp")" "$bin_link"
  HOME="$fake_home" safehouse_denied -- /bin/mv "$bin_link" "$(sft_workspace_path "moved_link")"

  # Ensure nothing changed
  [ "$(sft_tree_snapshot "$bin_link")" = "$snapshot_before" ]
}

# === Config ===

@test "[EXECUTION] uv can read user config but not write it" {
  local fake_home config_dir cache_dir
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  config_dir="${fake_home}/.config/uv"
  cache_dir="$(sft_workspace_path "uv_configured_cache")" || return 1

  # Write the config a user would author, outside the sandbox
  mkdir -p "$config_dir" || return 1
  printf 'cache-dir = "%s"\n' "$cache_dir" > "${config_dir}/uv.toml"

  # Ensure uv can read ~/.config/uv/uv.toml
  HOME="$fake_home" safehouse_run -- "$SFT_UV_BIN" cache dir
  [ "$status" -eq 0 ]
  [ "$output" = "$cache_dir" ]

  # Ensure cannot rewrite, delete, or add to config
  # NOTE: Rewriting uv.toml is the real hijack: cache-dir and index-url both
  #       live here, so a write would repoint where uv fetches from.
  HOME="$fake_home" safehouse_denied -- /bin/sh -c \
    "printf 'cache-dir = \"/hijacked\"\n' > '${config_dir}/uv.toml'"
  HOME="$fake_home" safehouse_denied -- /bin/rm -f "${config_dir}/uv.toml"

  # Ensure config is unchanged and still honored
  sft_assert_file_contains "${config_dir}/uv.toml" "$cache_dir"
  HOME="$fake_home" safehouse_run -- "$SFT_UV_BIN" cache dir
  [ "$status" -eq 0 ]
  [ "$output" = "$cache_dir" ]
}

@test "[EXECUTION] uv cannot read or write stored index credentials" {
  local fake_home creds_file
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  creds_file="${fake_home}/.local/share/uv/credentials/credentials.toml"

  sft_uv_auth_login_outside_sandbox "$fake_home" || return 1
  sft_assert_file_contains "$creds_file" "$SFT_UV_TEST_TOKEN"

  # Ensure cannot read the stored token
  HOME="$fake_home" safehouse_denied -- /bin/cat "$creds_file"
  HOME="$fake_home" safehouse_run -- "$SFT_UV_BIN" auth token "$SFT_UV_TEST_SERVICE"
  [ "$status" -ne 0 ]
  sft_assert_not_contains "$output" "$SFT_UV_TEST_TOKEN"

  # Ensure cannot add, rewrite, or delete credentials
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" auth login \
    "$SFT_UV_TEST_SERVICE" --token "hijacked"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "$creds_file"
  HOME="$fake_home" safehouse_denied -- /bin/rm -f "$creds_file"
  sft_assert_file_contains "$creds_file" "$SFT_UV_TEST_TOKEN"

  # Ensure the deny does not break uv itself, which stats this path on startup
  HOME="$fake_home" safehouse_ok -- "$SFT_UV_BIN" venv \
    "$(sft_workspace_path "uv_creds_venv")"
}

# === Special Permission Checks ===

# Ensure python.sb's narrow file-write grants inside the otherwise read-only
# ~/.local/share/uv/tools let `uvx` take its lock, without letting anything
# else be planted there.
@test "[EXECUTION] uv: the tools/ lock files are writable but the rest of tools/ is not" {
  local fake_home tools_dir
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  tools_dir="${fake_home}/.local/share/uv/tools"

  sft_uv_prepare_home_outside_sandbox "$fake_home" || return 1
  sft_assert_file_exists "${tools_dir}/.lock"

  # Ensure can write the lock and its .gitignore,
  # and stage a lock as a .tmp* file then rename it into place, as uv does
  HOME="$fake_home" safehouse_ok -- /usr/bin/touch "${tools_dir}/.lock"
  HOME="$fake_home" safehouse_ok -- /usr/bin/touch "${tools_dir}/.gitignore"
  HOME="$fake_home" safehouse_ok -- /bin/sh -c \
    ': > "$1/.tmpsft" && /bin/mv "$1/.tmpsft" "$1/.lock"' _ "$tools_dir"

  # Ensure cannot create anything else in tools/,
  # including a name that merely starts with ".lock"
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "${tools_dir}/${SFT_UV_TEST_PKG}"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${tools_dir}/.lock-sibling"
  [ ! -e "${tools_dir}/${SFT_UV_TEST_PKG}" ]
  [ ! -e "${tools_dir}/.lock-sibling" ]

  # Ensure a staged .tmp* entry cannot be renamed into place as a tool
  HOME="$fake_home" safehouse_ok -- /bin/mkdir "${tools_dir}/.tmpsft-tool"
  HOME="$fake_home" safehouse_denied -- /bin/mv \
    "${tools_dir}/.tmpsft-tool" "${tools_dir}/${SFT_UV_TEST_PKG}"
  [ ! -e "${tools_dir}/${SFT_UV_TEST_PKG}" ]
}

# === Cache Poisoning: Accepted Risk ===

# NOTE: Test characterizes current behavior. Ideal behavior would disallow tampering.
@test "[EXECUTION] can tamper with a cached uvx venv to place a binary where it will run outside sandbox" {
  local fake_home cache_dir cached_bins cached_bin fake_bin
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1

  # Outside sandbox, create a cached venv
  HOME="$fake_home" run "$SFT_UV_BIN" tool run \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_UV_TEST_PKG_VERSION"

  # Locate the cached venv's console script (at ~/.cache/uv/archive-v0/<id>/bin/<pkg>)
  cache_dir="$(HOME="$fake_home" "$SFT_UV_BIN" cache dir)" || return 1
  cached_bins="$(find "${cache_dir}/archive-v0" -path "*/bin/${SFT_UV_TEST_PKG}")" || return 1
  [ -n "$cached_bins" ]
  [ "$(printf '%s\n' "$cached_bins" | wc -l)" -eq 1 ]
  cached_bin="$cached_bins"

  # Inside sandbox, replace the console script
  fake_bin="$(sft_workspace_path "fake_cowsay")" || return 1
  printf '%s\n' '#!/bin/sh' "echo \"I'm not cowsay\"" > "$fake_bin"
  HOME="$fake_home" safehouse_ok -- /bin/cp "$fake_bin" "$cached_bin"

  # Outside sandbox, rerun the same tool.
  # Ensure the reused venv ran the replaced script.
  HOME="$fake_home" run "$SFT_UV_BIN" tool run \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "I'm not cowsay"
}

# NOTE: Test characterizes current behavior. Ideal behavior would disallow tampering.
@test "[EXECUTION] can tamper with a cached uv run --script environment to place a binary where it will run outside sandbox" {
  local fake_home script_path cache_dir env_dirs env_dir fake_python marker
  fake_home="$(sft_fake_home --xdg-dirs)" || return 1
  script_path="$(sft_workspace_path "uv_cached_script.py")" || return 1
  marker="$(sft_workspace_path "planted_python_ran")" || return 1
  sft_uv_write_inline_deps_script "$script_path" || return 1

  # Outside sandbox, create a cached script environment
  HOME="$fake_home" run "$SFT_UV_BIN" run --script "$script_path"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "${SFT_UV_TEST_PKG} ${SFT_UV_TEST_PKG_VERSION}"

  # Locate the cached environment (at ~/.cache/uv/environments-v2/<script>-<hash>)
  cache_dir="$(HOME="$fake_home" "$SFT_UV_BIN" cache dir)" || return 1
  env_dirs="$(find "${cache_dir}/environments-v2" -mindepth 1 -maxdepth 1 -type d)" || return 1
  [ -n "$env_dirs" ]
  [ "$(printf '%s\n' "$env_dirs" | wc -l)" -eq 1 ]
  env_dir="$env_dirs"

  # Inside sandbox, replace the environment's interpreter link
  # NOTE: uv rebuilds the environment's site-packages on every run, discarding
  #       a planted module or .pth file, but leaves its bin/ alone.
  # NOTE: The fake interpreter only drops a marker. One that exec'd the real
  #       interpreter would report the base interpreter's prefix, and uv would
  #       then sync the script's dependencies into the base interpreter's
  #       global site-packages.
  fake_python="$(sft_workspace_path "fake_python")" || return 1
  printf '%s\n' '#!/bin/sh' ": > '${marker}'" 'exit 1' > "$fake_python"
  chmod +x "$fake_python"
  HOME="$fake_home" safehouse_ok -- /bin/sh -c \
    '/bin/rm "$1/bin/python" && /bin/cp "$2" "$1/bin/python"' _ "$env_dir" "$fake_python"

  # Outside sandbox, rerun the same script.
  # Ensure uv ran the planted interpreter.
  # NOTE: The run itself fails, because the fake interpreter answers none of
  #       uv's queries, but the planted code has already run by then.
  HOME="$fake_home" run "$SFT_UV_BIN" run --script "$script_path"
  sft_assert_file_exists "$marker"
}

# ------------------------------------------------------------------------------
# Utility

# Runs `uv tool run` once outside the sandbox, as a user would before starting
# a sandboxed agent, then clears uv's cache so a sandboxed run must build its
# own venv.
#
# Global paths created, inside $fake_home:
# - ~/.local/share/uv/tools, which `uv tool run` needs and cannot create inside the sandbox
sft_uv_prepare_home_outside_sandbox() {
  local fake_home="$1"

  HOME="$fake_home" "$SFT_UV_BIN" tool run \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}" --version >/dev/null || return 1
  HOME="$fake_home" "$SFT_UV_BIN" cache clean >/dev/null 2>&1
}

# Installs a uv-managed interpreter, as a user would before starting a sandboxed agent.
#
# Global paths created, inside $fake_home:
# - ~/.local/share/uv/python/cpython-<version>-<platform>
sft_uv_python_install_outside_sandbox() {
  local fake_home="$1"

  HOME="$fake_home" "$SFT_UV_BIN" python install "$SFT_UV_TEST_PYTHON_VERSION" >/dev/null 2>&1
}

# Writes a script with inline (PEP 723) dependencies on the test package,
# which prints the package's version and the interpreter's base prefix.
sft_uv_write_inline_deps_script() {
  local script_path="$1"

  cat > "$script_path" <<EOF
# /// script
# dependencies = ["${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"]
# ///
import importlib.metadata, sys
print("${SFT_UV_TEST_PKG}", importlib.metadata.version("${SFT_UV_TEST_PKG}"), sys.base_prefix)
EOF
}

# 1. Skip the current test if the requested Python install type is absent.
# 2. Set SFT_UV_SYSTEM_PYTHON_BIN to that install's python3.
# 3. Set SFT_UV_PEP668_FLAG to --break-system-packages for Homebrew,
#    so that the sandbox, not PEP 668's EXTERNALLY-MANAGED marker,
#    is what refuses a system install.
#
# NOTE: Duplicate logic in: sft_pip_use_python, sft_uv_use_system_python,
#       sft_poetry_use_python
sft_uv_use_system_python() {
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

  export SFT_UV_SYSTEM_PYTHON_BIN="$python_bin"
  export SFT_UV_PEP668_FLAG=""
  [ "$install_type" != "homebrew" ] || SFT_UV_PEP668_FLAG="--break-system-packages"
}

# 1. Set SFT_UV_SITE_PACKAGES and SFT_UV_SCRIPTS_DIR to where a system
#    (non-venv, non-user) install lands.
# 2. Hold the interpreter's global-site lock until teardown.
# 3. Skip the test when it cannot be exercised faithfully, since a sandbox
#    denial proves nothing there: when the test package is already installed
#    globally, or when site-packages is not writable by this user.
sft_uv_require_system_install_target() {
  SFT_UV_SITE_PACKAGES="$("$SFT_UV_SYSTEM_PYTHON_BIN" -c \
    'import sysconfig; print(sysconfig.get_path("purelib"))')" || return 1
  SFT_UV_SCRIPTS_DIR="$("$SFT_UV_SYSTEM_PYTHON_BIN" -c \
    'import sysconfig; print(sysconfig.get_path("scripts"))')" || return 1

  # Serialize tests that use this interpreter's global site-packages, across
  # pip.bats, uv.bats and poetry.bats. Parallel tests would otherwise install,
  # see, and uninstall each other's package.
  sft_acquire_run_lock "pip-global-$(printf '%s' "$SFT_UV_SITE_PACKAGES" | cksum | cut -d' ' -f1)" || return 1

  # Skip if package appears to have been installed before test run started,
  # so that we do NOT adopt it and do NOT uninstall it later.
  [ ! -e "${SFT_UV_SITE_PACKAGES}/${SFT_UV_TEST_PKG}" ] \
    || skip "${SFT_UV_TEST_PKG} is already installed globally"

  [ -w "$SFT_UV_SITE_PACKAGES" ] && [ -w "$SFT_UV_SCRIPTS_DIR" ] \
    || skip "global site-packages/bin not writable by this user (${SFT_UV_SITE_PACKAGES})"
}

# Uninstalls the test package from the interpreter's global site-packages,
# in case a sandbox failure let a system install through.
sft_uv_cleanup_system_install() {
  [ "${SFT_UV_SYSTEM_DIRTY:-}" = 1 ] || return 0
  # shellcheck disable=SC2086
  "$SFT_UV_BIN" pip uninstall --system --python "$SFT_UV_SYSTEM_PYTHON_BIN" \
    $SFT_UV_PEP668_FLAG "$SFT_UV_TEST_PKG" >/dev/null 2>&1 || true
  SFT_UV_SYSTEM_DIRTY=0
}

# Installs the test package globally,
# as a user would before starting a sandboxed agent.
# 
# Global paths modified, inside $fake_home:
# - ~/.local/share/uv/tools
#     - Test package binary
# - ~/.local/bin
#     - Symlink to test package binary
sft_uv_tool_install_outside_sandbox() {
  local fake_home="$1"

  HOME="$fake_home" "$SFT_UV_BIN" tool install \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"
}

# Stores an index credential, as a user would before starting a sandboxed agent.
#
# Global paths modified, inside $fake_home:
# - ~/.local/share/uv/credentials/credentials.toml
#     - Plaintext token for $SFT_UV_TEST_SERVICE
sft_uv_auth_login_outside_sandbox() {
  local fake_home="$1"

  HOME="$fake_home" "$SFT_UV_BIN" auth login \
    "$SFT_UV_TEST_SERVICE" --token "$SFT_UV_TEST_TOKEN"
}

# ------------------------------------------------------------------------------
