# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154

# Purpose: Runtime compatibility shims for wrapped commands that need adjusted editor/app launch paths.
# Reads globals: policy_req_home_dir, policy_req_invoked_command_profile_basename, runtime_execution_environment.
# Writes globals: runtime_execution_environment and filesystem shim artifacts under the caller HOME.
# Called by: commands/execute.sh.
# Notes: Keep compatibility-specific hacks isolated here so environment building stays generic.
#
# Claude Code + VS Code under Safehouse needs a special editor wrapper:
# - The full cold-start path is intentionally opt-in behind --enable=vscode.
#   Most Claude runs do not need desktop VS Code access, so Safehouse should not
#   grant the broader VS Code integration surface by default.
# - There is a narrower default case worth supporting: if an unsandboxed VS Code
#   instance is already running, Claude can hand the temp prompt file to that
#   existing app through Launch Services without the broader VS Code app profile.
# - That reuse path needs to be injected eagerly when Claude starts, even if
#   VS Code is not running yet. Otherwise a user who launches VS Code later in
#   the same Claude session still cannot use Ctrl+G, because Claude would never
#   have received the editor wrapper in its environment.
# - That narrower reuse path still needs a tiny policy carve-out: Launch Services
#   must be able to read metadata for `/Applications` and the VS Code app bundles
#   so `open -b ...` can resolve the already-installed handler.
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
# - Claude does not add `-w`, so the wrapper must supply its own blocking editor
#   behavior. In reuse mode that is a file-change wait heuristic, and in full
#   cold-start mode it is the same heuristic after launching VS Code detached.
#
# The shim below therefore supports two modes:
# 1. `reuse`: hand the file to an already-running VS Code instance via
#    `lsappinfo` + `open -b`. This mode cannot cold-start VS Code, so its shim
#    filename is intentionally descriptive: if Claude shows "<shim> exited with
#    code 1", the filename itself tells the user what to do next.
# 2. `full`: fall back to direct app-binary launch, disable Electron's nested
#    sandbox with `--no-sandbox`, launch VS Code detached, and keep the shim
#    blocked by watching the temp prompt file until the edit stabilizes.
#    The cold-start path also uses an isolated VS Code user-data/extensions root
#    so the temporary Claude prompt editor does not inherit the user's normal
#    VS Code settings, extensions, or recently-opened state.

runtime_claude_editor_reuse_shim_relative_path=".cache/claude/safehouse-vscode-reuse-needs-running-vscode.sh"
runtime_claude_editor_full_shim_relative_path=".cache/claude/safehouse-claude-vscode-editor.sh"
runtime_claude_editor_shim_profile_key="profiles/55-integrations-optional/vscode.sb"
runtime_claude_editor_shim_mode_env_key="SAFEHOUSE_CLAUDE_VSCODE_MODE"
runtime_claude_editor_vscode_bundle_id="com.microsoft.VSCode"
runtime_claude_editor_vscode_insiders_bundle_id="com.microsoft.VSCodeInsiders"

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

runtime_claude_editor_shim_relative_path_for_mode() {
  local shim_mode="$1"

  case "$shim_mode" in
    reuse)
      printf '%s\n' "$runtime_claude_editor_reuse_shim_relative_path"
      ;;
    full)
      printf '%s\n' "$runtime_claude_editor_full_shim_relative_path"
      ;;
    *)
      return 1
      ;;
  esac
}

runtime_claude_editor_shim_path_for_mode() {
  local shim_mode="$1"
  local shim_relative_path=""

  shim_relative_path="$(runtime_claude_editor_shim_relative_path_for_mode "$shim_mode")" || return 1
  printf '%s/%s\n' "${policy_req_home_dir%/}" "${shim_relative_path}"
}

runtime_claude_editor_shim_full_supported() {
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

runtime_claude_editor_shim_mode() {
  if runtime_claude_editor_shim_enabled; then
    if runtime_claude_editor_shim_full_supported; then
      printf 'full\n'
      return 0
    fi
  fi

  runtime_command_is_claude_code || return 1
  printf 'reuse\n'
}

runtime_apply_claude_editor_shim_environment() {
  local target_name="$1"
  local shim_path=""
  local shim_mode=""

  shim_mode="$(runtime_claude_editor_shim_mode || true)"
  [[ -n "$shim_mode" ]] || return 0

  if runtime_env_array_has_key "$target_name" "EDITOR"; then
    return 0
  fi
  if runtime_env_array_has_key "$target_name" "VISUAL"; then
    return 0
  fi

  shim_path="$(runtime_claude_editor_shim_path_for_mode "$shim_mode")" || return 1
  safehouse_env_array_upsert_entries "$target_name" \
    "EDITOR=${shim_path}" \
    "VISUAL=${shim_path}" \
    "${runtime_claude_editor_shim_mode_env_key}=${shim_mode}"
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
mode="${SAFEHOUSE_CLAUDE_VSCODE_MODE:-reuse}"

# In reuse mode, only hand the file to an already-running unsandboxed VS Code.
# `lsappinfo` is sufficient to detect whether a running stable/insiders instance
# exists, and it avoids the broad process/file scan that `lsof` triggers under
# Seatbelt.
running_vscode_bundle_id() {
  lsappinfo_output="$(/usr/bin/lsappinfo list 2>/dev/null || true)"

  case "$lsappinfo_output" in
    *'bundleID="com.microsoft.VSCodeInsiders"'*)
      printf '%s\n' 'com.microsoft.VSCodeInsiders'
      return 0
      ;;
    *'bundleID="com.microsoft.VSCode"'*)
      printf '%s\n' 'com.microsoft.VSCode'
      return 0
      ;;
  esac

  return 1
}

# Reuse mode cannot rely on VS Code's native `-w` / wait-marker flow without the
# broader app integration surface. Instead, block until the prompt file content
# changes and then settles for a short quiet period. That approximates the
# common Claude flow of "edit prompt, save, then continue" without the noisy
# `lsof` scans that were probing unrelated GUI app state.
editor_file_signature() {
  file_path="$1"
  [ -r "$file_path" ] || return 1
  /usr/bin/cksum < "$file_path" | awk '{print $1 ":" $2}'
}

wait_for_editor_file_change() {
  file_path="$1"
  baseline_signature="$2"
  attempts="${3:-18000}"
  current_signature=""
  changed_signature=""
  stable_polls=0

  while [ "$attempts" -gt 0 ]; do
    current_signature="$(editor_file_signature "$file_path" || true)"

    if [ -n "$changed_signature" ]; then
      if [ "$current_signature" = "$changed_signature" ]; then
        stable_polls=$((stable_polls + 1))
        if [ "$stable_polls" -ge 3 ]; then
          return 0
        fi
      else
        changed_signature="$current_signature"
        stable_polls=0
      fi
    elif [ -n "$current_signature" ] && [ "$current_signature" != "$baseline_signature" ]; then
      changed_signature="$current_signature"
      stable_polls=0
    fi

    sleep 0.2
    attempts=$((attempts - 1))
  done

  return 1
}

reuse_running_vscode() {
  file_path="$1"
  bundle_id="$(running_vscode_bundle_id)" || return 1
  baseline_signature="$(editor_file_signature "$file_path" || true)"

  /usr/bin/open -b "$bundle_id" "$file_path" >/dev/null 2>&1 || return 1
  wait_for_editor_file_change "$file_path" "$baseline_signature"
}

prepare_full_mode_profile_dirs() {
  app_variant="$1"

  # The explicit cold-start path should not load the user's normal VS Code
  # profile. Keep the temporary Claude prompt editor in its own Safehouse-owned
  # state root so startup does not pick up user settings, extensions, or recent
  # workspace history.
  case "$app_variant" in
    stable)
      profile_root="${HOME}/.cache/claude/vscode-editor-stable"
      ;;
    insiders)
      profile_root="${HOME}/.cache/claude/vscode-editor-insiders"
      ;;
    *)
      return 1
      ;;
  esac

  full_user_data_dir="${profile_root}/user-data"
  full_extensions_dir="${profile_root}/extensions"
  full_settings_dir="${full_user_data_dir}/User"
  full_settings_path="${full_settings_dir}/settings.json"

  mkdir -p "$full_settings_dir" "$full_extensions_dir" || return 1
  cat >"$full_settings_path" <<'SETTINGS'
{
  "window.restoreWindows": "none",
  "workbench.startupEditor": "none",
  "extensions.autoCheckUpdates": false,
  "extensions.autoUpdate": false,
  "update.mode": "none"
}
SETTINGS
}

# The direct app binary also inherits Claude's TTY by default. Capture stdout/stderr
# and disconnect stdin so VS Code startup logs do not bleed into the terminal UI.
stdout_path="$(mktemp /tmp/safehouse-vscode-stdout.XXXXXX)"
stderr_path="$(mktemp /tmp/safehouse-vscode-stderr.XXXXXX)"
cleanup() {
  rm -f "$stdout_path" "$stderr_path"
}
trap cleanup EXIT INT TERM

launch_code_detached() {
  nohup "$@" </dev/null >"$stdout_path" 2>"$stderr_path" &
  launched_code_pid="$!"
}

wait_for_editor_file_change_or_process_exit() {
  file_path="$1"
  baseline_signature="$2"
  child_pid="$3"
  attempts="${4:-18000}"
  current_signature=""
  changed_signature=""
  stable_polls=0

  while [ "$attempts" -gt 0 ]; do
    current_signature="$(editor_file_signature "$file_path" || true)"

    if [ -n "$changed_signature" ]; then
      if [ "$current_signature" = "$changed_signature" ]; then
        stable_polls=$((stable_polls + 1))
        if [ "$stable_polls" -ge 3 ]; then
          return 0
        fi
      else
        changed_signature="$current_signature"
        stable_polls=0
      fi
    elif [ -n "$current_signature" ] && [ "$current_signature" != "$baseline_signature" ]; then
      changed_signature="$current_signature"
      stable_polls=0
    fi

    if ! kill -0 "$child_pid" 2>/dev/null; then
      wait "$child_pid"
      return $?
    fi

    sleep 0.2
    attempts=$((attempts - 1))
  done

  return 1
}

if [ "$#" -ge 1 ] && reuse_running_vscode "$1"; then
  exit 0
fi

if [ "$mode" != "full" ]; then
  printf '%s\n' 'safehouse: VS Code is not already running; use --enable=vscode to allow cold-start editor handoff.' >&2
  exit 1
fi

if [ "$#" -lt 1 ]; then
  printf '%s\n' 'safehouse: Claude editor shim expected a prompt file path.' >&2
  exit 1
fi

baseline_signature="$(editor_file_signature "$1" || true)"

if [ -x '/Applications/Visual Studio Code.app/Contents/MacOS/Code' ]; then
  prepare_full_mode_profile_dirs stable || {
    printf '%s\n' 'safehouse: failed to prepare isolated VS Code profile for Claude editor handoff.' >&2
    exit 1
  }
  launch_code_detached '/Applications/Visual Studio Code.app/Contents/MacOS/Code' --no-sandbox --new-window --disable-extensions --disable-workspace-trust --skip-add-to-recently-opened --user-data-dir "$full_user_data_dir" --extensions-dir "$full_extensions_dir" "$@"
  if wait_for_editor_file_change_or_process_exit "$1" "$baseline_signature" "$launched_code_pid"; then
    exit 0
  fi
  status="$?"
  [ ! -s "$stdout_path" ] || cat "$stdout_path" >&2
  [ ! -s "$stderr_path" ] || cat "$stderr_path" >&2
  exit "$status"
fi

if [ -x '/Applications/Visual Studio Code - Insiders.app/Contents/MacOS/Code - Insiders' ]; then
  prepare_full_mode_profile_dirs insiders || {
    printf '%s\n' 'safehouse: failed to prepare isolated VS Code Insiders profile for Claude editor handoff.' >&2
    exit 1
  }
  launch_code_detached '/Applications/Visual Studio Code - Insiders.app/Contents/MacOS/Code - Insiders' --no-sandbox --new-window --disable-extensions --disable-workspace-trust --skip-add-to-recently-opened --user-data-dir "$full_user_data_dir" --extensions-dir "$full_extensions_dir" "$@"
  if wait_for_editor_file_change_or_process_exit "$1" "$baseline_signature" "$launched_code_pid"; then
    exit 0
  fi
  status="$?"
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
  local shim_mode=""

  shim_mode="$(runtime_env_array_value_for_key runtime_execution_environment "${runtime_claude_editor_shim_mode_env_key}" || true)"
  [[ -n "$shim_mode" ]] || return 0
  shim_path="$(runtime_claude_editor_shim_path_for_mode "$shim_mode")" || return 1
  editor_value="$(runtime_env_array_value_for_key runtime_execution_environment "EDITOR" || true)"
  visual_value="$(runtime_env_array_value_for_key runtime_execution_environment "VISUAL" || true)"
  if [[ -n "$shim_mode" && "$editor_value" == "$shim_path" && "$visual_value" == "$shim_path" ]]; then
    runtime_prepare_claude_editor_shim "$shim_path" || return 1
  fi
}
