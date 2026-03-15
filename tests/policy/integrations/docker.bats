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

@test "[EXECUTION] docker cli can reach the configured daemon only when enable=docker is set" { # https://github.com/eugene1g/agent-safehouse/issues/19
  local docker_bin

  docker_bin="$(sft_command_path_or_skip docker)" || return 1

  HOME="$SAFEHOUSE_HOST_HOME" "$docker_bin" version >/dev/null 2>&1 || skip "docker daemon precheck failed outside sandbox"

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_denied -- "$docker_bin" version

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok --enable=docker -- "$docker_bin" version >/dev/null
}
