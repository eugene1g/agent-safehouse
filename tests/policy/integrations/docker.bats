#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Container runtime socket deny regressions.
# Docker clients use connect() on unix domain sockets, classified as
# network-outbound by sandbox-exec, not file-read/write. Without explicit
# network-outbound deny rules the file-level deny was bypassed entirely.
#
load ../../test_helper.bash

@test "[POLICY-ONLY] default profile includes the core container runtime deny profile" { # https://github.com/eugene1g/agent-safehouse/issues/19
  local profile
  profile="$(safehouse_profile)"

  sft_assert_includes_source "$profile" "50-integrations-core/container-runtime-default-deny.sb"
}

@test "docker socket file access is denied at runtime" { # https://github.com/eugene1g/agent-safehouse/issues/19
  [ -e "/var/run/docker.sock" ] || skip "docker socket not present"

  safehouse_denied -- /bin/sh -c "cat /var/run/docker.sock >/dev/null 2>&1"
}

@test "[POLICY-ONLY] enable=docker includes the docker allow profile after the core deny profile" { # https://github.com/eugene1g/agent-safehouse/issues/19
  local profile
  profile="$(safehouse_profile --enable=docker)"

  sft_assert_includes_source "$profile" "50-integrations-core/container-runtime-default-deny.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/docker.sb"
  sft_assert_order "$profile" "$(sft_source_marker "50-integrations-core/container-runtime-default-deny.sb")" "$(sft_source_marker "55-integrations-optional/docker.sb")"
}

@test "[POLICY-ONLY] podman sockets are denied by default and not re-opened without enable=docker" { # https://github.com/eugene1g/agent-safehouse/issues/19
  local profile deny
  profile="$(safehouse_profile)"
  deny="$(sft_profile_source_section "$profile" "50-integrations-core/container-runtime-default-deny.sb")"

  # The core deny profile blocks connect() on the podman sockets — both the
  # system API sockets and the per-machine sockets under HOME.
  sft_assert_contains "$deny" "(remote unix-socket (path-literal \"/var/run/podman/podman.sock\"))"
  sft_assert_contains "$deny" "(remote unix-socket (path-literal \"/private/var/run/podman/podman.sock\"))"
  sft_assert_contains "$deny" "(remote unix-socket (path-regex (string-append \"^\" HOME_DIR \"/\\\\.local/share/containers/podman/machine/podman\\\\.sock\$\")))"
  sft_assert_contains "$deny" "(remote unix-socket (path-regex (string-append \"^\" HOME_DIR \"/\\\\.config/containers/podman/machine/podman\\\\.sock\$\")))"

  # Without enable=docker the optional profile is absent, so nothing re-opens them.
  sft_assert_omits_source "$profile" "55-integrations-optional/docker.sb"
}

@test "[POLICY-ONLY] enable=docker re-opens the podman sockets symmetrically with the deny block" { # https://github.com/eugene1g/agent-safehouse/issues/19
  local profile reopen
  profile="$(safehouse_profile --enable=docker)"

  # Assert the re-opens appear inside the optional docker.sb section specifically.
  # The core deny block contains identical socket strings, so a whole-profile
  # substring check would false-pass even if these allow rules were removed.
  reopen="$(sft_profile_source_section "$profile" "55-integrations-optional/docker.sb")"

  # File-level re-opens for the system podman API socket and machine state dirs.
  sft_assert_contains "$reopen" "(literal \"/var/run/podman/podman.sock\")"
  sft_assert_contains "$reopen" "(literal \"/private/var/run/podman/podman.sock\")"
  sft_assert_contains "$reopen" "(home-subpath \"/.local/share/containers\")"
  sft_assert_contains "$reopen" "(home-subpath \"/.config/containers\")"

  # network-outbound connect() re-opens — the block that actually unblocks the
  # client — mirroring the deny block's podman entries exactly.
  sft_assert_contains "$reopen" "(remote unix-socket (path-literal \"/var/run/podman/podman.sock\"))"
  sft_assert_contains "$reopen" "(remote unix-socket (path-literal \"/private/var/run/podman/podman.sock\"))"
  sft_assert_contains "$reopen" "(remote unix-socket (path-regex (string-append \"^\" HOME_DIR \"/\\\\.local/share/containers/podman/machine/podman\\\\.sock\$\")))"
  sft_assert_contains "$reopen" "(remote unix-socket (path-regex (string-append \"^\" HOME_DIR \"/\\\\.local/share/containers/podman/machine/[^/]+/podman\\\\.sock\$\")))"
  sft_assert_contains "$reopen" "(remote unix-socket (path-regex (string-append \"^\" HOME_DIR \"/\\\\.config/containers/podman/machine/podman\\\\.sock\$\")))"
  sft_assert_contains "$reopen" "(remote unix-socket (path-regex (string-append \"^\" HOME_DIR \"/\\\\.config/containers/podman/machine/[^/]+/podman\\\\.sock\$\")))"

  # The re-opens must come after the core deny so allow wins (later rules win).
  sft_assert_order "$profile" "$(sft_source_marker "50-integrations-core/container-runtime-default-deny.sb")" "$(sft_source_marker "55-integrations-optional/docker.sb")"
}

@test "[POLICY-ONLY] enable=docker grants read access to Docker.app bundle" { # https://github.com/eugene1g/agent-safehouse/issues/117
  local profile
  profile="$(safehouse_profile --enable=docker)"

  sft_assert_contains "$profile" "(subpath \"/Applications/Docker.app\")"
  sft_assert_contains "$profile" "/Applications/Docker.app"
}

@test "[POLICY-ONLY] enable=docker grants the credential helper its state dir and SecurityServer, without the keychain profile" { # https://github.com/eugene1g/agent-safehouse/issues/158
  local profile grants
  profile="$(safehouse_profile --enable=docker)"
  grants="$(sft_profile_source_section "$profile" "55-integrations-optional/docker.sb")"

  # docker-credential-desktop aborts during startup unless it can create its own
  # state directory, and returns an error rather than "credentials not found"
  # unless it can reach SecurityServer. Both are needed for an anonymous pull.
  sft_assert_contains "$grants" "(home-literal \"/Library/Containers\")"
  sft_assert_contains "$grants" "(home-subpath \"/Library/Containers/com.docker.docker\")"
  sft_assert_contains "$grants" "(global-name \"com.apple.SecurityServer\")"

  # Anonymous pulls need none of the keychain profile's privileges — notably
  # write access to ~/Library/Keychains and the interactive auth-prompt services.
  sft_assert_omits_source "$profile" "55-integrations-optional/keychain.sb"
  sft_assert_not_contains "$profile" "(home-subpath \"/Library/Keychains\")"
}

@test "[EXECUTION] docker credential helper reports 'not found' rather than erroring when enable=docker is set" { # https://github.com/eugene1g/agent-safehouse/issues/158
  local helper_bin

  helper_bin="$(sft_command_path_or_skip docker-credential-desktop)" || return 1

  HOME="$SAFEHOUSE_HOST_HOME" "$helper_bin" list >/dev/null 2>&1 ||
    skip "docker-credential-desktop precheck failed outside sandbox"

  # An anonymous pull of a public image still invokes the helper when
  # ~/.docker/config.json sets a credsStore. The CLI treats a non-zero exit with
  # no "credentials not found" message as a hard error and abandons the pull, so
  # the helper starting successfully is what makes such a pull work at all.
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok --enable=docker -- \
    "$helper_bin" list
  [ "$status" -eq 0 ]

  # Without the integration the helper cannot start at all.
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_denied -- "$helper_bin" list
}

@test "[EXECUTION] enable=docker reaches SecurityServer without opening any keychain" { # https://github.com/eugene1g/agent-safehouse/issues/158
  local login_keychain

  sft_require_cmd_or_skip security

  # The login keychain is the thing that must stay shut; find its path outside
  # the sandbox so the assertions below name a real file.
  login_keychain="$(HOME="$SAFEHOUSE_HOST_HOME" /usr/bin/security list-keychains 2>/dev/null |
    sed -n 's/^ *"\(.*login\.keychain[^"]*\)".*/\1/p' | head -1)"
  [ -n "$login_keychain" ] && [ -r "$login_keychain" ] || skip "no readable login keychain outside the sandbox"

  # enable=docker grants mach-lookup on com.apple.SecurityServer so the
  # credential helper can answer "credentials not found" instead of erroring
  # (-50). A reachable Security framework must not come with keychain contents:
  # the login keychain is neither searched nor readable. Note that asserting on
  # `security` exit status would not catch a regression here -- with the grant
  # in place `find-certificate -a` exits 0 and simply returns nothing.
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok --enable=docker -- /usr/bin/security list-keychains
  [ "$status" -eq 0 ]
  sft_assert_not_contains "$output" "login.keychain"

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_denied --enable=docker -- \
    /bin/sh -c "cat '$login_keychain' >/dev/null"

  # Opening it stays a separate, explicit opt-in.
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok --enable=docker,keychain -- /usr/bin/security list-keychains
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "login.keychain"
}

@test "[EXECUTION] docker cli can reach the configured daemon only when enable=docker is set" { # https://github.com/eugene1g/agent-safehouse/issues/19
  local docker_bin

  docker_bin="$(sft_command_path_or_skip docker)" || return 1

  HOME="$SAFEHOUSE_HOST_HOME" "$docker_bin" version >/dev/null 2>&1 || skip "docker daemon precheck failed outside sandbox"

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_denied -- "$docker_bin" version

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok --enable=docker -- "$docker_bin" version >/dev/null
}
