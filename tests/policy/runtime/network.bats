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

@test "[POLICY-ONLY] --offline strips network allows and appends a terminal network deny" {
  local append_profile profile

  append_profile="$(sft_workspace_path "offline-append.sb")"
  printf '%s\n' ';; offline-append-sentinel' '(allow network-outbound (remote ip))' > "$append_profile"

  profile="$(safehouse_profile --enable=docker --append-profile="$append_profile" --offline)"

  sft_assert_contains "$profile" "#safehouse-test-id:offline-network-deny#"
  sft_assert_contains "$profile" "(deny network*)"
  sft_assert_contains "$profile" "offline-append-sentinel"
  sft_assert_not_contains "$profile" "(allow network-outbound"
  sft_assert_not_contains "$profile" "(allow network-bind"
  sft_assert_not_contains "$profile" "(allow network-inbound"
  sft_assert_order "$profile" "$(sft_source_marker "55-integrations-optional/docker.sb")" "#safehouse-test-id:offline-network-deny#"
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

@test "[EXECUTION] --offline denies outbound TCP to IP destinations" {
  local nc_pid

  sft_require_cmd_or_skip python3

  nc -l 127.0.0.1 19755 &
  nc_pid=$!
  sleep 0.3

  safehouse_ok --offline -- python3 -c "
import errno
import socket
import sys

with socket.socket() as s:
  try:
    s.connect(('127.0.0.1', 19755))
  except OSError as exc:
    if exc.errno in (errno.EACCES, errno.EPERM):
      sys.exit(0)
    raise
  else:
    sys.exit('outbound TCP connect unexpectedly succeeded')
"

  kill "$nc_pid" 2>/dev/null || true  # ignore error if nc exited early
  wait "$nc_pid" 2>/dev/null || true  # ignore SIGTERM from kill
}

@test "[EXECUTION] --offline denies binding local IP ports" {
  sft_require_cmd_or_skip python3

  safehouse_ok --offline -- python3 -c "
import errno
import sys
from contextlib import closing
import socket

with closing(socket.socket()) as s:
  try:
    s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    s.bind(('127.0.0.1', 19756))
    s.listen(1)
  except OSError as exc:
    if exc.errno in (errno.EACCES, errno.EPERM):
      sys.exit(0)
    raise
  else:
    sys.exit('local IP bind unexpectedly succeeded')
"
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
