#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

# ------------------------------------------------------------------------------
# Policy-Only

@test "[POLICY-ONLY] copilot-cli grants the VS Code Copilot CLI launcher shim directory" {
  local profile copilot_section

  profile="$(safehouse_profile -- copilot)"
  copilot_section="$(sft_profile_source_section "$profile" "60-agents/copilot-cli.sb")"

  sft_assert_contains "$copilot_section" \
    "(home-subpath \"/Library/Application Support/Code/User/globalStorage/github.copilot-chat/copilotCli\")"
  sft_assert_contains "$copilot_section" \
    "(home-subpath \"/Library/Application Support/Code - Insiders/User/globalStorage/github.copilot-chat/copilotCli\")"
}

@test "[POLICY-ONLY] copilot-cli grants only the VS Code Frameworks dir, not the whole app bundle" {
  local profile copilot_section

  profile="$(safehouse_profile -- copilot)"
  copilot_section="$(sft_profile_source_section "$profile" "60-agents/copilot-cli.sb")"

  # ELECTRON_RUN_AS_NODE only needs the helper binary and Electron Framework.
  sft_assert_contains "$copilot_section" \
    '(subpath "/Applications/Visual Studio Code.app/Contents/Frameworks")'
  sft_assert_contains "$copilot_section" \
    '(subpath "/Applications/Visual Studio Code - Insiders.app/Contents/Frameworks")'

  sft_assert_not_contains "$copilot_section" '(subpath "/Applications/Visual Studio Code.app")'
  sft_assert_not_contains "$copilot_section" '(subpath "/Applications/Visual Studio Code - Insiders.app")'
  sft_assert_not_contains "$copilot_section" '(subpath "/Applications")'
}

@test "[POLICY-ONLY] copilot-cli keeps the VS Code shim grants read-only" {
  local profile copilot_section write_block

  profile="$(safehouse_profile -- copilot)"
  copilot_section="$(sft_profile_source_section "$profile" "60-agents/copilot-cli.sb")"

  # The single file-write* block in this profile must stay scoped to Copilot's
  # own state; nothing under VS Code or /Applications may be writable.
  write_block="$(printf '%s\n' "$copilot_section" | awk '
    /^\(allow file-read\* file-write\*/ { inblock = 1 }
    inblock { print }
    inblock && /^\)/ { inblock = 0 }
  ')"

  sft_assert_not_contains "$write_block" "/Applications"
  sft_assert_not_contains "$write_block" "globalStorage"
}

@test "[POLICY-ONLY] copilot-cli allows ancestor traversal to the shim without granting the parents" {
  local profile copilot_section

  profile="$(safehouse_profile -- copilot)"
  copilot_section="$(sft_profile_source_section "$profile" "60-agents/copilot-cli.sb")"

  # Node's realpathSync lstats every ancestor of the shim entrypoint.
  sft_assert_contains "$copilot_section" '(home-literal "/Library/Application Support")'
  sft_assert_contains "$copilot_section" '(home-literal "/Library/Application Support/Code")'
  sft_assert_contains "$copilot_section" '(home-literal "/Library/Application Support/Code/User")'
  sft_assert_contains "$copilot_section" \
    '(home-literal "/Library/Application Support/Code/User/globalStorage")'

  # Traversal only: the surrounding VS Code user data must not be readable.
  sft_assert_not_contains "$copilot_section" '(home-subpath "/Library/Application Support/Code")'
  sft_assert_not_contains "$copilot_section" \
    '(home-subpath "/Library/Application Support/Code/User/globalStorage")'
}

@test "[POLICY-ONLY] copilot-cli does not pull in the VS Code app or Electron integrations" {
  local profile

  profile="$(safehouse_profile -- copilot)"

  # The shim runs the helper as plain Node, so no GUI/Electron surface is needed.
  sft_assert_omits_source "$profile" "65-apps/vscode-app.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/electron.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/macos-gui.sb"
}

# ------------------------------------------------------------------------------
# Execution
#
# The VS Code shim lives under HOME, so the home-side grants are exercised
# hermetically against the per-test fake HOME. A launcher named `copilot` is
# used so the agent profile is actually selected (command basename match).

sft_copilot_launcher() {
  local launcher="${HOME}/.local/bin/copilot"

  mkdir -p "$(dirname "$launcher")" || return 1
  printf '#!/bin/sh\nexec "$@"\n' > "$launcher" || return 1
  chmod 755 "$launcher" || return 1

  printf '%s\n' "$launcher"
}

sft_copilot_shim_dir() {
  local shim_dir="${HOME}/Library/Application Support/Code/User/globalStorage/github.copilot-chat/copilotCli"

  mkdir -p "$shim_dir" || return 1
  printf '%s\n' "$shim_dir"
}

@test "[EXECUTION] copilot-cli can read the VS Code launcher shim under HOME" {
  local launcher shim_dir

  launcher="$(sft_copilot_launcher)"
  shim_dir="$(sft_copilot_shim_dir)"
  printf '#!/bin/sh\n' > "${shim_dir}/copilot"

  safehouse_ok -- "$launcher" cat "${shim_dir}/copilot"
}

@test "[EXECUTION] copilot-cli cannot read VS Code user data beside the shim" {
  local launcher shim_dir global_storage

  launcher="$(sft_copilot_launcher)"
  shim_dir="$(sft_copilot_shim_dir)"
  global_storage="$(dirname "$(dirname "$shim_dir")")"

  printf 'secret\n' > "${global_storage}/state.vscdb"
  printf 'secret\n' > "$(dirname "$shim_dir")/copilotUserPreferences.md"

  # Traversal to the shim must not expose the surrounding VS Code profile.
  safehouse_denied -- "$launcher" cat "${global_storage}/state.vscdb"
  safehouse_denied -- "$launcher" cat "$(dirname "$shim_dir")/copilotUserPreferences.md"
}

@test "[EXECUTION] copilot-cli cannot write into the VS Code launcher shim directory" {
  local launcher shim_dir

  launcher="$(sft_copilot_launcher)"
  shim_dir="$(sft_copilot_shim_dir)"

  # The shim is executed, never modified; a writable shim would let a
  # sandboxed agent alter what later runs outside the sandbox.
  safehouse_denied -- "$launcher" touch "${shim_dir}/injected"
  sft_assert_path_absent "${shim_dir}/injected"
}

@test "[EXECUTION] copilot-cli reads the VS Code Electron runtime but not the rest of the bundle" {
  local launcher app="/Applications/Visual Studio Code.app"

  [ -d "$app" ] || skip "VS Code is not installed"

  launcher="$(sft_copilot_launcher)"

  safehouse_ok -- "$launcher" test -r "${app}/Contents/Frameworks/Electron Framework.framework/Electron Framework"
  safehouse_denied -- "$launcher" cat "${app}/Contents/Info.plist"
  safehouse_denied -- "$launcher" ls "${app}/Contents/Resources"
}

# ------------------------------------------------------------------------------
