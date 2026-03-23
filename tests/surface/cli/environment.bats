#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

create_env_printer_command() {
  local path="$1"

  cat >"$path" <<'EOF'
#!/bin/sh
printf 'EDITOR=%s\n' "${EDITOR:-}"
printf 'VISUAL=%s\n' "${VISUAL:-}"
printf 'SAFEHOUSE_CLAUDE_VSCODE_MODE=%s\n' "${SAFEHOUSE_CLAUDE_VSCODE_MODE:-}"
EOF
  chmod 755 "$path" || return 1
}

create_fake_lsappinfo_command() {
  local path="$1"
  local mode="$2"

  cat >"$path" <<EOF
#!/bin/sh
mode='${mode}'

if [ "\${1:-}" != "list" ]; then
  exit 1
fi

  case "\$mode" in
  running)
    cat <<'OUT'
86) "Code" ASN:0x0-0x4e64e6:
    bundleID="com.microsoft.VSCode"
    bundle path="/Applications/Visual Studio Code.app"
    pid = 70451 type="Foreground" flavor=3 Version="1.112.0"
    coalition: 4709  { 70451 70453 70454 70455 84531 }
OUT
    exit 0
    ;;
  insiders)
    cat <<'OUT'
86) "Code - Insiders" ASN:0x0-0x4e64e6:
    bundleID="com.microsoft.VSCodeInsiders"
    bundle path="/Applications/Visual Studio Code - Insiders.app"
    pid = 71451 type="Foreground" flavor=3 Version="1.112.0"
    coalition: 4719  { 71451 71453 71454 71455 71531 }
OUT
    exit 0
    ;;
  *)
    exit 0
    ;;
esac
EOF
  chmod 755 "$path" || return 1
}

create_editor_shim_env_file() {
  local path="$1"
  local fake_bin_dir="$2"

  cat >"$path" <<EOF
PATH=${fake_bin_dir}:/usr/bin:/bin:/usr/sbin:/sbin
EOF
}

claude_reuse_shim_path_for_home() {
  local normalized_home="$1"
  printf '%s\n' "${normalized_home}/.cache/claude/safehouse-vscode-reuse-needs-running-vscode.sh"
}

claude_full_shim_path_for_home() {
  local normalized_home="$1"
  printf '%s\n' "${normalized_home}/.cache/claude/safehouse-claude-vscode-editor.sh"
}

@test "[EXECUTION] default sanitized mode drops unrelated host vars while preserving core runtime env" {
  SAFEHOUSE_TEST_SECRET="safehouse-secret" \
  safehouse_ok -- /bin/sh -c '
    [ -z "${SAFEHOUSE_TEST_SECRET+x}" ] &&
    [ -n "${HOME:-}" ] &&
    [ -n "${PATH:-}" ] &&
    [ -n "${SHELL:-}" ] &&
    [ -n "${TMPDIR:-}" ]
  '
}

@test "[EXECUTION] default sanitized mode preserves allowlisted SDK and proxy/browser vars" {
  SAFEHOUSE_TEST_SECRET="safehouse-secret" \
  SDKROOT="/tmp/safehouse-sdkroot" \
  HTTP_PROXY="http://proxy.example:8080" \
  NO_BROWSER="true" \
  safehouse_ok -- /bin/sh -c '
    [ "${SDKROOT:-}" = "/tmp/safehouse-sdkroot" ] &&
    [ "${HTTP_PROXY:-}" = "http://proxy.example:8080" ] &&
    [ "${NO_BROWSER:-}" = "true" ]
  '
}

@test "[EXECUTION] default sanitized mode appends common Homebrew and user bin paths" { # issue #13
  PATH="/usr/bin:/bin:/usr/sbin:/sbin" \
  safehouse_ok -- /bin/sh -c '
    case ":${PATH:-}:" in
      *:/opt/homebrew/bin:*) ;;
      *) exit 1 ;;
    esac &&
    case ":${PATH:-}:" in
      *:/opt/homebrew/sbin:*) ;;
      *) exit 1 ;;
    esac &&
    case ":${PATH:-}:" in
      *:"${HOME}/.local/bin":*) ;;
      *) exit 1 ;;
    esac
  '
}

@test "[EXECUTION] --env passes through the caller environment" {
  SAFEHOUSE_TEST_SECRET="secret-value" safehouse_ok --env -- /bin/sh -c '[ "${SAFEHOUSE_TEST_SECRET:-}" = "secret-value" ]'
}

@test "[EXECUTION] leading NAME=VALUE tokens after -- set one-off child env vars" {
  SAFEHOUSE_TEST_SECRET="host-secret" \
    safehouse_ok -- SAFEHOUSE_TEST_SECRET="command-secret" /bin/sh -c '[ "${SAFEHOUSE_TEST_SECRET:-}" = "command-secret" ]'
}

@test "[EXECUTION] --env-pass passes only selected host variables" {
  SAFEHOUSE_TEST_PASS_ONE="pass-one" SAFEHOUSE_TEST_PASS_TWO="pass-two" \
    safehouse_ok --env-pass=SAFEHOUSE_TEST_PASS_ONE -- /bin/sh -c '
      [ "${SAFEHOUSE_TEST_PASS_ONE:-}" = "pass-one" ] &&
      [ -z "${SAFEHOUSE_TEST_PASS_TWO+x}" ]
    '
}

@test "[EXECUTION] SAFEHOUSE_ENV_PASS passes only selected host variables" {
  SAFEHOUSE_ENV_PASS="SAFEHOUSE_TEST_PASS_ONE" \
  SAFEHOUSE_TEST_PASS_ONE="pass-one" \
  SAFEHOUSE_TEST_PASS_TWO="pass-two" \
    safehouse_ok -- /bin/sh -c '
      [ "${SAFEHOUSE_TEST_PASS_ONE:-}" = "pass-one" ] &&
      [ -z "${SAFEHOUSE_TEST_PASS_TWO+x}" ]
    '
}

@test "--env and --env-pass cannot be combined" {
  safehouse_denied --env --env-pass=SAFEHOUSE_TEST_PASS_ONE -- /usr/bin/true
}

@test "[EXECUTION] --env=FILE loads file overrides over sanitized defaults" {
  local env_file
  env_file="$(sft_workspace_path "safehouse.env")"

  cat > "$env_file" <<'EOF'
SAFEHOUSE_TEST_SECRET=file-secret
PATH=/safehouse/env-path
HOME=/safehouse/env-home
EOF

  SAFEHOUSE_TEST_HOST_ONLY="host-only" \
    safehouse_ok --env="$env_file" -- /bin/sh -c '
      [ "${SAFEHOUSE_TEST_SECRET:-}" = "file-secret" ] &&
      [ "${PATH:-}" = "/safehouse/env-path" ] &&
      [ "${HOME:-}" = "/safehouse/env-home" ] &&
      [ -z "${SAFEHOUSE_TEST_HOST_ONLY+x}" ] &&
      [ -n "${SHELL:-}" ] &&
      [ -n "${TMPDIR:-}" ]
    '
}

@test "[EXECUTION] --env-pass can override a matching value loaded from --env=FILE" {
  local env_file
  env_file="$(sft_workspace_path "safehouse.env")"

  cat > "$env_file" <<'EOF'
SAFEHOUSE_TEST_SECRET=file-secret
PATH=/safehouse/env-path
HOME=/safehouse/env-home
EOF

  SAFEHOUSE_TEST_SECRET="host-secret" \
    safehouse_ok --env="$env_file" --env-pass=SAFEHOUSE_TEST_SECRET -- /bin/sh -c '
      [ "${SAFEHOUSE_TEST_SECRET:-}" = "host-secret" ] &&
      [ "${PATH:-}" = "/safehouse/env-path" ]
    '
}

@test "[EXECUTION] playwright-chrome injects its profile env default when the caller does not set it" {
  safehouse_ok --enable=playwright-chrome -- /bin/sh -c '[ "${PLAYWRIGHT_MCP_SANDBOX:-}" = "false" ]'
}

@test "[EXECUTION] caller-provided PLAYWRIGHT_MCP_SANDBOX overrides the playwright-chrome profile default" {
  PLAYWRIGHT_MCP_SANDBOX="true" \
    safehouse_ok --enable=playwright-chrome -- /bin/sh -c '[ "${PLAYWRIGHT_MCP_SANDBOX:-}" = "true" ]'
}

@test "[EXECUTION] claude injects a reuse-mode VS Code editor shim by default even when no running VS Code instance is detected yet" {
  local claude_bin="${SAFEHOUSE_WORKSPACE}/claude"
  local fake_bin_dir="${SAFEHOUSE_WORKSPACE}/fake-bin"
  local env_file
  local normalized_home=""
  local shim_path=""

  create_env_printer_command "$claude_bin"
  mkdir -p "$fake_bin_dir"
  create_fake_lsappinfo_command "${fake_bin_dir}/lsappinfo" "none"
  env_file="$(sft_workspace_path "shim-none.env")"
  create_editor_shim_env_file "$env_file" "$fake_bin_dir"
  normalized_home="$(cd "$HOME" && pwd -P)"
  shim_path="$(claude_reuse_shim_path_for_home "$normalized_home")"

  safehouse_run --env="$env_file" -- "./claude"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "EDITOR=${shim_path}"
  sft_assert_contains "$output" "VISUAL=${shim_path}"
  sft_assert_contains "$output" "SAFEHOUSE_CLAUDE_VSCODE_MODE=reuse"
  sft_assert_file_exists "$shim_path"
}

@test "[EXECUTION] claude injects a reuse-mode VS Code editor shim when a running VS Code instance is detected" {
  local claude_bin="${SAFEHOUSE_WORKSPACE}/claude"
  local fake_bin_dir="${SAFEHOUSE_WORKSPACE}/fake-bin"
  local env_file
  local normalized_home=""
  local shim_path=""

  create_env_printer_command "$claude_bin"
  mkdir -p "$fake_bin_dir"
  create_fake_lsappinfo_command "${fake_bin_dir}/lsappinfo" "running"
  env_file="$(sft_workspace_path "shim-running.env")"
  create_editor_shim_env_file "$env_file" "$fake_bin_dir"
  normalized_home="$(cd "$HOME" && pwd -P)"
  shim_path="$(claude_reuse_shim_path_for_home "$normalized_home")"

  safehouse_run --env="$env_file" -- "./claude"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "EDITOR=${shim_path}"
  sft_assert_contains "$output" "VISUAL=${shim_path}"
  sft_assert_contains "$output" "SAFEHOUSE_CLAUDE_VSCODE_MODE=reuse"
  sft_assert_file_exists "$shim_path"

  run /usr/bin/grep -F -- "running_vscode_bundle_id" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "/usr/bin/open -b \"\$bundle_id\" \"\$file_path\"" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "editor_file_signature" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "wait_for_editor_file_change \"\$file_path\" \"\$baseline_signature\"" "$shim_path"
  [ "$status" -eq 0 ]
}

@test "[EXECUTION] claude injects a full-mode VS Code editor shim when enable=vscode is set and EDITOR/VISUAL are unset" {
  local claude_bin="${SAFEHOUSE_WORKSPACE}/claude"
  local fake_bin_dir="${SAFEHOUSE_WORKSPACE}/fake-bin"
  local env_file
  local normalized_home=""
  local shim_path=""

  [[ -x "/Applications/Visual Studio Code.app/Contents/MacOS/Code" || -x "/Applications/Visual Studio Code - Insiders.app/Contents/MacOS/Code - Insiders" ]] ||
    skip "requires VS Code or VS Code Insiders"

  create_env_printer_command "$claude_bin"
  mkdir -p "$fake_bin_dir"
  create_fake_lsappinfo_command "${fake_bin_dir}/lsappinfo" "none"
  env_file="$(sft_workspace_path "shim-full.env")"
  create_editor_shim_env_file "$env_file" "$fake_bin_dir"
  normalized_home="$(cd "$HOME" && pwd -P)"
  shim_path="$(claude_full_shim_path_for_home "$normalized_home")"

  safehouse_run --env="$env_file" --enable=vscode -- "./claude"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "EDITOR=${shim_path}"
  sft_assert_contains "$output" "VISUAL=${shim_path}"
  sft_assert_contains "$output" "SAFEHOUSE_CLAUDE_VSCODE_MODE=full"
  sft_assert_file_exists "$shim_path"

  run /usr/bin/grep -F -- "--no-sandbox" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "--disable-extensions" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "--disable-workspace-trust" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "--user-data-dir \"\$full_user_data_dir\"" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "--extensions-dir \"\$full_extensions_dir\"" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "launch_code_detached" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "wait_for_editor_file_change_or_process_exit" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "\"window.restoreWindows\": \"none\"" "$shim_path"
  [ "$status" -eq 0 ]
  run /usr/bin/grep -F -- "prepare_full_mode_profile_dirs stable" "$shim_path"
  [ "$status" -eq 0 ]
}

@test "[EXECUTION] claude still injects the reuse-mode VS Code editor shim when only enable=all-apps is set" {
  local claude_bin="${SAFEHOUSE_WORKSPACE}/claude"
  local fake_bin_dir="${SAFEHOUSE_WORKSPACE}/fake-bin"
  local env_file
  local normalized_home=""
  local shim_path=""

  create_env_printer_command "$claude_bin"
  mkdir -p "$fake_bin_dir"
  create_fake_lsappinfo_command "${fake_bin_dir}/lsappinfo" "none"
  env_file="$(sft_workspace_path "shim-all-apps.env")"
  create_editor_shim_env_file "$env_file" "$fake_bin_dir"
  normalized_home="$(cd "$HOME" && pwd -P)"
  shim_path="$(claude_reuse_shim_path_for_home "$normalized_home")"

  safehouse_run --env="$env_file" --enable=all-apps -- "./claude"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "EDITOR=${shim_path}"
  sft_assert_contains "$output" "VISUAL=${shim_path}"
  sft_assert_contains "$output" "SAFEHOUSE_CLAUDE_VSCODE_MODE=reuse"
  sft_assert_file_exists "$shim_path"
}

@test "[EXECUTION] caller-provided EDITOR suppresses the claude editor shim" {
  local claude_bin="${SAFEHOUSE_WORKSPACE}/claude"
  local fake_bin_dir="${SAFEHOUSE_WORKSPACE}/fake-bin"
  local env_file
  local normalized_home=""
  local shim_path=""

  create_env_printer_command "$claude_bin"
  mkdir -p "$fake_bin_dir"
  create_fake_lsappinfo_command "${fake_bin_dir}/lsappinfo" "running"
  env_file="$(sft_workspace_path "shim-editor.env")"
  create_editor_shim_env_file "$env_file" "$fake_bin_dir"
  normalized_home="$(cd "$HOME" && pwd -P)"
  shim_path="$(claude_reuse_shim_path_for_home "$normalized_home")"

  safehouse_run_env EDITOR="/tmp/custom-editor" -- --env="$env_file" -- "./claude"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "EDITOR=/tmp/custom-editor"
  sft_assert_contains "$output" "VISUAL="
  sft_assert_contains "$output" "SAFEHOUSE_CLAUDE_VSCODE_MODE="
  [ ! -e "$shim_path" ]
}

@test "[EXECUTION] caller-provided VISUAL suppresses the claude editor shim" {
  local claude_bin="${SAFEHOUSE_WORKSPACE}/claude"
  local fake_bin_dir="${SAFEHOUSE_WORKSPACE}/fake-bin"
  local env_file
  local normalized_home=""
  local shim_path=""

  create_env_printer_command "$claude_bin"
  mkdir -p "$fake_bin_dir"
  create_fake_lsappinfo_command "${fake_bin_dir}/lsappinfo" "running"
  env_file="$(sft_workspace_path "shim-visual.env")"
  create_editor_shim_env_file "$env_file" "$fake_bin_dir"
  normalized_home="$(cd "$HOME" && pwd -P)"
  shim_path="$(claude_reuse_shim_path_for_home "$normalized_home")"

  safehouse_run_env VISUAL="/tmp/custom-visual" -- --env="$env_file" -- "./claude"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "EDITOR="
  sft_assert_contains "$output" "VISUAL=/tmp/custom-visual"
  sft_assert_contains "$output" "SAFEHOUSE_CLAUDE_VSCODE_MODE="
  [ ! -e "$shim_path" ]
}

@test "[EXECUTION] default sanitized mode proxies EDITOR and VISUAL through by default" {
  EDITOR="/tmp/custom-editor" \
    VISUAL="/tmp/custom-visual" \
    safehouse_ok -- /bin/sh -c '
      [ "${EDITOR:-}" = "/tmp/custom-editor" ] &&
      [ "${VISUAL:-}" = "/tmp/custom-visual" ]
    '
}

@test "[EXECUTION] non-claude commands do not receive the VS Code editor shim even when a running VS Code instance is detected" {
  local cmd_bin="${SAFEHOUSE_WORKSPACE}/not-claude"
  local fake_bin_dir="${SAFEHOUSE_WORKSPACE}/fake-bin"
  local env_file
  local normalized_home=""
  local shim_path=""

  create_env_printer_command "$cmd_bin"
  mkdir -p "$fake_bin_dir"
  create_fake_lsappinfo_command "${fake_bin_dir}/lsappinfo" "running"
  env_file="$(sft_workspace_path "shim-not-claude.env")"
  create_editor_shim_env_file "$env_file" "$fake_bin_dir"
  normalized_home="$(cd "$HOME" && pwd -P)"
  shim_path="$(claude_reuse_shim_path_for_home "$normalized_home")"

  safehouse_run --env="$env_file" -- "./not-claude"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "EDITOR="
  sft_assert_contains "$output" "VISUAL="
  sft_assert_contains "$output" "SAFEHOUSE_CLAUDE_VSCODE_MODE="
  [ ! -e "$shim_path" ]
}

@test "[EXECUTION] default sanitized mode sets APP_SANDBOX_CONTAINER_ID=agent-safehouse" {
  safehouse_ok -- /bin/sh -c '[ "${APP_SANDBOX_CONTAINER_ID:-}" = "agent-safehouse" ]'
}

@test "[EXECUTION] --env preserves caller-provided APP_SANDBOX_CONTAINER_ID" {
  APP_SANDBOX_CONTAINER_ID="caller-container" \
    safehouse_ok --env -- /bin/sh -c '[ "${APP_SANDBOX_CONTAINER_ID:-}" = "caller-container" ]'
}

@test "[EXECUTION] --env=FILE preserves file-provided APP_SANDBOX_CONTAINER_ID" {
  local env_file
  env_file="$(sft_workspace_path "safehouse.env")"

  cat > "$env_file" <<'EOF'
APP_SANDBOX_CONTAINER_ID=file-container
EOF

  safehouse_ok --env="$env_file" -- /bin/sh -c '[ "${APP_SANDBOX_CONTAINER_ID:-}" = "file-container" ]'
}

@test "[EXECUTION] --env-pass=APP_SANDBOX_CONTAINER_ID preserves host value" {
  APP_SANDBOX_CONTAINER_ID="host-container" \
    safehouse_ok --env-pass=APP_SANDBOX_CONTAINER_ID -- /bin/sh -c '[ "${APP_SANDBOX_CONTAINER_ID:-}" = "host-container" ]'
}
