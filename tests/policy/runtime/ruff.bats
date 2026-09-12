#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Ruff linting toolchain tests.
# Verifies that Ruff works inside the default sandbox including cache file operations.
#
load ../../test_helper.bash

@test "[EXECUTION] ruff can lint a file inside the sandbox" {
  local ruff_bin source_file "code"
  ruff_bin="$(sft_command_path_or_skip ruff)" || return 1
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
  ruff_bin="$(sft_command_path_or_skip ruff)" || return 1
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

  # Ruff's default cache is .ruff_cache under the working directory
  run safehouse_ok -- ls "$cache_dir"
  [ "$status" -eq 0 ]
}

@test "[EXECUTION] ruff can format a file inside the sandbox" {
  local ruff_bin source_file "code"
  ruff_bin="$(sft_command_path_or_skip ruff)" || return 1
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
  ruff_bin="$(sft_command_path_or_skip ruff)" || return 1
  source_file="$(sft_workspace_path ".ruff.toml")" || return 1
  local py_file
  py_file="$(sft_workspace_path "config_test.py")" || return 1

  # Standalone ruff config: no [tool.ruff] wrapper (that is pyproject.toml only)
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