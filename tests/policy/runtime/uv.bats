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

# 1. Skip tests if uv not installed.
# 2. Set SFT_UV_BIN to uv's path.
setup_file() {
  export SFT_UV_BIN
  SFT_UV_BIN="$(command -v uv || true)"
  [ -n "$SFT_UV_BIN" ] || skip "uv is not installed"
}

# === Basics ===

@test "[EXECUTION] uv --version works" {
  safehouse_ok -- "$SFT_UV_BIN" --version
}

@test "[EXECUTION] uv tool list and uv tool dir work on a fresh home directory, without creating uv's data directories" {
  skip "not yet automated"
}

@test "[EXECUTION] uvx and uv tool run fail on a fresh home directory, with uv's own error" {
  local fake_home
  fake_home="$(sft_fake_home)" || return 1

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
  fake_home="$(sft_fake_home)" || return 1
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
  skip "not yet automated"
}

@test "[EXECUTION] uv pip uninstall can remove a package from a venv" {
  skip "not yet automated"
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
  skip "not yet automated"
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
  fake_home="$(sft_fake_home)" || return 1
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
  skip "not yet automated"
}

@test "[EXECUTION] uv run --with can run a command with an ephemeral dependency" {
  skip "not yet automated"
}

# === Global Installs: Denied ===

@test "[EXECUTION] uv tool install cannot install a global binary" {
  local fake_home
  fake_home="$(sft_fake_home)" || return 1
  sft_uv_prepare_home_outside_sandbox "$fake_home" || return 1

  # Ensure cannot write payload (under ~/.local/share/uv/tools)
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" tool install \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"
  [ ! -e "${fake_home}/.local/share/uv/tools/${SFT_UV_TEST_PKG}" ]
  [ ! -e "${fake_home}/.local/bin/${SFT_UV_TEST_PKG}" ]
}

@test "[EXECUTION] uv pip install --system cannot install a package into the interpreter's global site-packages or bin directory (python.org)" {
  skip "not yet automated"
}

@test "[EXECUTION] uv pip install --system cannot install a package into the interpreter's global site-packages or bin directory (Homebrew)" {
  skip "not yet automated"
}

# === Pre-Installed Global Tools: Usable, Immutable ===

@test "[EXECUTION] a uv-installed global binary runs" {
  local fake_home
  fake_home="$(sft_fake_home)" || return 1

  sft_uv_tool_install_outside_sandbox "$fake_home" || return 1

  # Ensure can run binary, via the ~/.local/share/uv and ~/.local/bin read grants
  HOME="$fake_home" safehouse_run -- "${fake_home}/.local/bin/${SFT_UV_TEST_PKG}" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_UV_TEST_PKG_VERSION" ]
}

# TODO: Also ensure `uv tool upgrade` is denied, alongside --reinstall and uninstall
@test "[EXECUTION] a uv-installed global binary cannot be modified" {
  local fake_home uv_data_dir tools_dir payload_bin bin_link snapshot_before
  fake_home="$(sft_fake_home)" || return 1
  uv_data_dir="${fake_home}/.local/share/uv"
  tools_dir="${uv_data_dir}/tools"
  payload_bin="${tools_dir}/${SFT_UV_TEST_PKG}/bin/${SFT_UV_TEST_PKG}"
  bin_link="${fake_home}/.local/bin/${SFT_UV_TEST_PKG}"

  sft_uv_tool_install_outside_sandbox "$fake_home" || return 1
  sft_assert_file_exists "$payload_bin"
  snapshot_before="$(sft_uv_snapshot "$tools_dir" "$bin_link")" || return 1

  # Ensure cannot reinstall/uninstall binary
  # NOTE: Both subcommands try to rewrite the payload in place
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" tool install \
    --reinstall "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"
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
  [ "$(sft_uv_snapshot "$tools_dir" "$bin_link")" = "$snapshot_before" ]
}

# === Interpreters ===

@test "[EXECUTION] uv venv cannot provision a uv-managed Python interpreter" {
  local fake_home venv_dir python_dir
  fake_home="$(sft_fake_home)" || return 1
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
  fake_home="$(sft_fake_home)" || return 1
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
  fake_home="$(sft_fake_home)" || return 1
  python_dir="${fake_home}/.local/share/uv/python"
  venv_dir="$(sft_workspace_path "uv_preinstalled_python_venv")" || return 1

  sft_uv_python_install_outside_sandbox "$fake_home" || return 1
  sft_uv_prepare_home_outside_sandbox "$fake_home" || return 1
  snapshot_before="$(sft_uv_snapshot "$python_dir")" || return 1

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
  cat > "$script_path" <<EOF
# /// script
# dependencies = ["${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"]
# ///
import importlib.metadata, sys
print("${SFT_UV_TEST_PKG}", importlib.metadata.version("${SFT_UV_TEST_PKG}"), sys.base_prefix)
EOF
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
  [ "$(sft_uv_snapshot "$python_dir")" = "$snapshot_before" ]
}

@test "[EXECUTION] a uv-managed interpreter cannot be modified" {
  local fake_home uv_data_dir python_dir interp_dir minor_link stdlib_dir snapshot_before
  fake_home="$(sft_fake_home)" || return 1
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
  snapshot_before="$(sft_uv_snapshot "$python_dir")" || return 1

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
  [ "$(sft_uv_snapshot "$python_dir")" = "$snapshot_before" ]
}

@test "[EXECUTION] a uv-managed interpreter's ~/.local/bin/pythonX.Y link cannot be modified" {
  skip "not yet automated"
}

# === Config ===

@test "[EXECUTION] uv can read user config but not write it" {
  local fake_home config_dir cache_dir
  fake_home="$(sft_fake_home)" || return 1
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
  fake_home="$(sft_fake_home)" || return 1
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

@test "[EXECUTION] uv: the tools/ lock files are writable but the rest of tools/ is not" {
  skip "not yet automated"
}

# === Cache Poisoning: Accepted Risk ===

# NOTE: Test characterizes current behavior. Ideal behavior would disallow tampering.
@test "[EXECUTION] can tamper with a cached uvx venv to place a binary where it will run outside sandbox" {
  local fake_home cache_dir cached_bins cached_bin fake_bin
  fake_home="$(sft_fake_home)" || return 1

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
  skip "not yet automated"
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

# Prints a digest of the names, modes, inodes and change times of every path
# under the given paths, without following symlinks.
sft_uv_snapshot() {
  find "$@" -exec /usr/bin/stat -f '%N %Sp %i %z %m' {} + | LC_ALL=C sort | shasum
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
