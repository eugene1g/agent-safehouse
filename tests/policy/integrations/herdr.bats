#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

# Overrides the shared teardown (test_helper.bash) to also reap the socket listener, which
# the in-test cleanup misses when a test aborts on a failed assertion.
teardown() {
  if [ -n "${nc_pid:-}" ]; then
    kill "$nc_pid" 2>/dev/null || true
    wait "$nc_pid" 2>/dev/null || true
  fi

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

@test "[POLICY-ONLY] herdr profile grants unix-socket access to the default socket and the named-sessions directory" { # https://herdr.dev/docs/socket-api/#socket-paths
  local profile section

  profile="$(safehouse_profile --enable=herdr)"
  section="$(sft_profile_source_section "$profile" "55-integrations-optional/herdr.sb")"

  sft_assert_contains "$section" '(remote unix-socket (home-subpath "/.config/herdr/sessions"))'
}

@test "[EXECUTION] herdr named-session socket connect stays denied by default and becomes allowed when enabled" { # https://herdr.dev/docs/socket-api/#socket-paths
  local fake_home herdr_dir socket_path  # nc_pid stays global for teardown

  fake_home="$(sft_fake_home)" || return 1
  herdr_dir="${fake_home}/.config/herdr"
  socket_path="${herdr_dir}/sessions/api/herdr.sock"

  mkdir -p "$(dirname "$socket_path")"
  nc -lU "$socket_path" &
  nc_pid=$!
  sleep 0.3

  HOME="$fake_home" safehouse_denied -- /bin/sh -c "nc -U '$socket_path' </dev/null 2>&1"

  HOME="$fake_home" safehouse_ok --enable=herdr -- /bin/sh -c "printf '' | nc -U '$socket_path' >/dev/null 2>&1"
}
