# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# Purpose: Runtime compatibility shims for wrapped commands that need adjusted editor/app launch paths.
# Reads globals: policy_req_home_dir, policy_req_invoked_command_profile_basename, runtime_execution_environment.
# Writes globals: runtime_execution_environment and filesystem shim artifacts under the caller HOME.
# Called by: commands/execute.sh.
# Notes: Keep compatibility-specific hacks isolated here so environment building stays generic.
#
# Claude Code + VS Code under Safehouse needs a special editor wrapper:
# - The wrapper is intentionally opt-in behind --enable=vscode. Most Claude runs
#   do not need desktop VS Code access, so this integration should not activate
#   just because the wrapped command is Claude.
# - On Ctrl+G, Claude invokes $EDITOR directly and passes only the temp prompt file path.
# - If $EDITOR points at `code`, VS Code's macOS CLI takes the `open -n -a ...` path.
# - Under Safehouse, that fresh-instance LaunchServices handoff can open/focus VS Code
#   without actually opening the temp prompt file.
# - If we bypass `code` and exec the app binary directly, Electron then tries to
#   initialize its own inner Chromium sandbox, which fails inside Safehouse unless
#   `--no-sandbox` is set.
# - Launching the GUI app binary directly also inherits Claude's controlling TTY
#   by default. Without detaching stdio, VS Code startup logs bleed into the Claude
#   terminal and can interfere with the otherwise clean "Save and close editor"
#   prompt flow.
# - Claude does not add `-w`, so the wrapper must add it or the edit handoff loses
#   the expected "wait until the editor closes" behavior.
#
# The shim below therefore does three things together:
# 1. bypasses the `code` -> `open -n` path,
# 2. disables Electron's nested sandbox with `--no-sandbox`,
# 3. preserves Claude's wait semantics with `-w`,
# 4. detaches stdio so GUI startup noise does not spill back into the TUI.

runtime_claude_editor_shim_relative_path=".cache/claude/safehouse-claude-vscode-editor.sh"
runtime_claude_editor_shim_profile_key="profiles/55-integrations-optional/vscode.sb"

runtime_env_array_has_key() {
  local array_name="$1"
  local key="$2"
  local entry idx array_length

  safehouse_require_collection_name "$array_name" || return 1

  eval "array_length=\${#${array_name}[@]}"
  for ((idx = 0; idx < array_length; idx++)); do
    eval "entry=\${${array_name}[${idx}]}"
    if [[ "${entry%%=*}" == "$key" ]]; then
      return 0
    fi
  done

  return 1
}

runtime_env_array_value_for_key() {
  local array_name="$1"
  local key="$2"
  local entry idx array_length

  safehouse_require_collection_name "$array_name" || return 1

  eval "array_length=\${#${array_name}[@]}"
  for ((idx = 0; idx < array_length; idx++)); do
    eval "entry=\${${array_name}[${idx}]}"
    if [[ "${entry%%=*}" == "$key" ]]; then
      printf '%s\n' "${entry#*=}"
      return 0
    fi
  done

  return 1
}

runtime_claude_editor_shim_path() {
  printf '%s/%s\n' "${policy_req_home_dir%/}" "${runtime_claude_editor_shim_relative_path}"
}

runtime_claude_editor_shim_supported() {
  [[ -x "/Applications/Visual Studio Code.app/Contents/MacOS/Code" ]] && return 0
  [[ -x "/Applications/Visual Studio Code - Insiders.app/Contents/MacOS/Code - Insiders" ]] && return 0
  return 1
}

runtime_command_is_claude_code() {
  local command_basename=""

  command_basename="$(safehouse_to_lowercase "${policy_req_invoked_command_profile_basename:-}")"
  case "$command_basename" in
    claude|claude-code)
      return 0
      ;;
  esac

  return 1
}

runtime_claude_editor_shim_enabled() {
  runtime_command_is_claude_code || return 1
  policy_plan_optional_profile_selected "$runtime_claude_editor_shim_profile_key"
}

runtime_apply_claude_editor_shim_environment() {
  local target_name="$1"
  local shim_path=""

  runtime_claude_editor_shim_enabled || return 0
  runtime_claude_editor_shim_supported || return 0

  if runtime_env_array_has_key "$target_name" "EDITOR"; then
    return 0
  fi
  if runtime_env_array_has_key "$target_name" "VISUAL"; then
    return 0
  fi

  shim_path="$(runtime_claude_editor_shim_path)"
  safehouse_env_array_upsert_entries "$target_name" \
    "EDITOR=${shim_path}" \
    "VISUAL=${shim_path}"
}

runtime_prepare_claude_editor_shim() {
  local shim_path="$1"
  local shim_dir="" tmp_path=""

  shim_dir="$(dirname "$shim_path")"
  if ! mkdir -p "$shim_dir"; then
    safehouse_fail "Failed to create Claude editor shim directory: ${shim_dir}"
    return 1
  fi

  tmp_path="$(mktemp "${shim_path}.XXXXXX")" || {
    safehouse_fail "Failed to create temporary Claude editor shim: ${shim_path}"
    return 1
  }

  cat >"$tmp_path" <<'EOF'
#!/bin/sh
# Claude passes only the temp prompt file path here.
# We intentionally launch the app binary directly instead of `/usr/local/bin/code`
# because the macOS `code` wrapper routes through `open -n -a ...`, which can fail
# to hand the prompt file over to VS Code under Safehouse.
#
# `--no-sandbox` is required because Electron/Chromium tries to initialize its own
# nested sandbox; that inner sandbox is incompatible with Safehouse's outer Seatbelt
# sandbox and fails with "Operation not permitted" without this flag.
#
# The direct app binary also inherits Claude's TTY by default. Capture stdout/stderr
# and disconnect stdin so VS Code startup logs do not bleed into the terminal UI.
stdout_path="$(mktemp /tmp/safehouse-vscode-stdout.XXXXXX)"
stderr_path="$(mktemp /tmp/safehouse-vscode-stderr.XXXXXX)"
cleanup() {
  rm -f "$stdout_path" "$stderr_path"
}
trap cleanup EXIT INT TERM

# `-w` is required because Claude expects the editor command to block until editing
# is done, but Claude itself does not pass a wait flag.
run_code() {
  "$@" </dev/null >"$stdout_path" 2>"$stderr_path"
}

if [ -x '/Applications/Visual Studio Code.app/Contents/MacOS/Code' ]; then
  if run_code '/Applications/Visual Studio Code.app/Contents/MacOS/Code' --no-sandbox -w "$@"; then
    exit 0
  fi
  status=$?
  [ ! -s "$stdout_path" ] || cat "$stdout_path" >&2
  [ ! -s "$stderr_path" ] || cat "$stderr_path" >&2
  exit "$status"
fi

if [ -x '/Applications/Visual Studio Code - Insiders.app/Contents/MacOS/Code - Insiders' ]; then
  if run_code '/Applications/Visual Studio Code - Insiders.app/Contents/MacOS/Code - Insiders' --no-sandbox -w "$@"; then
    exit 0
  fi
  status=$?
  [ ! -s "$stdout_path" ] || cat "$stdout_path" >&2
  [ ! -s "$stderr_path" ] || cat "$stderr_path" >&2
  exit "$status"
fi

printf '%s\n' 'safehouse: no supported VS Code app binary found for Claude editor shim.' >&2
exit 1
EOF

  if ! chmod 0755 "$tmp_path"; then
    rm -f "$tmp_path"
    safehouse_fail "Failed to mark Claude editor shim executable: ${tmp_path}"
    return 1
  fi

  if ! mv -f "$tmp_path" "$shim_path"; then
    rm -f "$tmp_path"
    safehouse_fail "Failed to install Claude editor shim: ${shim_path}"
    return 1
  fi
}

runtime_prepare_exec_compat_shims() {
  local shim_path=""
  local editor_value="" visual_value=""

  runtime_claude_editor_shim_enabled || return 0
  runtime_claude_editor_shim_supported || return 0

  shim_path="$(runtime_claude_editor_shim_path)"
  editor_value="$(runtime_env_array_value_for_key runtime_execution_environment "EDITOR" || true)"
  visual_value="$(runtime_env_array_value_for_key runtime_execution_environment "VISUAL" || true)"
  if [[ "$editor_value" == "$shim_path" && "$visual_value" == "$shim_path" ]]; then
    runtime_prepare_claude_editor_shim "$shim_path" || return 1
  fi
}
