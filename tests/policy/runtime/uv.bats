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

# Skip tests if uv not installed. Set SFT_UV_BIN to uv's path.
setup_file() {
  export SFT_UV_BIN
  SFT_UV_BIN="$(command -v uv || true)"
  [ -n "$SFT_UV_BIN" ] || skip "uv is not installed"
}

@test "[EXECUTION] uv version works" {
  safehouse_ok -- "$SFT_UV_BIN" --version
}

@test "[EXECUTION] uv venv can create a venv" {
  local venv_dir
  venv_dir="$(sft_workspace_path "uv_venv")" || return 1

  # Ensure `uv venv` can create a virtualenv
  safehouse_ok -- "$SFT_UV_BIN" venv "$venv_dir"
  [ -d "$venv_dir/bin" ]
  [ -x "$venv_dir/bin/python" ]
}

@test "[EXECUTION] uv venv can provision a uv-managed shared Python interpreter" {
  local fake_home venv_dir python_dir
  fake_home="$(sft_fake_home)" || return 1
  venv_dir="$(sft_workspace_path "uv_managed_venv")" || return 1
  python_dir="${fake_home}/.local/share/uv/python"
  
  # Ensure `uv venv` can create a virtualenv using a
  # dynamically downloaded Python interpreter.
  # NOTE: `only-managed` stops uv adopting a system interpreter,
  #       so the download always happens.
  HOME="$fake_home" safehouse_ok -- "$SFT_UV_BIN" venv \
    --python-preference only-managed \
    --python "$SFT_UV_TEST_PYTHON_VERSION" \
    "$venv_dir"

  # Ensure a real interpreter landed under python/, and the venv built from it runs.
  [ -n "$(find "$python_dir" -maxdepth 1 \
      -name "cpython-${SFT_UV_TEST_PYTHON_VERSION}*" -print -quit)" ]
  HOME="$fake_home" safehouse_run -- "${venv_dir}/bin/python" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Python ${SFT_UV_TEST_PYTHON_VERSION}."

  # Ensure no interpreter symlink was installed globally to PATH
  [ ! -e "${fake_home}/.local/bin/python${SFT_UV_TEST_PYTHON_VERSION}" ]
}

@test "[EXECUTION] uv python install can install a shared Python binary but not put it on global PATH" {
  local fake_home global_bin python_symlink
  fake_home="$(sft_fake_home)" || return 1
  global_bin="${fake_home}/.local/bin"
  python_symlink="${global_bin}/python${SFT_UV_TEST_PYTHON_VERSION}"

  # Ensure ~/.local/bin already exists, as it would for a real user
  mkdir -p "$global_bin" || return 1

  # 1. Ensure can install shared interpreter (under ~/.local/share/uv/python)
  # 2. Ensure cannot install it to the global PATH (under ~/.local/bin)
  # NOTE: Not a `safehouse_denied` case. uv reports the refused symlink as a
  #       warning and still exits 0, so only the missing symlink and the denial
  #       message distinguish this from an unsandboxed install.
  HOME="$fake_home" safehouse_run -- "$SFT_UV_BIN" python install \
    "$SFT_UV_TEST_PYTHON_VERSION"
  [ "$status" -eq 0 ]
  [ -n "$(find "${fake_home}/.local/share/uv/python" -maxdepth 1 \
      -name "cpython-${SFT_UV_TEST_PYTHON_VERSION}*" -print -quit)" ]
  [ ! -e "$python_symlink" ]
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

@test "[EXECUTION] uv tool install cannot install a global binary" {
  local fake_home
  fake_home="$(sft_fake_home)" || return 1
  
  # Ensure cannot write payload (under ~/.local/share/uv/tools)
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" tool install \
    "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"
  [ ! -e "${fake_home}/.local/share/uv/tools/${SFT_UV_TEST_PKG}" ]
  [ ! -e "${fake_home}/.local/bin/${SFT_UV_TEST_PKG}" ]
}

@test "[EXECUTION] uvx and uv tool run can run an ephemeral tool" {
  local fake_home
  fake_home="$(sft_fake_home)" || return 1

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

@test "[EXECUTION] a uv-installed global binary runs" {
  local fake_home
  fake_home="$(sft_fake_home)" || return 1

  sft_uv_tool_install_outside_sandbox "$fake_home" || return 1

  # Ensure can run binary, via the ~/.local/share/uv and ~/.local/bin read grants
  HOME="$fake_home" safehouse_run -- "${fake_home}/.local/bin/${SFT_UV_TEST_PKG}" --version
  [ "$status" -eq 0 ]
  [ "$output" = "$SFT_UV_TEST_PKG_VERSION" ]
}

@test "[EXECUTION] a uv-installed global binary cannot be modified" {
  local fake_home payload_bin
  fake_home="$(sft_fake_home)" || return 1
  payload_bin="${fake_home}/.local/share/uv/tools/${SFT_UV_TEST_PKG}/bin/${SFT_UV_TEST_PKG}"

  sft_uv_tool_install_outside_sandbox "$fake_home" || return 1
  sft_assert_file_exists "$payload_bin"
  
  # Ensure cannot reinstall/uninstall binary
  # NOTE: Both subcommands try to rewrite the payload in place
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" tool install \
    --reinstall "${SFT_UV_TEST_PKG}==${SFT_UV_TEST_PKG_VERSION}"
  HOME="$fake_home" safehouse_denied -- "$SFT_UV_BIN" tool uninstall "$SFT_UV_TEST_PKG"
  
  # Ensure cannot write to binary directly,
  # including to its __pycache__ which a Python tool writes on first run
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${payload_bin}"
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "$(dirname "$payload_bin")/__pycache__"
}

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

# ------------------------------------------------------------------------------
# Utility

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
