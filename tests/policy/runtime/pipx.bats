#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# pipx toolchain tests.
#
# pipx's macOS layout (pipx 1.16+):
# - ~/Library/Application Support/pipx/   PIPX_HOME (default). Itself cannot be
#                                         created, moved or removed in sandbox.
#   - venvs/   Installed tools.                          Read-only in sandbox.
#   - shared/  pip venv on every tool's sys.path.        Read-only in sandbox.
#              (pip backend only.)
#   - py/      Standalone interpreters it downloads.     Read-only in sandbox.
#   - .trash/  Staging for uninstalls.
# - ~/.local/pipx/                        PIPX_HOME (pipx <1.16), used instead of
#                                         the default only if it already exists.
#                                         Same contents as above.
# - ~/Library/Caches/pipx/                Venvs reused by `pipx run` for 14 days.
#                                         Writable. (pip backend only.)
# - ~/Library/Logs/pipx/                  Per-invocation logs. Writable.
# - ~/.local/bin/                         Symlinks to installed tools.
# - ~/.local/share/man/                   Man pages of installed tools.
#
# Backends:
# - pipx 1.12+ manages venvs with either pip or uv, picking uv automatically
#   when it is on PATH.
# - Under the uv backend, `pipx run` execs `uv tool run`, so it uses uv's cache
#   (~/.cache/uv), and venvs have no shared/.
# - Each variant pins its backend with PIPX_DEFAULT_BACKEND; the (uv backend)
#   variants skip when uv or backend support is missing.
#
# Home locations:
# - Tests run with the default PIPX_HOME. A (legacy ~/.local/pipx home)
#   variant covers the policy boundaries that depend on the home location,
#   with the pip backend only, to keep the variant count down.
#
# NOTE: Every subcommand except --version, list, and environment first mkdirs
#       venvs/, ~/.local/bin, ~/.local/share/man, the venv cache, and py/.
#
load ../../test_helper.bash
load python_helper.bash

# Minimal test package to install
SFT_PIPX_TEST_PKG="cowsay"
SFT_PIPX_TEST_PKG_VERSION="6.1"

# ------------------------------------------------------------------------------
# Tests

setup_file() {
  # 1. Skip tests if pipx not installed.
  # 2. Set SFT_PIPX_BIN to pipx's path.
  export SFT_PIPX_BIN SFT_PIPX_HAS_BACKENDS
  SFT_PIPX_BIN="$(command -v pipx || true)"
  [ -n "$SFT_PIPX_BIN" ] || skip "pipx is not installed"

  # Set SFT_PIPX_HAS_BACKENDS to 1 if pipx supports --backend (pipx 1.12+).
  SFT_PIPX_HAS_BACKENDS=0
  if "$SFT_PIPX_BIN" run --help 2>/dev/null | grep -q -- '--backend'; then
    SFT_PIPX_HAS_BACKENDS=1
  fi

  # Fetch python-build-standalone's release index once, for the tests that
  # download a standalone interpreter. See sft_pipx_load_python_index.
  export SFT_PIPX_PYTHON_INDEX="${BATS_FILE_TMPDIR}/pipx-python-index.json"
  if "$SFT_PIPX_BIN" run --help 2>/dev/null | grep -q -- '--fetch-'; then
    sft_pipx_fetch_python_index "$SFT_PIPX_PYTHON_INDEX" \
      || echo "# WARNING: could not fetch the python-build-standalone index" >&3
  fi
}

# === Basics ===

@test "[EXECUTION] pipx --version works" {
  local expected_version
  expected_version="$("$SFT_PIPX_BIN" --version)" || return 1

  # NOTE: Exits before pipx's setup(), so exercises little of the policy.
  safehouse_run -- "$SFT_PIPX_BIN" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$expected_version"
}

@test "[EXECUTION] pipx list works on a fresh home directory" {
  local fake_home
  fake_home="$(sft_fake_home --macos-dirs)" || return 1

  # NOTE: pipx 1.16+ skips setup()'s mkdirs for `pipx list`.
  sft_pipx_test_list_works "$fake_home"
}

@test "[EXECUTION] pipx list works when ~/.local/bin and ~/.local/share/man already exist" {
  local fake_home
  fake_home="$(sft_fake_home --macos-dirs)" || return 1
  mkdir -p "${fake_home}/.local/bin" "${fake_home}/.local/share/man" || return 1

  # NOTE: Models a typical user's machine, where other tools have
  #       already created these directories.
  sft_pipx_test_list_works "$fake_home"
}

@test "[EXECUTION] pipx list works (legacy ~/.local/pipx home)" {
  local fake_home pipx_home
  fake_home="$(sft_fake_home --macos-dirs)" || return 1

  # Outside sandbox, create a legacy home populated as a user's would be
  mkdir -p "${fake_home}/.local/pipx" || return 1
  HOME="$fake_home" "$SFT_PIPX_BIN" interpreter list >/dev/null || return 1

  # Ensure pipx uses the legacy home
  pipx_home="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_HOME)" || return 1
  [ "$pipx_home" = "${fake_home}/.local/pipx" ]

  sft_pipx_test_list_works "$fake_home"
}

sft_pipx_test_list_works() {
  local fake_home="$1"

  HOME="$fake_home" safehouse_run -- "$SFT_PIPX_BIN" list
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "nothing has been installed with pipx"
}

@test "[EXECUTION] pipx subcommands that create pipx's directories fail on a fresh home directory, with pipx's own error" {
  local fake_home
  fake_home="$(sft_fake_home --macos-dirs)" || return 1
  mkdir -p "${fake_home}/.local/bin" "${fake_home}/.local/share/man" || return 1

  HOME="$fake_home" safehouse_denied -- "$SFT_PIPX_BIN" interpreter list
  sft_assert_contains "$output" "Cannot create"
  sft_assert_contains "$output" "permission denied"
}

# === Ephemeral Runs: Allowed ===
#
# Setup creates shared/ outside the sandbox, since it is read-only inside.

@test "[EXECUTION] pipx run can run an ephemeral tool (pip backend)" {
  sft_pipx_use_backend pip
  sft_pipx_test_run_ephemeral_tool
}
@test "[EXECUTION] pipx run can run an ephemeral tool (uv backend)" {
  sft_pipx_use_backend uv
  sft_pipx_test_run_ephemeral_tool
}
sft_pipx_test_run_ephemeral_tool() {
  local fake_home venvs_dir
  fake_home="$(sft_pipx_fake_home)" || return 1

  sft_pipx_prepare_home_outside_sandbox "$fake_home" || return 1
  venvs_dir="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_LOCAL_VENVS)" || return 1

  # Ensure can resolve, create a temporary venv, install the package, and exec it
  HOME="$fake_home" safehouse_run -- "$SFT_PIPX_BIN" run \
    ${SFT_PIPX_BACKEND_ARGS[@]+"${SFT_PIPX_BACKEND_ARGS[@]}"} \
    "${SFT_PIPX_TEST_PKG}==${SFT_PIPX_TEST_PKG_VERSION}" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_PIPX_TEST_PKG_VERSION"

  # Ensure installed nothing persistent to PATH
  sft_assert_path_absent "${venvs_dir}/${SFT_PIPX_TEST_PKG}"
  sft_assert_path_absent "${fake_home}/.local/bin/${SFT_PIPX_TEST_PKG}"
}

@test "[EXECUTION] pipx run can run a script with inline dependencies (pip backend)" {
  sft_pipx_use_backend pip
  sft_pipx_test_run_script_with_inline_deps
}
@test "[EXECUTION] pipx run can run a script with inline dependencies (uv backend)" {
  sft_pipx_use_backend uv
  sft_pipx_test_run_script_with_inline_deps
}
sft_pipx_test_run_script_with_inline_deps() {
  local fake_home script_path
  fake_home="$(sft_pipx_fake_home)" || return 1
  sft_pipx_prepare_home_outside_sandbox "$fake_home" || return 1

  # Create a PEP 723 script in the workspace
  script_path="$(sft_workspace_path "pipx_inline_deps.py")" || return 1
  cat > "$script_path" <<EOF
# /// script
# dependencies = ["${SFT_PIPX_TEST_PKG}==${SFT_PIPX_TEST_PKG_VERSION}"]
# ///
import importlib.metadata
print("${SFT_PIPX_TEST_PKG}", importlib.metadata.version("${SFT_PIPX_TEST_PKG}"))
EOF

  # Ensure can create a temporary venv with the script's dependencies, and run it
  HOME="$fake_home" safehouse_run -- "$SFT_PIPX_BIN" run \
    ${SFT_PIPX_BACKEND_ARGS[@]+"${SFT_PIPX_BACKEND_ARGS[@]}"} \
    "$script_path"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "${SFT_PIPX_TEST_PKG} ${SFT_PIPX_TEST_PKG_VERSION}"
}

# === Global Installs: Denied ===

@test "[EXECUTION] pipx install cannot install a global binary (pip backend)" {
  sft_pipx_use_backend pip
  sft_pipx_test_install_denied
}
@test "[EXECUTION] pipx install cannot install a global binary (uv backend)" {
  sft_pipx_use_backend uv
  sft_pipx_test_install_denied
}
@test "[EXECUTION] pipx install cannot install a global binary (legacy ~/.local/pipx home)" {
  sft_pipx_use_backend pip
  sft_pipx_use_home legacy
  sft_pipx_test_install_denied
}
sft_pipx_test_install_denied() {
  local fake_home venvs_dir
  fake_home="$(sft_pipx_fake_home)" || return 1
  sft_pipx_prepare_home_outside_sandbox "$fake_home" || return 1
  venvs_dir="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_LOCAL_VENVS)" || return 1

  # Ensure cannot install
  HOME="$fake_home" safehouse_denied -- "$SFT_PIPX_BIN" install \
    ${SFT_PIPX_BACKEND_ARGS[@]+"${SFT_PIPX_BACKEND_ARGS[@]}"} \
    "${SFT_PIPX_TEST_PKG}==${SFT_PIPX_TEST_PKG_VERSION}"

  # Ensure no payload under venvs/ and no symlink in ~/.local/bin
  sft_assert_path_absent "${venvs_dir}/${SFT_PIPX_TEST_PKG}"
  sft_assert_path_absent "${fake_home}/.local/bin/${SFT_PIPX_TEST_PKG}"
}

# === Pre-Installed Global Tools: Usable, Immutable ===
#
# Setup installs outside the sandbox, as a user would before starting an agent.

@test "[EXECUTION] a pipx-installed global binary runs (pip backend)" {
  sft_pipx_use_backend pip
  sft_pipx_test_installed_binary_runs
}
@test "[EXECUTION] a pipx-installed global binary runs (uv backend)" {
  sft_pipx_use_backend uv
  sft_pipx_test_installed_binary_runs
}
@test "[EXECUTION] a pipx-installed global binary runs (legacy ~/.local/pipx home)" {
  sft_pipx_use_backend pip
  sft_pipx_use_home legacy
  sft_pipx_test_installed_binary_runs
}
sft_pipx_test_installed_binary_runs() {
  local fake_home
  fake_home="$(sft_pipx_fake_home)" || return 1
  sft_pipx_install_outside_sandbox "$fake_home" || return 1

  # Ensure can run the binary, via its ~/.local/bin symlink into venvs/
  HOME="$fake_home" safehouse_run -- "${fake_home}/.local/bin/${SFT_PIPX_TEST_PKG}" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_PIPX_TEST_PKG_VERSION"
}

@test "[EXECUTION] a pipx-installed global binary cannot be modified (pip backend)" {
  sft_pipx_use_backend pip
  sft_pipx_test_installed_binary_immutable
}
@test "[EXECUTION] a pipx-installed global binary cannot be modified (uv backend)" {
  sft_pipx_use_backend uv
  sft_pipx_test_installed_binary_immutable
}
@test "[EXECUTION] a pipx-installed global binary cannot be modified (legacy ~/.local/pipx home)" {
  sft_pipx_use_backend pip
  sft_pipx_use_home legacy
  sft_pipx_test_installed_binary_immutable
}
sft_pipx_test_installed_binary_immutable() {
  local fake_home pipx_home venvs_dir venv_dir pkg_dir bin_link snapshot_before
  fake_home="$(sft_pipx_fake_home)" || return 1
  sft_pipx_install_outside_sandbox "$fake_home" || return 1

  pipx_home="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_HOME)" || return 1
  venvs_dir="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_LOCAL_VENVS)" || return 1
  venv_dir="${venvs_dir}/${SFT_PIPX_TEST_PKG}"
  pkg_dir="$(sft_py_venv_site_packages "$venv_dir")/${SFT_PIPX_TEST_PKG}" || return 1
  bin_link="${fake_home}/.local/bin/${SFT_PIPX_TEST_PKG}"
  sft_assert_file_exists "${pkg_dir}/__init__.py"

  # Remove the package's __pycache__, as if the tool had never run
  # NOTE: The uv backend does not precompile, so it has none to begin with.
  rm -rf "${pkg_dir}/__pycache__" || return 1
  snapshot_before="$(sft_tree_snapshot "$venvs_dir" "$bin_link")" || return 1

  # Ensure cannot modify the tool with pipx subcommands
  HOME="$fake_home" safehouse_denied -- "$SFT_PIPX_BIN" reinstall "$SFT_PIPX_TEST_PKG"
  HOME="$fake_home" safehouse_denied -- "$SFT_PIPX_BIN" uninstall "$SFT_PIPX_TEST_PKG"
  HOME="$fake_home" safehouse_denied -- "$SFT_PIPX_BIN" inject "$SFT_PIPX_TEST_PKG" six
  HOME="$fake_home" safehouse_denied -- "$SFT_PIPX_BIN" runpip "$SFT_PIPX_TEST_PKG" install six
  # NOTE: May succeed without writing anything if already at the latest version.
  #       The snapshot comparison below catches any write.
  HOME="$fake_home" safehouse_run -- "$SFT_PIPX_BIN" upgrade "$SFT_PIPX_TEST_PKG"

  # Ensure cannot write to the payload directly,
  # including to its __pycache__ which a Python tool writes on first run
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${venv_dir}/bin/${SFT_PIPX_TEST_PKG}"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${pkg_dir}/__init__.py"
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "${pkg_dir}/__pycache__"
  HOME="$fake_home" safehouse_denied -- /bin/rm "$bin_link"

  # Ensure cannot move the payload out from under the read-only rule,
  # where it could be modified and then moved back
  HOME="$fake_home" safehouse_denied -- /bin/mv "$venvs_dir" "$(sft_workspace_path "moved_venvs")"
  HOME="$fake_home" safehouse_denied -- /bin/mv "$pipx_home" "$(sft_workspace_path "moved_pipx_home")"

  # Ensure cannot hard link the payload into the workspace, to modify it there
  HOME="$fake_home" safehouse_denied -- /bin/ln "${venv_dir}/bin/${SFT_PIPX_TEST_PKG}" "$(sft_workspace_path "linked_bin")"

  # Ensure the tool still runs, without being able to write its __pycache__
  HOME="$fake_home" safehouse_run -- "$bin_link" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_PIPX_TEST_PKG_VERSION"
  sft_assert_path_absent "${pkg_dir}/__pycache__"

  # Ensure nothing changed
  [ -d "$pipx_home" ]
  [ "$(sft_tree_snapshot "$venvs_dir" "$bin_link")" = "$snapshot_before" ]
}

# Only the pip backend has shared libraries.

@test "[EXECUTION] pipx shared libraries cannot be modified" {
  sft_pipx_use_backend pip
  sft_pipx_test_shared_libs_immutable
}
@test "[EXECUTION] pipx shared libraries cannot be modified (legacy ~/.local/pipx home)" {
  sft_pipx_use_backend pip
  sft_pipx_use_home legacy
  sft_pipx_test_shared_libs_immutable
}
sft_pipx_test_shared_libs_immutable() {
  # pipx/shared/ is on every installed tool's sys.path (via a .pth file),
  # so a write there (e.g. a sitecustomize.py) would run inside every tool,
  # outside the sandbox.
  local fake_home shared_dir site_dir snapshot_before
  fake_home="$(sft_pipx_fake_home)" || return 1
  sft_pipx_install_outside_sandbox "$fake_home" || return 1

  shared_dir="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_SHARED_LIBS)" || return 1
  site_dir="$(sft_py_venv_site_packages "$shared_dir")" || return 1
  sft_assert_file_exists "${site_dir}/pip/__init__.py"
  snapshot_before="$(sft_tree_snapshot "$shared_dir")" || return 1

  # Ensure cannot modify pipx/shared/ with pipx subcommands
  # NOTE: May succeed without writing anything if pip is already at the latest version.
  #       The snapshot comparison below catches any write.
  HOME="$fake_home" safehouse_run -- "$SFT_PIPX_BIN" upgrade-shared

  # Ensure cannot write to pipx/shared/ directly
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${site_dir}/sitecustomize.py"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${site_dir}/pip/__init__.py"
  HOME="$fake_home" safehouse_denied -- /bin/mv "$shared_dir" "$(sft_workspace_path "moved_shared")"
  HOME="$fake_home" safehouse_denied -- /bin/ln "${site_dir}/pip/__init__.py" "$(sft_workspace_path "linked_pip_init")"

  # Ensure nothing changed
  sft_assert_path_absent "${site_dir}/sitecustomize.py"
  [ "$(sft_tree_snapshot "$shared_dir")" = "$snapshot_before" ]
}

# === Interpreters ===

@test "[EXECUTION] pipx run --fetch-python cannot provision a standalone interpreter (pip backend)" {
  sft_pipx_use_backend pip
  sft_pipx_test_fetch_python_denied
}
@test "[EXECUTION] pipx run --fetch-python cannot provision a standalone interpreter (uv backend)" {
  # NOTE: pipx downloads the interpreter itself, into py/, under either backend.
  sft_pipx_use_backend uv
  sft_pipx_test_fetch_python_denied
}
sft_pipx_test_fetch_python_denied() {
  local fake_home py_dir fetch_arg py_version
  sft_pipx_fetch_python_args_or_skip fetch_arg py_version

  fake_home="$(sft_pipx_fake_home)" || return 1
  sft_pipx_prepare_home_outside_sandbox "$fake_home" || return 1
  sft_pipx_load_python_index "$fake_home" || return 1
  py_dir="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_STANDALONE_PYTHON_CACHEDIR)" || return 1

  # Ensure cannot download a standalone interpreter into py/
  HOME="$fake_home" safehouse_denied -- "$SFT_PIPX_BIN" run \
    ${SFT_PIPX_BACKEND_ARGS[@]+"${SFT_PIPX_BACKEND_ARGS[@]}"} \
    "$fetch_arg" --python "$py_version" \
    "${SFT_PIPX_TEST_PKG}==${SFT_PIPX_TEST_PKG_VERSION}" --version
  sft_assert_path_absent "${py_dir}/${py_version}"

  # Ensure nothing is put on global PATH
  [ -z "$(ls -A "${fake_home}/.local/bin")" ]
}

@test "[EXECUTION] a pipx-fetched standalone interpreter cannot be modified" {
  sft_pipx_use_backend pip
  sft_pipx_test_fetched_python_immutable
}

@test "[EXECUTION] a pipx-fetched standalone interpreter cannot be modified (legacy ~/.local/pipx home)" {
  sft_pipx_use_backend pip
  sft_pipx_use_home legacy
  sft_pipx_test_fetched_python_immutable
}
sft_pipx_test_fetched_python_immutable() {
  # An installed tool's venv uses the fetched interpreter as its Python home,
  # so a write to its stdlib (e.g. a sitecustomize.py) would run inside the tool,
  # outside the sandbox.
  local fake_home py_dir fetch_arg py_version interp_dir stdlib_dir snapshot_before output
  sft_pipx_fetch_python_args_or_skip fetch_arg py_version

  # Outside sandbox, install a tool with a fetched interpreter
  # NOTE: Prints pipx's output and logs on failure
  fake_home="$(sft_pipx_fake_home)" || return 1
  sft_pipx_load_python_index "$fake_home" || return 1
  if ! output="$(HOME="$fake_home" "$SFT_PIPX_BIN" install \
      ${SFT_PIPX_BACKEND_ARGS[@]+"${SFT_PIPX_BACKEND_ARGS[@]}"} \
      "$fetch_arg" --python "$py_version" \
      "${SFT_PIPX_TEST_PKG}==${SFT_PIPX_TEST_PKG_VERSION}" 2>&1)"; then
    local log_dir log_file
    printf 'pipx install with a fetched Python %s failed:\n%s\n' "$py_version" "$output" >&2
    log_dir="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_LOG_DIR)" || return 1
    for log_file in "$log_dir"/*.log; do
      [ -f "$log_file" ] || continue
      printf '\n=== pipx log: %s\n' "$log_file" >&2
      cat "$log_file" >&2
    done
    return 1
  fi
  py_dir="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_STANDALONE_PYTHON_CACHEDIR)" || return 1
  interp_dir="${py_dir}/${py_version}"
  stdlib_dir="${interp_dir}/lib/python${py_version}"
  sft_assert_file_exists "${stdlib_dir}/site.py"
  snapshot_before="$(sft_tree_snapshot "$py_dir")" || return 1

  # Ensure cannot write to the interpreter directly
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${stdlib_dir}/sitecustomize.py"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${stdlib_dir}/site.py"
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${interp_dir}/bin/python${py_version}"

  # Ensure cannot move or hard link it out from under the read-only rule
  HOME="$fake_home" safehouse_denied -- /bin/mv "$interp_dir" "$(sft_workspace_path "moved_interp")"
  HOME="$fake_home" safehouse_denied -- /bin/mv "$py_dir" "$(sft_workspace_path "moved_py")"
  HOME="$fake_home" safehouse_denied -- /bin/ln "${stdlib_dir}/site.py" "$(sft_workspace_path "linked_site_py")"

  # Ensure the installed tool still runs with it
  HOME="$fake_home" safehouse_run -- "${fake_home}/.local/bin/${SFT_PIPX_TEST_PKG}" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_PIPX_TEST_PKG_VERSION"

  # Ensure nothing changed
  sft_assert_path_absent "${stdlib_dir}/sitecustomize.py"
  [ "$(sft_tree_snapshot "$py_dir")" = "$snapshot_before" ]
}

# === Cache Poisoning: Accepted Risk ===
#
# Only the pip backend has its own venv cache. Under the uv backend,
# `pipx run` uses uv's cache, which uv.bats covers.

# NOTE: Test characterizes current behavior. Ideal behavior would disallow tampering.
@test "[EXECUTION] can tamper with a cached pipx venv to place a binary where it will run outside sandbox" {
  local fake_home cache_dir venv_dirs cached_bin fake_bin
  sft_pipx_use_backend pip
  fake_home="$(sft_pipx_fake_home)" || return 1

  # Outside sandbox, create a cached venv
  HOME="$fake_home" run "$SFT_PIPX_BIN" run \
    ${SFT_PIPX_BACKEND_ARGS[@]+"${SFT_PIPX_BACKEND_ARGS[@]}"} \
    "${SFT_PIPX_TEST_PKG}==${SFT_PIPX_TEST_PKG_VERSION}" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$SFT_PIPX_TEST_PKG_VERSION"

  # Locate the cached venv's console script (at PIPX_VENV_CACHEDIR/<hash>/bin/<pkg>)
  cache_dir="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_VENV_CACHEDIR)" || return 1
  venv_dirs=("$cache_dir"/*/)
  [ "${#venv_dirs[@]}" -eq 1 ]
  cached_bin="${venv_dirs[0]}bin/${SFT_PIPX_TEST_PKG}"
  sft_assert_file_exists "$cached_bin"

  # Inside sandbox, replace the console script
  fake_bin="$(sft_workspace_path "fake_cowsay")" || return 1
  printf '%s\n' '#!/bin/sh' "echo \"I'm not cowsay\"" > "$fake_bin"
  HOME="$fake_home" safehouse_ok -- /bin/cp "$fake_bin" "$cached_bin"

  # Outside sandbox, rerun the same tool.
  # Ensure the reused venv ran the replaced script.
  HOME="$fake_home" run "$SFT_PIPX_BIN" run \
    ${SFT_PIPX_BACKEND_ARGS[@]+"${SFT_PIPX_BACKEND_ARGS[@]}"} \
    "${SFT_PIPX_TEST_PKG}==${SFT_PIPX_TEST_PKG_VERSION}" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "I'm not cowsay"
}

# ------------------------------------------------------------------------------
# Utility

# 1. Skip the current test if the requested backend is unavailable.
# 2. Set SFT_PIPX_BACKEND to its name.
# 3. Set SFT_PIPX_BACKEND_ARGS to the args that select it,
#    to pass to pipx subcommands that accept --backend.
#
# NOTE: Selects the backend with --backend rather than PIPX_DEFAULT_BACKEND
#       because the sandbox does not pass that env var through by default.
sft_pipx_use_backend() {
  local backend="$1" uv_bin

  case "$backend" in
    pip)
      SFT_PIPX_BACKEND=pip
      # pipx before 1.12 has no --backend option and always uses pip
      SFT_PIPX_BACKEND_ARGS=()
      [ "$SFT_PIPX_HAS_BACKENDS" != "1" ] || SFT_PIPX_BACKEND_ARGS=(--backend pip)
      ;;
    uv)
      [ "$SFT_PIPX_HAS_BACKENDS" = "1" ] || skip "pipx does not support --backend"
      sft_command_path_or_skip uv_bin uv
      # pipx finds uv on PATH. A PATH entry under the host HOME is dropped
      # from the sandbox's PATH because each test runs with a fake HOME,
      # so a real user's ~/.local/bin/uv would be found but this one not.
      case "$uv_bin" in
        "$SAFEHOUSE_HOST_HOME"/*)
          skip "uv is installed under the host HOME (${uv_bin}), which the sandbox cannot see under a fake HOME. Suggest install uv via brew instead."
          ;;
      esac
      SFT_PIPX_BACKEND=uv
      SFT_PIPX_BACKEND_ARGS=(--backend uv)
      ;;
    *)
      echo "unknown pipx backend: $backend" >&2
      return 1
      ;;
  esac
}

# Sets SFT_PIPX_HOME_KIND, the PIPX_HOME location that sft_pipx_fake_home sets up:
# - default: ~/Library/Application Support/pipx (pipx 1.16+). Used if never called.
# - legacy:  ~/.local/pipx
sft_pipx_use_home() {
  local kind="$1"

  case "$kind" in
    default|legacy)
      SFT_PIPX_HOME_KIND="$kind"
      ;;
    *)
      echo "unknown pipx home kind: $kind" >&2
      return 1
      ;;
  esac
}

# Creates a fake home with the ~/Library directories macOS creates for every
# new user, where pipx puts its default home, cache and logs. For a legacy
# SFT_PIPX_HOME_KIND, also creates ~/.local/pipx and ensures pipx will use it.
# Prints the fake home's path.
sft_pipx_fake_home() {
  local fake_home pipx_home expected_pipx_home
  fake_home="$(sft_fake_home --macos-dirs)" || return 1

  if [ "${SFT_PIPX_HOME_KIND:-default}" = "legacy" ]; then
    mkdir -p "${fake_home}/.local/pipx" || return 1
    expected_pipx_home="${fake_home}/.local/pipx"
  else  # default
    expected_pipx_home="${fake_home}/Library/Application Support/pipx"
  fi

  pipx_home="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_HOME)" || return 1
  if [ "$pipx_home" != "$expected_pipx_home" ]; then
    echo "expected PIPX_HOME=${expected_pipx_home}, got ${pipx_home}" >&2
    return 1
  fi

  printf '%s\n' "$fake_home"
}

# Installs the test package with pipx outside the sandbox, as a user would
# before starting a sandboxed agent.
#
# Global paths created, inside $fake_home: same as
# sft_pipx_prepare_home_outside_sandbox, plus:
# - PIPX_HOME/venvs/<pkg>
# - ~/.local/bin/<pkg>, a symlink into it
sft_pipx_install_outside_sandbox() {
  local fake_home="$1"

  HOME="$fake_home" "$SFT_PIPX_BIN" install \
    ${SFT_PIPX_BACKEND_ARGS[@]+"${SFT_PIPX_BACKEND_ARGS[@]}"} \
    "${SFT_PIPX_TEST_PKG}==${SFT_PIPX_TEST_PKG_VERSION}" >/dev/null
}

# Runs pipx once outside the sandbox, as a user would before starting
# a sandboxed agent.
#
# Global paths created, inside $fake_home:
# - PIPX_HOME (e.g. ~/Library/Application Support/pipx)
#     - shared/ (pip backend only), which is read-only inside the sandbox
# - ~/.local/bin
# - ~/.local/share/man
# - ~/.local/share/uv/tools (uv backend only), which `uv tool run` needs
#   and cannot create inside the sandbox
sft_pipx_prepare_home_outside_sandbox() {
  local fake_home="$1" cache_dir

  if [ "$SFT_PIPX_BACKEND" = "uv" ]; then
    # 1. Run a pipx command, creating pipx's global paths
    # 2. Run `uv tool run`, via `pipx run`, creating uv's global paths
    HOME="$fake_home" "$SFT_PIPX_BIN" run \
      ${SFT_PIPX_BACKEND_ARGS[@]+"${SFT_PIPX_BACKEND_ARGS[@]}"} \
      "${SFT_PIPX_TEST_PKG}==${SFT_PIPX_TEST_PKG_VERSION}" --version >/dev/null || return 1

    # Remove the cached venv
    HOME="$fake_home" uv cache clean >/dev/null 2>&1 || return 1

    return
  fi
  
  if [ "$SFT_PIPX_BACKEND" = "pip" ]; then
    # 1. Run a pipx command, creating pipx's global paths
    # 2. Create a venv, because the pip backend creates shared/ only on first venv creation
    HOME="$fake_home" "$SFT_PIPX_BIN" run \
      ${SFT_PIPX_BACKEND_ARGS[@]+"${SFT_PIPX_BACKEND_ARGS[@]}"} \
      "${SFT_PIPX_TEST_PKG}==${SFT_PIPX_TEST_PKG_VERSION}" --version >/dev/null || return 1

    # Remove the cached venv
    cache_dir="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_VENV_CACHEDIR)" || return 1
    rm -rf "${cache_dir:?}"/*/ || return 1
    
    return
  fi
}

# Writes python-build-standalone's latest release index to $1, in the format
# of the index that pipx caches.
#
# Authenticates with GH_TOKEN if set. Unauthenticated, the GitHub API has a
# lower rate limit.
sft_pipx_fetch_python_index() {
  local index_file="$1" release_file="${1}.release" auth_file="${1}.auth"

  # NOTE: Passes the token in a file, not argv, so that ps cannot see it.
  ( umask 077; : > "$auth_file" ) || return 1
  [ -z "${GH_TOKEN:-}" ] \
    || printf 'Authorization: Bearer %s\n' "$GH_TOKEN" > "$auth_file" || return 1
  curl -fsSL --retry 3 -o "$release_file" \
    -H "@${auth_file}" -H 'Accept: application/vnd.github+json' \
    https://api.github.com/repos/astral-sh/python-build-standalone/releases/latest
  local rc=$?
  rm -f "$auth_file"
  [ "$rc" -eq 0 ] || return 1

  # NOTE: macOS 15+ is known to ship jq
  jq -c '{fetched: now, releases: [.assets[] | [.browser_download_url, .digest]]}' \
    "$release_file" > "$index_file" || return 1
  rm -f "$release_file"
}

# Copies the index from sft_pipx_fetch_python_index into the fake home at $1,
# so that pipx does not fetch the index itself when it downloads an interpreter.
# pipx trusts a cached index for 30 days (pipx 1.18).
sft_pipx_load_python_index() {
  local fake_home="$1" py_dir

  [ -s "$SFT_PIPX_PYTHON_INDEX" ] || {
    echo "python-build-standalone index missing: setup_file could not fetch it" >&2
    return 1
  }
  py_dir="$(sft_pipx_env_value_outside_sandbox "$fake_home" PIPX_STANDALONE_PYTHON_CACHEDIR)" || return 1
  mkdir -p "$py_dir" || return 1
  cp "$SFT_PIPX_PYTHON_INDEX" "${py_dir}/index.json"
}

# Sets the variable named $1 to the pipx option that downloads a standalone
# interpreter, and the variable named $2 to a Python version to download.
#
# Skips the current test if pipx cannot download interpreters, or if it can
# download only missing versions and every candidate is already on PATH.
sft_pipx_fetch_python_args_or_skip() {
  local arg_var="$1" version_var="$2" run_help version

  run_help="$("$SFT_PIPX_BIN" run --help 2>/dev/null)"
  if [[ "$run_help" == *"--fetch-python"* ]]; then
    # Prepare to install a fixed Python version,
    # regardless of any Python versions on PATH
    printf -v "$arg_var" '%s' "--fetch-python=always"
    printf -v "$version_var" '%s' "3.13"
    return 0
  fi
  if [[ "$run_help" == *"--fetch-missing-python"* ]]; then
    # Prepare to install a Python version that is not on PATH.
    # NOTE: Each candidate must be one that python-build-standalone provides.
    for version in 3.13 3.12 3.11 3.14; do
      command -v "python${version}" >/dev/null 2>&1 && continue
      printf -v "$arg_var" '%s' "--fetch-missing-python"
      printf -v "$version_var" '%s' "$version"
      return 0
    done
    skip "every candidate Python version is already on PATH"
  fi
  skip "pipx cannot download standalone interpreters"
}

# Prints the value of a `pipx environment` variable for $fake_home.
sft_pipx_env_value_outside_sandbox() {
  local fake_home="$1" name="$2"

  HOME="$fake_home" "$SFT_PIPX_BIN" environment --value "$name"
}

# ------------------------------------------------------------------------------
