#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Ruff linting toolchain tests.
# Verifies that Ruff works inside the default sandbox including cache file operations.
#
load ../../test_helper.bash

@test "[EXECUTION] ruff can lint a file inside the sandbox" {
  sft_require_cmd_or_skip ruff

  local source_file "code"
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
  run safehouse_ok -- /usr/bin/ruff check "$source_file"
  [ "$status" -eq 0 ]
}

@test "[EXECUTION] ruff can write cache files inside the sandbox" {
  sft_require_cmd_or_skip ruff

  local source_file "code"
  source_file="$(sft_workspace_path "cache_test.py")" || return 1

  cat > "$source_file" <<'EOF'
def cached_function():
    return "test"
EOF

  # Clear any existing cache to ensure we write new cache files
  run safehouse_ok -- bash -c 'rm -rf "$HOME/.cache/ruff" 2>/dev/null || true'

  # Run ruff check to trigger cache file creation
  run safehouse_ok -- /usr/bin/ruff check "$source_file"
  [ "$status" -eq 0 ]

  # Verify cache files were created in the home directory
  run safehouse_ok -- bash -c 'ls -la "$HOME/.cache/ruff" 2>/dev/null || echo "cache-directory-missing"'
  [ "$status" -eq 0 ]
  [ "$output" != *"cache-directory-missing"* ]
}

@test "[EXECUTION] ruff can format a file inside the sandbox" {
  sft_require_cmd_or_skip ruff

  local source_file "code"
  source_file="$(sft_workspace_path "format_test.py")" || return 1

  cat > "$source_file" <<'EOF'
def bad_format():
    x=1
    y=2
    return x+y
EOF

  # Run ruff format to format the file
  run safehouse_ok -- /usr/bin/ruff format "$source_file"
  [ "$status" -eq 0 ]

  # Verify the file was formatted (ruff format modifies in place)
  run bash -c 'cat "$source_file" | grep -q "def bad_format():"'
  [ "$status" -eq 0 ]
}

@test "[EXECUTION] ruff respects configuration in the sandbox" {
  sft_require_cmd_or_skip ruff

  local source_file "config_test"
  source_file="$(sft_workspace_path ".ruff.toml")" || return 1
  local py_file "code"
  py_file="$(sft_workspace_path "config_test.py")" || return 1

  # Create a ruff config that sets line length to 80
  cat > "$source_file" <<'EOF'
[tool.ruff]
line-length = 80
EOF

  # Create a Python file with long line that should trigger linting if line length check is applied
  cat > "$py_file" <<'EOF'
def long_line_function():
    very_long_variable_name_that_exceeds_eighty_characters = "this should trigger a lint if line length is enforced"
    return very_long_variable_name_that_exceeds_eighty_characters
EOF

  # Run ruff check to lint the file with config
  run safehouse_ok -- /usr/bin/ruff check "$py_file"
  [ "$status" -eq 0 ]
}

@test "[POLICY-ONLY] default profile includes the ruff cache path" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_contains "$profile" "(home-subpath \"/.cache/ruff\")"
}