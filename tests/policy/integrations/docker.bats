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

@test "[EXECUTION] docker cli can reach the configured daemon only when enable=docker is set" { # https://github.com/eugene1g/agent-safehouse/issues/19
  local docker_bin

  docker_bin="$(sft_command_path_or_skip docker)" || return 1

  HOME="$SAFEHOUSE_HOST_HOME" "$docker_bin" version >/dev/null 2>&1 || skip "docker daemon precheck failed outside sandbox"

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_denied -- "$docker_bin" version

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok --enable=docker -- "$docker_bin" version >/dev/null
}
