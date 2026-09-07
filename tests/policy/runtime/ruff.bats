#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Ruff linting toolchain tests.
# Verifies that Ruff works inside the default sandbox including cache file operations.
#
load ../../test_helper.bash

@test "[EXECUTION] ruff can lint a file inside the sandbox" {
  local ruff_bin source_file
  sft_command_path_or_skip ruff_bin ruff
  source_file="$(sft_workspace_path "sample.py")" || return 1

  cat > "$source_file" <<'EOF'
def hello_world():
    print("Hello, World!")
    # This is a simple comment
    x = 1 + 2
    return x

if __name__ == "__main__":
    hello_world()
EOF

  # Run ruff check to lint the file
  run safehouse_ok -- "$ruff_bin" check "$source_file"
  [ "$status" -eq 0 ]
}

@test "[EXECUTION] ruff can write cache files inside the sandbox" {
  local ruff_bin source_file cache_dir
  sft_command_path_or_skip ruff_bin ruff
  source_file="$(sft_workspace_path "cache_test.py")" || return 1
  cache_dir="$(sft_workspace_path ".ruff_cache")" || return 1

  cat > "$source_file" <<'EOF'
def cached_function():
    return "test"
EOF

  # Clear any existing cache to ensure we write new cache files
  rm -rf "$cache_dir"

  # Run ruff check to trigger cache file creation
  run safehouse_ok -- "$ruff_bin" check "$source_file"
  [ "$status" -eq 0 ]

  # Assert an actual cache file was written
  run safehouse_ok -- find "$cache_dir" -type f
  [ "$status" -eq 0 ]
  [ -n "$output" ]
}

@test "[EXECUTION] ruff can format a file inside the sandbox" {
  local ruff_bin source_file
  sft_command_path_or_skip ruff_bin ruff
  source_file="$(sft_workspace_path "format_test.py")" || return 1

  cat > "$source_file" <<'EOF'
def bad_format():
    x=1
    y=2
    return x+y
EOF

  # Run ruff format to format the file
  run safehouse_ok -- "$ruff_bin" format "$source_file"
  [ "$status" -eq 0 ]

  # Verify the file was formatted in place (ruff adds spaces around =)
  run grep -q "x = 1" "$source_file"
  [ "$status" -eq 0 ]
}

@test "[EXECUTION] ruff respects configuration in the sandbox" {
  local ruff_bin source_file
  sft_command_path_or_skip ruff_bin ruff
  source_file="$(sft_workspace_path ".ruff.toml")" || return 1
  local py_file
  py_file="$(sft_workspace_path "config_test.py")" || return 1

  cat > "$source_file" <<'EOF'
line-length = 20
[lint]
select = ["E501"]
EOF

  # Create a Python file with long lines that E501 flags under the config above
  cat > "$py_file" <<'EOF'
def long_line_function():
    very_long_variable_name_that_exceeds_twenty_characters = "value"
    return very_long_variable_name_that_exceeds_twenty_characters
EOF

  # Config must be discovered and applied: the long lines are flagged
  run safehouse_ok -- "$ruff_bin" check "$py_file"
  [ "$status" -ne 0 ]
  [[ "$output" == *E501* ]]
}

@test "[POLICY-ONLY] default profile includes the ruff cache path" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_contains "$profile" "(home-subpath \"/.cache/ruff\")"
}

@test "[EXECUTION] ruff installed via uv tool install is runnable in the sandbox" {
  local fake_home tool_bin shim

  fake_home="$(sft_fake_home)" || return 1
  tool_bin="${fake_home}/.local/share/uv/tools/ruff/bin/ruff"
  shim="${fake_home}/.local/bin/ruff"

  # Reproduce the `uv tool install ruff` layout: the real binary lives under
  # ~/.local/share/uv/tools, and ~/.local/bin/ruff is a symlink to it.
  sft_make_fake_command "$tool_bin" || return 1
  mkdir -p "${fake_home}/.local/bin" || return 1
  /bin/ln -sfn "$tool_bin" "$shim"

  HOME="$fake_home" safehouse_ok -- "$shim"
}

@test "[EXECUTION] the uv-managed ruff entrypoint is not writable in the sandbox" {
  local fake_home tool_bin shim

  fake_home="$(sft_fake_home)" || return 1
  tool_bin="${fake_home}/.local/share/uv/tools/ruff/bin/ruff"
  shim="${fake_home}/.local/bin/ruff"

  sft_make_fake_command "$tool_bin" || return 1
  mkdir -p "${fake_home}/.local/bin" || return 1

  # Running a globally installed ruff is in scope; installing or upgrading one
  # from inside the sandbox is not. `uv tool upgrade ruff` rewrites this symlink,
  # so the grant stays read-only and link creation here must be refused.
  HOME="$fake_home" safehouse_denied -- /bin/ln -sfn "$tool_bin" "$shim"
}

@test "[EXECUTION] other uv tool entrypoints resolve without a per-tool grant" {
  local fake_home other_target other_shim

  fake_home="$(sft_fake_home)" || return 1
  other_target="${fake_home}/.local/share/uv/tools/black/bin/black"
  other_shim="${fake_home}/.local/bin/black"

  # No profile names black. The shim resolves because ~/.local/bin is readable,
  # so uv-installed tools run without a grant each.
  sft_make_fake_command "$other_target" || return 1
  mkdir -p "${fake_home}/.local/bin" || return 1
  /bin/ln -sfn "$other_target" "$other_shim"

  HOME="$fake_home" safehouse_ok -- "$other_shim"
}
