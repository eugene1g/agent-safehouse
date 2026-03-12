#!/usr/bin/env bash

run_section_policy_behavior() {
  local policy_all_agents
  local policy_clipboard
  local policy_agent_browser policy_browser_native_messaging policy_cloud_credentials policy_onepassword
  local policy_chromium_headless policy_chromium_full
  local policy_ssh policy_spotlight policy_cleanshot policy_process_control policy_lldb policy_xcode
  local policy_docker_wide_read policy_docker_workdir_root policy_docker_append_allow
  local append_docker_allow append_docker_allow_marker
  local policy_override_same_literal policy_override_subpath_literal policy_override_wide_read
  local append_override_same_literal append_override_subpath_literal append_override_wide_read
  local override_test_dir override_literal_file override_subpath_dir override_subpath_allowed_file override_subpath_blocked_file override_wide_read_file

  section_begin "Feature Toggles"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Docker integration profile marker" ";; Integration: Docker"
  assert_policy_contains "$POLICY_DOCKER" "--enable=docker includes docker socket grants" "/var/run/docker.sock"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits kubectl integration profile marker" ";; Integration: kubectl"
  assert_policy_contains "$POLICY_KUBECTL" "--enable=kubectl includes kubectl integration profile marker" "#safehouse-test-id:kubectl-integration#"
  assert_policy_contains "$POLICY_KUBECTL" "--enable=kubectl includes kubeconfig path grants" "/.kube/config"
  assert_policy_contains "$POLICY_KUBECTL" "--enable=kubectl includes krew path grants" "/.krew"
  assert_policy_contains "$POLICY_DEFAULT" "default policy emits container runtime socket deny marker" "#safehouse-test-id:container-runtime-socket-deny#"
  assert_policy_contains "$POLICY_DOCKER" "--enable=docker still includes container runtime socket deny marker from core profile" "#safehouse-test-id:container-runtime-socket-deny#"
  assert_policy_order_literal "$POLICY_DOCKER" "docker optional integration is emitted after core container runtime deny profile" "#safehouse-test-id:container-runtime-socket-deny#" ";; Integration: Docker"
  assert_policy_contains "$POLICY_DEFAULT" "default policy container deny block includes OrbStack home socket path" "/.orbstack/run/docker.sock"
  assert_policy_contains "$POLICY_DEFAULT" "default policy container deny block includes Podman runtime socket path" "/var/run/podman/podman.sock"
  assert_policy_contains "$POLICY_DEFAULT" "default policy container deny block includes Colima socket regex" "/\\\\.colima/[^/]+/docker\\\\.sock$"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits chromium-headless integration marker" "#safehouse-test-id:chromium-headless-integration#"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits chromium-full integration marker" "#safehouse-test-id:chromium-full-integration#"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits agent-browser state grant" "/.agent-browser"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits agent-browser Chromium mach rendezvous grant" "MachPortRendezvousServer"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits browser native messaging grants" "/NativeMessagingHosts"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Firefox native messaging grants" "/Mozilla/NativeMessagingHosts"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits extensions read grants" "/Default/Extensions"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes global gitignore variants in core git profile" "(home-prefix \"/.gitignore\")"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits broad ~/.local read grant" "(home-subpath \"/.local\")"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes scoped ~/.local pipx grant" "/.local/pipx"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes scoped uv binary grant" "/.local/bin/uv"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes shared Claude agents directory grant" "/.claude/agents"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes shared Claude skills directory grant" "/.claude/skills"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes shared CLAUDE.md read grant" "/CLAUDE.md"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits aider-specific grants when no command is provided" "/.local/bin/aider-install"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits openCode-specific grants when no command is provided" "/.local/share/opentui"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes scoped pnpm XDG config grant" "/.config/pnpm"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes runtime manager proto grant" "/.proto"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes runtime manager pkgx grant" "/.pkgx"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Azure CLI grant" "/.azure"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Azure Developer CLI grant" "/.azd"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits regex 1Password socket-file grant" "Group Containers/[A-Za-z0-9]+\\\\.com\\\\.1password/t/agent\\\\.sock$"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits regex 1Password desktop settings-dir grant" "Group Containers/[A-Za-z0-9]+\\\\.com\\\\.1password/Library/Application Support/1Password/Data/settings(/.*)?$"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits 1Password mach-lookup regex grant" "com\\.1password(\\..*)?$"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits SSH integration profile" ";; Integration: SSH"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes SSH config metadata grant for git-over-ssh" "/.ssh/config"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes SSH known_hosts metadata grant for git-over-ssh" "/.ssh/known_hosts"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Spotlight integration profile" ";; Integration: Spotlight"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits CleanShot integration profile" ";; Integration: CleanShot"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits clipboard pasteboard access" "(global-name \"com.apple.pasteboard.1\")"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes Apple Toolchain Core profile marker" "#safehouse-test-id:apple-toolchain-core#"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes Apple git shim target" "/Library/Developer/CommandLineTools/usr/bin/git"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes Apple git-core helpers" "/Library/Developer/CommandLineTools/usr/libexec/git-core"
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes Apple SDK data path grant" "/Library/Developer/CommandLineTools/SDKs"
  assert_policy_not_contains "$POLICY_DEFAULT" "default Apple toolchain core omits lldb binary" "/Library/Developer/CommandLineTools/usr/bin/lldb"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits process control integration profile" ";; Integration: Process Control"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits LLDB integration profile" ";; Integration: LLDB"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy omits Xcode integration profile" ";; Integration: Xcode"
  assert_policy_not_contains "$POLICY_DEFAULT" "default policy no longer grants broad file-read* access to /private/var/run" "Resolver/daemon sockets and pid files used by networking flows."
  assert_policy_contains "$POLICY_DEFAULT" "default policy includes metadata-only /private/var/run grant" "Metadata traversal for /private/var/run socket namespace."

  policy_agent_browser="${TEST_CWD}/policy-feature-agent-browser.sb"
  policy_browser_native_messaging="${TEST_CWD}/policy-feature-browser-native-messaging.sb"
  policy_cloud_credentials="${TEST_CWD}/policy-feature-cloud-credentials.sb"
  policy_onepassword="${TEST_CWD}/policy-feature-1password.sb"
  policy_chromium_headless="${TEST_CWD}/policy-feature-chromium-headless.sb"
  policy_chromium_full="${TEST_CWD}/policy-feature-chromium-full.sb"
  policy_ssh="${TEST_CWD}/policy-feature-ssh.sb"
  policy_spotlight="${TEST_CWD}/policy-feature-spotlight.sb"
  policy_cleanshot="${TEST_CWD}/policy-feature-cleanshot.sb"
  policy_clipboard="${TEST_CWD}/policy-feature-clipboard.sb"
  policy_process_control="${TEST_CWD}/policy-feature-process-control.sb"
  policy_lldb="${TEST_CWD}/policy-feature-lldb.sb"
  policy_xcode="${TEST_CWD}/policy-feature-xcode.sb"

  assert_command_succeeds "--enable=chromium-headless includes Chromium Headless profile" "$GENERATOR" --output "$policy_chromium_headless" --enable=chromium-headless
  assert_command_succeeds "--enable=chromium-full includes Chromium Full profile" "$GENERATOR" --output "$policy_chromium_full" --enable=chromium-full
  assert_command_succeeds "--enable=agent-browser includes agent-browser profile" "$GENERATOR" --output "$policy_agent_browser" --enable=agent-browser
  assert_command_succeeds "--enable=browser-native-messaging includes browser native messaging profile" "$GENERATOR" --output "$policy_browser_native_messaging" --enable=browser-native-messaging
  assert_command_succeeds "--enable=cloud-credentials includes cloud credentials profile" "$GENERATOR" --output "$policy_cloud_credentials" --enable=cloud-credentials
  assert_command_succeeds "--enable=1password includes 1Password profile" "$GENERATOR" --output "$policy_onepassword" --enable=1password
  assert_command_succeeds "--enable=ssh includes SSH profile" "$GENERATOR" --output "$policy_ssh" --enable=ssh
  assert_command_succeeds "--enable=spotlight includes Spotlight profile" "$GENERATOR" --output "$policy_spotlight" --enable=spotlight
  assert_command_succeeds "--enable=cleanshot includes CleanShot profile" "$GENERATOR" --output "$policy_cleanshot" --enable=cleanshot
  assert_command_succeeds "--enable=clipboard includes Clipboard profile" "$GENERATOR" --output "$policy_clipboard" --enable=clipboard
  assert_command_succeeds "--enable=process-control includes Process Control profile" "$GENERATOR" --output "$policy_process_control" --enable=process-control
  assert_command_succeeds "--enable=lldb includes LLDB profile" "$GENERATOR" --output "$policy_lldb" --enable=lldb
  assert_command_succeeds "--enable=xcode includes Xcode profile" "$GENERATOR" --output "$policy_xcode" --enable=xcode

  assert_policy_contains "$policy_chromium_headless" "--enable=chromium-headless includes Chromium Headless profile marker" "#safehouse-test-id:chromium-headless-integration#"
  assert_policy_contains "$policy_chromium_headless" "--enable=chromium-headless includes Chromium mach rendezvous marker" "#safehouse-test-id:chromium-headless-rendezvous#"
  assert_policy_contains "$policy_chromium_headless" "--enable=chromium-headless includes Chromium crashpad marker" "#safehouse-test-id:chromium-headless-crashpad#"
  assert_policy_contains "$policy_chromium_headless" "--enable=chromium-headless includes browser launch mach grant" "(global-name \"com.apple.windowserver.active\")"
  assert_policy_contains "$policy_chromium_headless" "--enable=chromium-headless includes GPU user-client grant" "(iokit-user-client-class \"IOSurfaceRootUserClient\")"
  assert_policy_not_contains "$policy_chromium_headless" "--enable=chromium-headless does not include agent-browser state grant" "(home-subpath \"/.agent-browser\")"
  assert_policy_not_contains "$policy_chromium_headless" "--enable=chromium-headless does not inject shell-init integration" "#safehouse-test-id:shell-init-integration#"

  assert_policy_contains "$policy_chromium_full" "--enable=chromium-full includes Chromium Full profile marker" "#safehouse-test-id:chromium-full-integration#"
  assert_policy_contains "$policy_chromium_full" "--enable=chromium-full includes Chromium Full rendezvous marker" "#safehouse-test-id:chromium-full-rendezvous#"
  assert_policy_contains "$policy_chromium_full" "--enable=chromium-full includes Chrome for Testing prefs grant" "/Library/Preferences/com.google.chrome.for.testing.plist"
  assert_policy_contains "$policy_chromium_full" "--enable=chromium-full includes Chrome DevToolsActivePort grant" "/Library/Application Support/Google/Chrome/DevToolsActivePort"
  assert_policy_contains "$policy_chromium_full" "--enable=chromium-full includes Chrome Crashpad grant" "/Library/Application Support/Google/Chrome for Testing/Crashpad"
  assert_policy_contains "$policy_chromium_full" "--enable=chromium-full includes pasteboard lookup grant" "(global-name \"com.apple.pasteboard.1\")"
  assert_policy_contains "$policy_chromium_full" "--enable=chromium-full includes OpenDirectory lookup grant" "(global-name \"com.apple.system.opendirectoryd.api\")"
  assert_policy_contains "$policy_chromium_full" "--enable=chromium-full includes token-client lookup grant" "(global-name \"com.apple.ctkd.token-client\")"
  assert_policy_contains "$policy_chromium_full" "--enable=chromium-full implicitly injects Chromium Headless integration" "#safehouse-test-id:chromium-headless-integration#"
  assert_policy_contains "$policy_chromium_full" "--enable=chromium-full preamble reports Chromium Headless as implicitly injected" "Optional integrations implicitly injected: chromium-headless"
  assert_policy_not_contains "$policy_chromium_full" "--enable=chromium-full does not include agent-browser state grant" "(home-subpath \"/.agent-browser\")"

  assert_policy_contains "$policy_agent_browser" "--enable=agent-browser includes Agent Browser profile marker" "#safehouse-test-id:agent-browser-integration#"
  assert_policy_contains "$policy_agent_browser" "--enable=agent-browser includes agent-browser state grant" "(home-subpath \"/.agent-browser\")"
  assert_policy_contains "$policy_agent_browser" "--enable=agent-browser includes Chromium mach rendezvous grant" "MachPortRendezvousServer"
  assert_policy_contains "$policy_agent_browser" "--enable=agent-browser includes browser launch mach grant" "(global-name \"com.apple.windowserver.active\")"
  assert_policy_contains "$policy_agent_browser" "--enable=agent-browser implicitly injects Chromium Headless integration" "#safehouse-test-id:chromium-headless-integration#"
  assert_policy_contains "$policy_agent_browser" "--enable=agent-browser preamble reports Chromium Headless as implicitly injected" "Optional integrations implicitly injected: chromium-headless"
  assert_policy_not_contains "$policy_agent_browser" "--enable=agent-browser does not inject electron integration" "#safehouse-test-id:electron-integration#"
  assert_policy_not_contains "$policy_agent_browser" "--enable=agent-browser does not inject macOS GUI integration" ";; Integration: macOS GUI"
  assert_policy_not_contains "$policy_agent_browser" "--enable=agent-browser no longer injects shell-init integration" "#safehouse-test-id:shell-init-integration#"

  assert_policy_contains "$policy_browser_native_messaging" "--enable=browser-native-messaging includes browser native messaging grants" "/NativeMessagingHosts"
  assert_policy_contains "$policy_browser_native_messaging" "--enable=browser-native-messaging includes Firefox native messaging grants" "/Mozilla/NativeMessagingHosts"
  assert_policy_contains "$policy_browser_native_messaging" "--enable=browser-native-messaging includes extensions read grants" "/Default/Extensions"
  assert_policy_contains "$policy_browser_native_messaging" "--enable=browser-native-messaging includes Browser Native Messaging profile marker" ";; Integration: Browser Native Messaging"

  assert_policy_contains "$policy_cloud_credentials" "--enable=cloud-credentials includes Azure CLI grant" "/.azure"
  assert_policy_contains "$policy_cloud_credentials" "--enable=cloud-credentials includes Azure Developer CLI grant" "/.azd"
  assert_policy_contains "$policy_cloud_credentials" "--enable=cloud-credentials includes Cloud Credentials profile marker" ";; Integration: Cloud Credentials"

  assert_policy_contains "$policy_onepassword" "--enable=1password includes regex 1Password socket-file grant" "Group Containers/[A-Za-z0-9]+\\\\.com\\\\.1password/t/agent\\\\.sock$"
  assert_policy_contains "$policy_onepassword" "--enable=1password includes regex 1Password desktop settings-dir grant" "Group Containers/[A-Za-z0-9]+\\\\.com\\\\.1password/Library/Application Support/1Password/Data/settings(/.*)?$"
  assert_policy_contains "$policy_onepassword" "--enable=1password includes 1Password mach-lookup regex grant" "com\\.1password(\\..*)?$"
  assert_policy_contains "$policy_onepassword" "--enable=1password includes 1Password profile marker" ";; Integration: 1Password"

  assert_policy_contains "$policy_ssh" "--enable=ssh includes SSH profile marker" ";; Integration: SSH"
  assert_policy_contains "$policy_ssh" "--enable=ssh includes SSH known_hosts grant" "/.ssh/known_hosts"

  assert_policy_contains "$policy_spotlight" "--enable=spotlight includes Spotlight profile marker" ";; Integration: Spotlight"
  assert_policy_contains "$policy_spotlight" "--enable=spotlight includes Spotlight mach-lookup grant" "(global-name \"com.apple.metadata.mds\")"

  assert_policy_contains "$policy_cleanshot" "--enable=cleanshot includes CleanShot profile marker" ";; Integration: CleanShot"
  assert_policy_contains "$policy_cleanshot" "--enable=cleanshot includes CleanShot media grant" "/Library/Application Support/CleanShot/media"
  assert_policy_contains "$policy_clipboard" "--enable=clipboard includes pasteboard service grant" "(global-name \"com.apple.pasteboard.1\")"
  assert_policy_contains "$policy_process_control" "--enable=process-control includes Process Control profile marker" ";; Integration: Process Control"
  assert_policy_contains "$policy_process_control" "--enable=process-control includes sysmond mach lookup grant" "(global-name \"com.apple.sysmond\")"
  assert_policy_contains "$policy_process_control" "--enable=process-control includes broad signal grant" "(allow signal)"
  assert_policy_not_contains "$policy_process_control" "--enable=process-control does not include debugger task-port grant" "(allow mach-priv-task-port)"
  assert_policy_not_contains "$policy_process_control" "--enable=process-control does not include debugger pidinfo grant" "Host process status/introspection used by debugger inspection flows."
  assert_policy_contains "$policy_lldb" "--enable=lldb includes LLDB profile marker" ";; Integration: LLDB"
  assert_policy_contains "$policy_lldb" "--enable=lldb includes developer tools path grant" "/Library/Developer/CommandLineTools"
  assert_policy_contains "$policy_lldb" "--enable=lldb includes lldb init file grant" "(home-prefix \"/.lldbinit\")"
  assert_policy_contains "$policy_lldb" "--enable=lldb includes process pidinfo grant" "(allow process-info-pidinfo)"
  assert_policy_contains "$policy_lldb" "--enable=lldb includes process setcontrol grant" "(allow process-info-setcontrol)"
  assert_policy_contains "$policy_lldb" "--enable=lldb includes task-port grant" "(allow mach-priv-task-port)"
  assert_policy_contains "$policy_lldb" "--enable=lldb implicitly injects process-control integration" "Optional integrations implicitly injected: process-control"
  assert_policy_contains "$policy_lldb" "--enable=lldb includes Process Control profile via dependency" ";; Integration: Process Control"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes Xcode profile marker" ";; Integration: Xcode"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes developer-root read marker" "#safehouse-test-id:xcode-developer-ro#"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes user state marker" "#safehouse-test-id:xcode-user-state#"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes Xcode app bundle grant" "/Applications/Xcode.app"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes versioned Xcode app regex grant" "(regex #\"^/Applications/Xcode[^/]*\\.app(/.*)?$\")"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes Data-backed versioned Xcode app regex grant" "(regex #\"^/System/Volumes/Data/Applications/Xcode[^/]*\\.app(/.*)?$\")"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes full CLT tree grant" "/Library/Developer/CommandLineTools"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes CoreSimulator shared runtime grant" "/Library/Developer/CoreSimulator"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes Xcode user state grant" "(home-subpath \"/Library/Developer/Xcode\")"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes CoreSimulator user state grant" "(home-subpath \"/Library/Developer/CoreSimulator\")"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes Xcode preferences domain grant" "(preference-domain \"com.apple.dt.Xcode\")"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes CoreSimulator service lookup" "(global-name \"com.apple.CoreSimulator.CoreSimulatorService\")"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes remoted coredevice lookup" "(global-name \"com.apple.remoted.coredevice\")"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes CoreDevice remote pairing lookup" "(global-name \"com.apple.CoreDevice.remotepairingd\")"
  assert_policy_contains "$policy_xcode" "--enable=xcode includes CoreDevice manager regex lookup" "(global-name-regex #\"^com\\.apple\\.coredevice\\.devicemanager(\\.|$)\")"
  assert_policy_not_contains "$policy_xcode" "--enable=xcode does not include debugger task-port grant" "(allow mach-priv-task-port)"
  assert_policy_not_contains "$policy_xcode" "--enable=xcode does not include LLDB integration marker" ";; Integration: LLDB"
  assert_policy_not_contains "$policy_xcode" "--enable=xcode does not include Process Control integration marker" ";; Integration: Process Control"

  policy_all_agents="${TEST_CWD}/policy-all-agents-feature-toggle.sb"
  assert_command_succeeds "--enable=all-agents restores legacy agent-specific grants in policy mode" "$GENERATOR" --output "$policy_all_agents" --enable=all-agents
  assert_policy_contains "$policy_all_agents" "all-agents policy includes aider-install binary grant" "/.local/bin/aider-install"
  assert_policy_contains "$policy_all_agents" "all-agents policy includes opentui data grant" "/.local/share/opentui"
  assert_policy_contains "$policy_all_agents" "all-agents policy includes goose config grant" "/.config/goose"
  assert_policy_contains "$policy_all_agents" "all-agents policy includes kilocode binary grant" "/.local/bin/kilocode"
  rm -f "$policy_all_agents" "$policy_clipboard" "$policy_process_control" "$policy_lldb" "$policy_xcode" "$policy_chromium_headless" "$policy_chromium_full"

  for docker_sock in \
    "/var/run/docker.sock" \
    "/private/var/run/docker.sock" \
    "${HOME}/.docker/run/docker.sock" \
    "${HOME}/.orbstack/run/docker.sock" \
    "${HOME}/.rd/docker.sock" \
    "${HOME}/.colima/docker.sock" \
    "${HOME}/.colima/default/docker.sock"; do
    assert_denied_if_exists "$POLICY_DEFAULT" "docker socket access denied by default (${docker_sock})" "$docker_sock" /bin/ls "$docker_sock"
    assert_allowed_if_exists "$POLICY_DOCKER" "docker socket access allowed with --enable=docker (${docker_sock})" "$docker_sock" /bin/ls "$docker_sock"
  done

  for podman_sock in \
    "/var/run/podman/podman.sock" \
    "/private/var/run/podman/podman.sock" \
    "${HOME}/.local/share/containers/podman/machine/podman.sock" \
    "${HOME}/.local/share/containers/podman/machine/default/podman.sock" \
    "${HOME}/.config/containers/podman/machine/podman.sock" \
    "${HOME}/.config/containers/podman/machine/default/podman.sock"; do
    assert_denied_if_exists "$POLICY_DEFAULT" "podman socket access denied by default (${podman_sock})" "$podman_sock" /bin/ls "$podman_sock"
  done

  for kubectl_path in \
    "${HOME}/.kube" \
    "${HOME}/.kube/config" \
    "${HOME}/.kube/cache" \
    "${HOME}/.kube/kuberc" \
    "${HOME}/.krew"; do
    assert_denied_if_exists "$POLICY_DEFAULT" "kubectl path access denied by default (${kubectl_path})" "$kubectl_path" /bin/ls "$kubectl_path"
    assert_allowed_if_exists "$POLICY_KUBECTL" "kubectl path access allowed with --enable=kubectl (${kubectl_path})" "$kubectl_path" /bin/ls "$kubectl_path"
  done

  append_docker_allow_marker="#safehouse-test-id:append-docker-allow#"
  policy_docker_wide_read="${TEST_CWD}/policy-docker-wide-read.sb"
  policy_docker_workdir_root="${TEST_CWD}/policy-docker-workdir-root.sb"
  policy_docker_append_allow="${TEST_CWD}/policy-docker-append-allow.sb"
  append_docker_allow="${TEST_CWD}/append-docker-allow.sb"

  assert_command_succeeds "generator emits --enable=wide-read policy for container socket deny checks" "$GENERATOR" --output "$policy_docker_wide_read" --enable=wide-read
  assert_command_succeeds "generator emits --workdir=/ policy for container socket deny checks" "$GENERATOR" --output "$policy_docker_workdir_root" --workdir /

  cat > "$append_docker_allow" <<EOF
;; ${append_docker_allow_marker}
(allow file-read* file-write*
    (literal "/var/run/docker.sock")
    (literal "/private/var/run/docker.sock")
    (home-literal "/.orbstack/run/docker.sock")
)
EOF
  assert_command_succeeds "generator emits append-profile policy that intentionally re-opens docker sockets" "$GENERATOR" --output "$policy_docker_append_allow" --append-profile "$append_docker_allow"
  assert_policy_order_literal "$policy_docker_append_allow" "container runtime socket deny block is emitted before appended profile rules" "#safehouse-test-id:container-runtime-socket-deny#" "$append_docker_allow_marker"

  for docker_sock in \
    "/var/run/docker.sock" \
    "/private/var/run/docker.sock" \
    "${HOME}/.orbstack/run/docker.sock"; do
    assert_allowed_if_exists "$policy_docker_wide_read" "core container runtime deny can be overridden by --enable=wide-read (${docker_sock})" "$docker_sock" /bin/ls "$docker_sock"
    assert_allowed_if_exists "$policy_docker_workdir_root" "core container runtime deny can be overridden by broad --workdir=/ grant (${docker_sock})" "$docker_sock" /bin/ls "$docker_sock"
    assert_allowed_if_exists "$policy_docker_append_allow" "docker socket can be intentionally re-opened via --append-profile (${docker_sock})" "$docker_sock" /bin/ls "$docker_sock"
  done

  for ext_dir in \
    "${HOME}/Library/Application Support/Google/Chrome/Default/Extensions" \
    "${HOME}/Library/Application Support/BraveSoftware/Brave-Browser/Default/Extensions" \
    "${HOME}/Library/Application Support/Arc/User Data/Default/Extensions" \
    "${HOME}/Library/Application Support/Microsoft Edge/Default/Extensions"; do
    browser_name="$(echo "$ext_dir" | sed "s|.*/Application Support/||;s|/.*||")"
    assert_denied_if_exists "$POLICY_DEFAULT" "browser extensions denied by default (${browser_name})" "$ext_dir" /bin/ls "$ext_dir"
    assert_allowed_if_exists "$policy_browser_native_messaging" "browser extensions allowed with --enable=browser-native-messaging (${browser_name})" "$ext_dir" /bin/ls "$ext_dir"
  done

  assert_denied_if_exists "$POLICY_DEFAULT" "agent-browser state dir denied by default" "${HOME}/.agent-browser" /bin/ls "${HOME}/.agent-browser"
  assert_allowed_if_exists "$policy_agent_browser" "agent-browser state dir allowed with --enable=agent-browser" "${HOME}/.agent-browser" /bin/ls "${HOME}/.agent-browser"
  rm -f "$policy_agent_browser"

  for cloud_dir in "${HOME}/.azure" "${HOME}/.azd"; do
    assert_denied_if_exists "$POLICY_DEFAULT" "cloud credential directory denied by default (${cloud_dir})" "$cloud_dir" /bin/ls "$cloud_dir"
    assert_allowed_if_exists "$policy_cloud_credentials" "cloud credential directory allowed with --enable=cloud-credentials (${cloud_dir})" "$cloud_dir" /bin/ls "$cloud_dir"
  done

  section_begin "Security Invariants"
  assert_allowed_if_exists "$POLICY_DEFAULT" "osascript execution allowed by default policy" "/usr/bin/osascript" /usr/bin/osascript -e 'return 1'

  for sensitive_path in \
    "${HOME}/Library/Application Support/Google/Chrome/Default/Cookies" \
    "${HOME}/Library/Application Support/Google/Chrome/Default/Login Data" \
    "${HOME}/Library/Application Support/BraveSoftware/Brave-Browser/Default/Cookies" \
    "${HOME}/Library/Application Support/BraveSoftware/Brave-Browser/Default/Login Data" \
    "${HOME}/Library/Application Support/Arc/User Data/Default/Cookies" \
    "${HOME}/Library/Application Support/Arc/User Data/Default/Login Data" \
    "${HOME}/Library/Application Support/Microsoft Edge/Default/Cookies" \
    "${HOME}/Library/Application Support/Microsoft Edge/Default/Login Data"; do
    browser_name="$(echo "$sensitive_path" | sed "s|.*/Application Support/||;s|/.*||")"
    assert_denied_if_exists "$POLICY_DEFAULT" "read browser sensitive file denied (${browser_name})" "$sensitive_path" /bin/cat "$sensitive_path"
  done

  section_begin "Grant Merge/Precedence"
  assert_allowed_strict "$POLICY_MERGE" "read from repeated --add-dirs-ro colon-list path" /bin/cat "${TEST_RO_DIR_2}/readable2.txt"
  assert_denied_strict "$POLICY_MERGE" "write denied for read-only merged path" /usr/bin/touch "${TEST_RO_DIR_2}/should-fail.txt"
  assert_allowed_strict "$POLICY_MERGE" "write allowed for read/write merged path" /usr/bin/touch "${TEST_RW_DIR_2}/should-succeed.txt"
  assert_allowed_strict "$POLICY_MERGE" "write allowed for path with spaces" /usr/bin/touch "${TEST_SPACE_DIR}/space-write-ok.txt"
  assert_allowed_strict "$POLICY_MERGE" "read/write wins when path is in both --add-dirs-ro and --add-dirs" /usr/bin/touch "${TEST_OVERLAP_DIR}/overlap-write-ok.txt"
  assert_allowed_strict "$POLICY_MERGE" "read allowed for read-only file grant" /bin/cat "$TEST_RO_FILE"
  assert_denied_strict "$POLICY_MERGE" "write denied for read-only file grant" /bin/sh -c "echo denied >> '$TEST_RO_FILE'"
  assert_allowed_strict "$POLICY_MERGE" "read allowed for read/write file grant" /bin/cat "$TEST_RW_FILE"
  assert_allowed_strict "$POLICY_MERGE" "write allowed for read/write file grant" /bin/sh -c "echo allowed >> '$TEST_RW_FILE'"

  section_begin "Rule Override Semantics"
  override_test_dir="${TEST_DENIED_DIR}/override-semantics"
  override_literal_file="${override_test_dir}/override-same-literal.txt"
  override_subpath_dir="${override_test_dir}/override-subpath"
  override_subpath_allowed_file="${override_subpath_dir}/allowed.txt"
  override_subpath_blocked_file="${override_subpath_dir}/blocked.txt"
  override_wide_read_file="${override_test_dir}/override-wide-read.txt"
  policy_override_same_literal="${TEST_CWD}/policy-override-same-literal.sb"
  policy_override_subpath_literal="${TEST_CWD}/policy-override-subpath-literal.sb"
  policy_override_wide_read="${TEST_CWD}/policy-override-wide-read.sb"
  append_override_same_literal="${TEST_CWD}/append-override-same-literal.sb"
  append_override_subpath_literal="${TEST_CWD}/append-override-subpath-literal.sb"
  append_override_wide_read="${TEST_CWD}/append-override-wide-read.sb"

  mkdir -p "$override_subpath_dir"
  printf 'override-same-literal\n' > "$override_literal_file"
  printf 'override-subpath-allowed\n' > "$override_subpath_allowed_file"
  printf 'override-subpath-blocked\n' > "$override_subpath_blocked_file"
  printf 'override-wide-read\n' > "$override_wide_read_file"

  cat > "$append_override_same_literal" <<EOF
(deny file-read* (literal "${override_literal_file}"))
(allow file-read* (literal "${override_literal_file}"))
EOF
  assert_command_succeeds "generator emits deny-then-allow literal override test policy" "$GENERATOR" --workdir="" --output "$policy_override_same_literal" --append-profile "$append_override_same_literal"
  assert_denied_strict "$policy_override_same_literal" "deny then allow on the same literal path remains denied on current macOS" /bin/cat "$override_literal_file"

  cat > "$append_override_subpath_literal" <<EOF
(deny file-read* (subpath "${override_subpath_dir}"))
(allow file-read* (literal "${override_subpath_allowed_file}"))
EOF
  assert_command_succeeds "generator emits deny-subpath-plus-allow-literal override test policy" "$GENERATOR" --workdir="" --output "$policy_override_subpath_literal" --append-profile "$append_override_subpath_literal"
  assert_denied_strict "$policy_override_subpath_literal" "deny subpath plus later allow literal still leaves the specific file denied on current macOS" /bin/cat "$override_subpath_allowed_file"
  assert_denied_strict "$policy_override_subpath_literal" "deny subpath still blocks sibling files not explicitly re-allowed" /bin/cat "$override_subpath_blocked_file"

  cat > "$append_override_wide_read" <<EOF
(deny file-read* (literal "${override_wide_read_file}"))
(allow file-read* (subpath "/"))
EOF
  assert_command_succeeds "generator emits deny-then-wide-read override test policy" "$GENERATOR" --workdir="" --output "$policy_override_wide_read" --append-profile "$append_override_wide_read"
  assert_allowed_strict "$policy_override_wide_read" "later broad allow (subpath /) re-opens an earlier literal deny" /bin/cat "$override_wide_read_file"

  rm -f "$policy_browser_native_messaging" "$policy_cloud_credentials" "$policy_onepassword" "$policy_ssh" "$policy_spotlight" "$policy_cleanshot"
  rm -f "$policy_docker_wide_read" "$policy_docker_workdir_root" "$policy_docker_append_allow" "$append_docker_allow"
  rm -f "$policy_override_same_literal" "$policy_override_subpath_literal" "$policy_override_wide_read"
  rm -f "$append_override_same_literal" "$append_override_subpath_literal" "$append_override_wide_read"
  rm -rf "$override_test_dir"
}

register_section run_section_policy_behavior
