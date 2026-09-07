#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# uv toolchain tests.
# Verifies that uv works inside the default sandbox including virtualenv creation
# and package installation from a local HTTP registry without external PyPI access.
#
load ../../test_helper.bash

# Global for teardown to reap the background HTTP server if the test aborts early
server_pid=""

# Overrides the shared teardown (test_helper.bash) to also reap the HTTP server, which the
# in-test cleanup misses when a test aborts on a failed assertion. A leaked server
# keeps holding its port, so it breaks the next run of the test too.
teardown() {
  if [ -n "${server_pid:-}" ]; then
    kill "$server_pid" 2>/dev/null || true
    wait "$server_pid" 2>/dev/null || true
  fi

  sft_teardown_test_env
}

@test "[POLICY-ONLY] default profile includes the uv cache, data, state, and config subpaths" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_contains "$profile" "(home-subpath \"/.cache/uv\")"
  sft_assert_contains "$profile" "(home-subpath \"/.local/share/uv\")"
  sft_assert_contains "$profile" "(home-subpath \"/.local/state/uv\")"
  sft_assert_contains "$profile" "(home-subpath \"/.config/uv\")"
}

@test "[EXECUTION] uv version works inside the sandbox" {
  sft_require_cmd_or_skip uv

  local uv_bin
  sft_command_path_or_skip uv_bin uv

  safehouse_ok -- "$uv_bin" --version
}

@test "[EXECUTION] uv can create a virtual environment inside the sandbox" {
  sft_require_cmd_or_skip uv

  local uv_bin venv_dir
  sft_command_path_or_skip uv_bin uv
  venv_dir="$(sft_workspace_path "uv_venv")" || return 1

  safehouse_ok -- "$uv_bin" venv "$venv_dir"
  [ -d "$venv_dir/bin" ]
  [ -x "$venv_dir/bin/python" ]
}

@test "[EXECUTION] uv can download and install a package from a local registry inside the sandbox" {
  sft_require_cmd_or_skip uv
  sft_require_cmd_or_skip python3

  local uv_bin repo_dir port venv_dir
  sft_command_path_or_skip uv_bin uv
  repo_dir="$(sft_workspace_path "local_pypi")" || return 1
  venv_dir="$(sft_workspace_path "test_venv")" || return 1

  mkdir -p "$repo_dir/samplepkg" || return 1

  # Create a valid Python wheel in a local PEP 503 simple repository layout
  python3 - "$repo_dir" <<'PYEOF'
import sys, os, zipfile

repo_dir = sys.argv[1]
wheel_path = os.path.join(repo_dir, "samplepkg", "samplepkg-0.1.0-py3-none-any.whl")

with zipfile.ZipFile(wheel_path, "w") as zf:
    zf.writestr(
        "samplepkg-0.1.0.dist-info/METADATA",
        "Metadata-Version: 2.1\nName: samplepkg\nVersion: 0.1.0\n",
    )
    zf.writestr(
        "samplepkg-0.1.0.dist-info/WHEEL",
        "Wheel-Version: 1.0\nGenerator: test\nRoot-Is-Purelib: true\nTag: py3-none-any\n",
    )
    zf.writestr("samplepkg-0.1.0.dist-info/RECORD", "")
    zf.writestr("samplepkg/__init__.py", "VALUE = 'sandboxed-uv-success'\n")

with open(os.path.join(repo_dir, "samplepkg", "index.html"), "w") as f:
    f.write('<!DOCTYPE html><html><body><a href="samplepkg-0.1.0-py3-none-any.whl">samplepkg-0.1.0-py3-none-any.whl</a></body></html>')
PYEOF

  # Start a lightweight local HTTP registry server
  python3 -c '
import http.server, socketserver, os, sys

class Handler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, format, *args):
        pass

os.chdir(sys.argv[1])
with socketserver.TCPServer(("127.0.0.1", 0), Handler) as httpd:
    port = httpd.server_address[1]
    with open(sys.argv[2], "w") as f:
        f.write(str(port))
    httpd.serve_forever()
' "$repo_dir" "$SAFEHOUSE_WORKSPACE/port.txt" &
  server_pid=$!

  # Wait for the server to report its port. The file is created empty and filled a
  # moment later, so wait for content rather than existence. The budget is generous
  # because a cold machine can take seconds just to start python3.
  local i
  for i in {1..200}; do
    if [ -s "$SAFEHOUSE_WORKSPACE/port.txt" ]; then break; fi
    sleep 0.05
  done

  if [ ! -s "$SAFEHOUSE_WORKSPACE/port.txt" ]; then
    # Fail rather than skip: this fixture is ours, so failing to start it is a test
    # bug. Skipping would let CI pass green without ever exercising the install path.
    printf 'local http registry server did not report a port within 10s\n' >&2
    return 1
  fi

  port="$(cat "$SAFEHOUSE_WORKSPACE/port.txt")"

  # Create venv and install from local registry inside sandbox
  safehouse_ok -- "$uv_bin" venv "$venv_dir"
  safehouse_ok -- "$uv_bin" pip install --index-url "http://127.0.0.1:${port}/" samplepkg --python "$venv_dir/bin/python"

  # Verify package installation and execution
  run "$venv_dir/bin/python" -c "import samplepkg; print(samplepkg.VALUE)"
  [ "$status" -eq 0 ]
  [ "$output" = "sandboxed-uv-success" ]
}

@test "[POLICY-ONLY] default profile keeps the uv tool directory read-only" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_contains "$profile" "(deny file-write*"
  sft_assert_contains "$profile" "(home-subpath \"/.local/share/uv/tools\")"
}

@test "[EXECUTION] installed uv tool payloads are readable but not writable" {
  local fake_home tool_bin

  fake_home="$(sft_fake_home)" || return 1
  tool_bin="${fake_home}/.local/share/uv/tools/ruff/bin/ruff"

  sft_make_fake_command "$tool_bin" || return 1

  # Running an installed tool stays in scope: the payload is readable and exec'able.
  HOME="$fake_home" safehouse_ok -- /bin/cat "$tool_bin" >/dev/null
  HOME="$fake_home" safehouse_ok -- "$tool_bin"

  # Mutating it is not. This covers both `uv tool upgrade` rewriting the payload and
  # the __pycache__ writes a Python tool attempts on first run.
  HOME="$fake_home" safehouse_denied -- /usr/bin/touch "${tool_bin}.new"
  HOME="$fake_home" safehouse_denied -- /bin/mkdir "$(dirname "$tool_bin")/__pycache__"
}

@test "[EXECUTION] uv managed interpreters stay writable" {
  local fake_home python_dir

  fake_home="$(sft_fake_home)" || return 1
  python_dir="${fake_home}/.local/share/uv/python"

  mkdir -p "$python_dir" || return 1

  # `uv run`, `uv sync` and `uv venv --python X.Y` provision interpreters here as
  # ordinary project work, so narrowing tools/ must not reach python/.
  HOME="$fake_home" safehouse_ok -- /usr/bin/touch "${python_dir}/cpython-marker"
  sft_assert_file_exists "${python_dir}/cpython-marker"
}
