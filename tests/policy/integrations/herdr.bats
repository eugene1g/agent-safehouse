#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

# Overrides the shared teardown (test_helper.bash) to also reap the socket listener and the
# headless herdr server, which the in-test cleanup misses when a test aborts on a failed assertion.
teardown() {
  if [ -n "${nc_pid:-}" ]; then
    kill "$nc_pid" 2>/dev/null || true
    wait "$nc_pid" 2>/dev/null || true
  fi

  local pid
  for pid in "${herdr_server_pid:-}" "${herdr_session_server_pid:-}"; do
    [ -n "$pid" ] || continue
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done

  sft_teardown_test_env
}

@test "[POLICY-ONLY] enable=herdr includes its optional profile source" {
  local default_profile enabled_profile

  default_profile="$(safehouse_profile)"
  enabled_profile="$(safehouse_profile --enable=herdr)"

  sft_assert_omits_source "$default_profile" "55-integrations-optional/herdr.sb"
  sft_assert_includes_source "$enabled_profile" "55-integrations-optional/herdr.sb"
}

@test "[POLICY-ONLY] HERDR_ENV in the host environment auto-enables the herdr profile" {
  local unset_profile set_profile

  unset_profile="$(safehouse_profile)"
  set_profile="$(safehouse_profile_env HERDR_ENV=1 --)"

  sft_assert_omits_source "$unset_profile" "55-integrations-optional/herdr.sb"
  sft_assert_includes_source "$set_profile" "55-integrations-optional/herdr.sb"
}

@test "[POLICY-ONLY] HERDR_ENV auto-detection passes through the herdr session-identity variables" { # https://github.com/eugene1g/agent-safehouse/issues/156
  local explain_log

  explain_log="$(sft_workspace_path "explain-herdr.log")"

  safehouse_ok_env HERDR_ENV=1 -- --explain --stdout >/dev/null 2>"$explain_log"

  sft_assert_file_contains "$explain_log" "named host vars (HERDR_ENV HERDR_SOCKET_PATH HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID)"
}

@test "[POLICY-ONLY] herdr profile grants read access to the herdr config directory and its socket" {
  local profile section

  profile="$(safehouse_profile --enable=herdr)"
  section="$(sft_profile_source_section "$profile" "55-integrations-optional/herdr.sb")"

  sft_assert_contains "$section" '(home-subpath "/.config/herdr")'
  sft_assert_contains "$section" '(remote unix-socket (home-literal "/.config/herdr/herdr.sock"))'
}

@test "[EXECUTION] herdr config directory stays denied by default and becomes readable when enabled" { # https://github.com/eugene1g/agent-safehouse/issues/156
  local fake_home herdr_dir state_file

  fake_home="$(sft_fake_home)" || return 1
  herdr_dir="${fake_home}/.config/herdr"
  state_file="${herdr_dir}/state.json"

  mkdir -p "$herdr_dir"
  printf '%s\n' '{"status":"idle"}' > "$state_file"

  HOME="$fake_home" safehouse_denied -- /bin/cat "$state_file"

  HOME="$fake_home" safehouse_ok --enable=herdr -- /bin/cat "$state_file" >/dev/null
}

@test "[EXECUTION] herdr socket connect stays denied by default and becomes allowed when enabled" { # https://github.com/eugene1g/agent-safehouse/issues/156
  local fake_home herdr_dir socket_path  # nc_pid stays global for teardown

  fake_home="$(sft_fake_home)" || return 1
  herdr_dir="${fake_home}/.config/herdr"
  socket_path="${herdr_dir}/herdr.sock"

  mkdir -p "$herdr_dir"
  nc -lU "$socket_path" &
  nc_pid=$!
  sleep 0.3

  HOME="$fake_home" safehouse_denied -- /bin/sh -c "nc -U '$socket_path' </dev/null 2>&1"

  HOME="$fake_home" safehouse_ok --enable=herdr -- /bin/sh -c "printf '' | nc -U '$socket_path' >/dev/null 2>&1"
}

@test "[POLICY-ONLY] herdr profile grants unix-socket access to named-session API sockets only" { # https://herdr.dev/docs/socket-api/#socket-paths
  local profile section

  profile="$(safehouse_profile --enable=herdr)"
  section="$(sft_profile_source_section "$profile" "55-integrations-optional/herdr.sb")"

  sft_assert_contains "$section" '/\\.config/herdr/sessions/[^/]+/herdr\\.sock$'
  sft_assert_not_contains "$section" '(home-subpath "/.config/herdr/sessions")'
}

@test "[EXECUTION] herdr named-session socket connect stays denied by default and becomes allowed when enabled" { # https://herdr.dev/docs/socket-api/#socket-paths
  local fake_home socket_path  # nc_pid stays global for teardown

  fake_home="$(sft_fake_home)" || return 1
  socket_path="${fake_home}/.config/herdr/sessions/api/herdr.sock"

  mkdir -p "$(dirname "$socket_path")"
  nc -lU "$socket_path" &
  nc_pid=$!
  sleep 0.3

  HOME="$fake_home" safehouse_denied -- /bin/sh -c "nc -U '$socket_path' </dev/null 2>&1"

  HOME="$fake_home" safehouse_ok --enable=herdr -- /bin/sh -c "printf '' | nc -U '$socket_path' >/dev/null 2>&1"
}

@test "[EXECUTION] herdr TUI-attach client sockets stay denied even when enabled" { # https://github.com/eugene1g/agent-safehouse/issues/193
  local fake_home socket_path  # nc_pid stays global for teardown

  fake_home="$(sft_fake_home)" || return 1

  for socket_path in \
    "${fake_home}/.config/herdr/herdr-client.sock" \
    "${fake_home}/.config/herdr/sessions/api/herdr-client.sock"; do
    mkdir -p "$(dirname "$socket_path")"
    nc -lU "$socket_path" &
    nc_pid=$!
    sleep 0.3

    HOME="$fake_home" safehouse_denied --enable=herdr -- /bin/sh -c "nc -U '$socket_path' </dev/null 2>&1"

    kill "$nc_pid" 2>/dev/null || true
    wait "$nc_pid" 2>/dev/null || true
    nc_pid=""
  done
}

@test "[EXECUTION] herdr client stays denied by default and reaches real headless herdr servers when enabled" { # https://herdr.dev/docs/cli-reference/#server
  local herdr_bin herdr_dir fake_home socket_path session_socket_path i  # herdr_server_pid, herdr_session_server_pid stay global for teardown

  sft_command_path_or_skip herdr_bin herdr
  herdr_dir="$(cd -- "$(dirname -- "$herdr_bin")" && pwd -P)"
  fake_home="$(sft_fake_home)" || return 1
  socket_path="${fake_home}/.config/herdr/herdr.sock"
  session_socket_path="${fake_home}/.config/herdr/sessions/api/herdr.sock"

  HOME="$fake_home" "$herdr_bin" server </dev/null >/dev/null 2>&1 &
  herdr_server_pid=$!
  HOME="$fake_home" "$herdr_bin" --session api server </dev/null >/dev/null 2>&1 &
  herdr_session_server_pid=$!

  for i in {1..40}; do
    [ -S "$socket_path" ] && [ -S "$session_socket_path" ] && break
    sleep 0.25
  done
  if [ ! -S "$socket_path" ] || [ ! -S "$session_socket_path" ]; then
    printf 'herdr server socket(s) did not appear\n' >&2
    cat "${fake_home}/.config/herdr/herdr-server.log" "${fake_home}/.config/herdr/sessions/api/herdr-server.log" >&2 2>/dev/null || true
    return 1
  fi

  HOME="$fake_home" safehouse_denied --add-dirs-ro "$herdr_dir" -- "$herdr_bin" api snapshot
  HOME="$fake_home" safehouse_denied --add-dirs-ro "$herdr_dir" -- "$herdr_bin" --session api api snapshot

  HOME="$fake_home" safehouse_ok --enable=herdr --add-dirs-ro "$herdr_dir" -- "$herdr_bin" api snapshot
  HOME="$fake_home" safehouse_ok --enable=herdr --add-dirs-ro "$herdr_dir" -- "$herdr_bin" --session api api snapshot
}
