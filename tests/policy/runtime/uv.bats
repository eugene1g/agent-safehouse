#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# uv toolchain tests.
# Verifies that uv works inside the default sandbox including virtualenv creation
# and package installation from a local HTTP registry without external PyPI access.
#
load ../../test_helper.bash

@test "[POLICY-ONLY] default profile includes uv cache and state subpaths" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_contains "$profile" "(home-subpath \"/.cache/uv\")"
  sft_assert_contains "$profile" "(home-subpath \"/.local/share/uv\")"
}

@test "[EXECUTION] uv version works inside the sandbox" {
  sft_require_cmd_or_skip uv

  local uv_bin
  uv_bin="$(sft_command_path_or_skip uv)" || skip "uv is not installed"

  safehouse_ok -- "$uv_bin" --version
}

@test "[EXECUTION] uv can create a virtual environment inside the sandbox" {
  sft_require_cmd_or_skip uv

  local uv_bin venv_dir
  uv_bin="$(sft_command_path_or_skip uv)" || skip "uv is not installed"
  venv_dir="$(sft_workspace_path "uv_venv")" || return 1

  safehouse_ok -- "$uv_bin" venv "$venv_dir"
  [ -d "$venv_dir/bin" ]
  [ -x "$venv_dir/bin/python" ]
}

@test "[EXECUTION] uv can download and install a package from a local registry inside the sandbox" {
  sft_require_cmd_or_skip uv
  sft_require_cmd_or_skip python3

  local uv_bin repo_dir server_pid port venv_dir
  uv_bin="$(sft_command_path_or_skip uv)" || skip "uv is not installed"
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

  # Wait for port file
  local i
  for i in {1..50}; do
    if [ -f "$SAFEHOUSE_WORKSPACE/port.txt" ]; then break; fi
    sleep 0.05
  done

  if [ ! -f "$SAFEHOUSE_WORKSPACE/port.txt" ]; then
    kill "$server_pid" 2>/dev/null || true
    skip "failed to start local http registry server"
  fi

  port="$(cat "$SAFEHOUSE_WORKSPACE/port.txt")"

  # Create venv and install from local registry inside sandbox
  safehouse_ok -- "$uv_bin" venv "$venv_dir"
  safehouse_ok -- "$uv_bin" pip install --index-url "http://127.0.0.1:${port}/" samplepkg --python "$venv_dir/bin/python"

  # Clean up background HTTP server
  kill "$server_pid" 2>/dev/null || true
  wait "$server_pid" 2>/dev/null || true

  # Verify package installation and execution
  run "$venv_dir/bin/python" -c "import samplepkg; print(samplepkg.VALUE)"
  [ "$status" -eq 0 ]
  [ "$output" = "sandboxed-uv-success" ]
}
