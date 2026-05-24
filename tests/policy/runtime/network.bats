#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Network policy regression tests for 20-network.sb.
# Verifies that the default policy uses narrowed IP-only rules (not the broad
# `network*` wildcard) and that UNIX-socket outbound is denied while normal
# TCP and DNS paths remain functional.
#
load ../../test_helper.bash

@test "[POLICY-ONLY] default profile uses narrowed IP outbound rules, not broad network*" { # https://github.com/eugene1g/agent-safehouse/issues/99
  local profile
  profile="$(safehouse_profile)"

  sft_assert_includes_source "$profile" "20-network.sb"
  sft_assert_not_contains "$profile" "(allow network*)"
  sft_assert_contains "$profile" "(allow network-outbound (remote ip))"
  sft_assert_contains "$profile" '(allow network-outbound (literal "/private/var/run/mDNSResponder"))'
  sft_assert_contains "$profile" "(allow network-bind"
  sft_assert_contains "$profile" "(allow network-inbound"
}

@test "[EXECUTION] default sandbox denies outbound to UNIX-domain sockets" { # https://github.com/eugene1g/agent-safehouse/issues/99
  local socket_path nc_pid

  socket_path="${BATS_TEST_TMPDIR}/test-unix-$$.sock"
  nc -lU "$socket_path" &
  nc_pid=$!
  sleep 0.3

  safehouse_denied -- /bin/sh -c "nc -U '$socket_path' </dev/null 2>&1"

  kill "$nc_pid" 2>/dev/null || true  # ignore error if nc exited early
  wait "$nc_pid" 2>/dev/null || true  # ignore SIGTERM from kill
  rm -f "$socket_path"
}

@test "[EXECUTION] default sandbox allows outbound TCP to IP destinations" { # https://github.com/eugene1g/agent-safehouse/issues/99
  local nc_pid

  nc -l 127.0.0.1 19753 &
  nc_pid=$!
  sleep 0.3

  safehouse_ok -- /bin/sh -c "printf '' | nc 127.0.0.1 19753 >/dev/null 2>&1"

  kill "$nc_pid" 2>/dev/null || true  # ignore error if nc exited early
  wait "$nc_pid" 2>/dev/null || true  # ignore SIGTERM from kill
}

@test "[EXECUTION] default sandbox allows DNS resolution via mDNSResponder" { # https://github.com/eugene1g/agent-safehouse/issues/99
  sft_require_cmd_or_skip python3

  safehouse_ok -- python3 -c "import socket; socket.gethostbyname('localhost')"
}

@test "[EXECUTION] default sandbox can bind and listen on a local IP port" { # https://github.com/eugene1g/agent-safehouse/issues/99
  sft_require_cmd_or_skip python3

  safehouse_ok -- python3 -c "
from contextlib import closing
import socket
with closing(socket.socket()) as s:
  s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
  s.bind(('127.0.0.1', 19754))
  s.listen(1)
"
}
