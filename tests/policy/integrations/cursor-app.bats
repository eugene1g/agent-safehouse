#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=all-apps includes the Cursor Desktop app profile and grants ~/.cursor without the CLI profile" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  sft_assert_includes_source "$profile" "65-apps/cursor-app.sb"
  # ~/.cursor is opened by the desktop app; the app profile grants it directly
  # because app selection intentionally does not pull in 60-agents/cursor-agent.sb.
  sft_assert_omits_source "$profile" "60-agents/cursor-agent.sb"
  sft_assert_contains "$profile" '(home-subpath "/.cursor")'
  sft_assert_contains "$profile" '(home-subpath "/Library/Application Support/Cursor")'
}

@test "[POLICY-ONLY] enable=all-apps grants Cursor Desktop MachPortRendezvousServer lookup and register, including the team-ID-prefixed form" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  sft_assert_contains "$profile" '(allow mach-lookup
    (global-name-regex #"^(VDXQ22DGB9\.)?com\.todesktop\.230313mzl4w4u92\.MachPortRendezvousServer\.")
)'
  sft_assert_contains "$profile" '(allow mach-register
    (global-name-regex #"^(VDXQ22DGB9\.)?com\.todesktop\.230313mzl4w4u92\.MachPortRendezvousServer\.")
)'
}

@test "[POLICY-ONLY] enable=all-apps grants the listen side of the Cursor CLI IPC socket" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  # Cursor inherits VS Code IPC naming; bind/accept on its own
  # vscode-ipc-<uuid>.sock is safe because it hands no capability out of
  # the sandbox.
  sft_assert_contains "$profile" '(allow network-bind network-inbound'
  sft_assert_contains "$profile" '(local unix-socket'
  sft_assert_contains "$profile" '(path-regex #"^(/private)?/var/folders/[^/]+/[^/]+/T/vscode-ipc-[0-9A-Fa-f-]+\.sock$")'
}

@test "[POLICY-ONLY] enable=all-apps explicitly denies the connect side of the Cursor CLI IPC socket" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  # Connecting out to this socket can drive an out-of-sandbox editor
  # (openExternal / directory-open with workspace-trust behavior), so outbound
  # connect is denied explicitly rather than left to the default deny.
  sft_assert_contains "$profile" '(deny network-outbound'
  sft_assert_contains "$profile" '(path-regex #"^(/private)?/var/folders/[^/]+/[^/]+/T/vscode-ipc-[0-9A-Fa-f-]+\.sock$")'
}

@test "[POLICY-ONLY] enable=all-apps denies both directions of the Cursor git IPC socket" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  # The git IPC socket (VSCODE_GIT_IPC_HANDLE) is a credential conduit whose
  # path does not identify the owning editor, so it cannot be scoped to a trust
  # domain. Both connect and listen are denied.
  sft_assert_contains "$profile" '(deny network-outbound
    (remote unix-socket
        (path-regex #"^(/private)?/var/folders/[^/]+/[^/]+/T/vscode-git-[0-9a-f]+\.sock$")))'
  sft_assert_contains "$profile" '(deny network-bind network-inbound
    (local unix-socket
        (path-regex #"^(/private)?/var/folders/[^/]+/[^/]+/T/vscode-git-[0-9a-f]+\.sock$")))'
}

@test "[POLICY-ONLY] enable=all-apps allows bind of Cursor single-instance socket and denies outbound connect" {
  local profile

  profile="$(safehouse_profile --enable=all-apps)"

  sft_assert_contains "$profile" '(allow network-bind network-inbound
    (local unix-socket
        (path-regex (string-append "^" HOME_DIR "/Library/Application Support/Cursor/[0-9.]+-main\\.sock$"))))'
  sft_assert_contains "$profile" '(deny network-outbound
    (remote unix-socket
        (path-regex (string-append "^" HOME_DIR "/Library/Application Support/Cursor/[0-9.]+-main\\.sock$"))))'
}
