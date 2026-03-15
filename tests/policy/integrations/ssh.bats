#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

cleanup_ssh_agent() {
  if [[ -n "${SFT_TEST_SSH_AGENT_PID:-}" ]]; then
    SSH_AUTH_SOCK="${SFT_TEST_SSH_AGENT_SOCK:-}" SSH_AGENT_PID="${SFT_TEST_SSH_AGENT_PID}" ssh-agent -k >/dev/null 2>&1 || true
  fi

  unset SFT_TEST_SSH_AGENT_PID
  unset SFT_TEST_SSH_AGENT_SOCK
}

start_test_ssh_agent() {
  local sock="$1" key="$2" ssh_keygen_bin="$3" ssh_add_bin="$4"
  local key_dir sock_dir

  key_dir="$(dirname "$key")"
  sock_dir="$(dirname "$sock")"

  SFT_TEST_SSH_AGENT_PID=""
  SFT_TEST_SSH_AGENT_SOCK="$sock"

  mkdir -p "$key_dir" "$sock_dir"
  chmod 700 "$key_dir" "$sock_dir"

  eval "$(ssh-agent -a "$sock" -s)" >/dev/null
  SFT_TEST_SSH_AGENT_PID="$SSH_AGENT_PID"

  "$ssh_keygen_bin" -q -t ed25519 -N '' -f "$key" >/dev/null || return 1
  SSH_AUTH_SOCK="$sock" SSH_AGENT_PID="$SFT_TEST_SSH_AGENT_PID" "$ssh_add_bin" "$key" >/dev/null || return 1
  SSH_AUTH_SOCK="$sock" "$ssh_add_bin" -l >/dev/null 2>&1 || return 1
}

@test "[EXECUTION] ssh-keygen metadata reads work by default while ssh client execution requires enable=ssh" {
  local fake_home ssh_bin ssh_dir ssh_keygen_bin

  ssh_bin="/usr/bin/ssh"
  [ -x "$ssh_bin" ] || skip "/usr/bin/ssh is not installed"
  ssh_keygen_bin="$(sft_command_path_or_skip ssh-keygen)" || return 1
  fake_home="$(sft_fake_home)" || return 1
  ssh_dir="${fake_home}/.ssh"
  mkdir -p "$ssh_dir"
  printf '%s\n' "Host github.com" "  User git" > "${ssh_dir}/config"
  printf '%s\n' "github.com ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOexampleexampleexampleexampleexample" > "${ssh_dir}/known_hosts"

  HOME="$fake_home" "$ssh_bin" -G github.com >/dev/null 2>&1 || skip "ssh config precheck failed outside sandbox"
  "$ssh_keygen_bin" -F github.com -f "${ssh_dir}/known_hosts" >/dev/null 2>&1 || skip "ssh-keygen known_hosts precheck failed outside sandbox"

  HOME="$fake_home" safehouse_denied -- "$ssh_bin" -G github.com
  HOME="$fake_home" safehouse_ok -- "$ssh_keygen_bin" -F github.com -f "${ssh_dir}/known_hosts" >/dev/null
  HOME="$fake_home" safehouse_ok --enable=ssh -- "$ssh_bin" -G github.com >/dev/null
  HOME="$fake_home" safehouse_ok --enable=ssh -- "$ssh_keygen_bin" -F github.com -f "${ssh_dir}/known_hosts" >/dev/null
}

@test "[EXECUTION] ssh private keys remain denied with and without enable=ssh" {
  local fake_home private_key ssh_dir ssh_keygen_bin

  ssh_keygen_bin="$(sft_command_path_or_skip ssh-keygen)" || return 1
  fake_home="$(sft_fake_home)" || return 1
  ssh_dir="${fake_home}/.ssh"
  private_key="${ssh_dir}/id_test"
  mkdir -p "$ssh_dir"
  "$ssh_keygen_bin" -q -t ed25519 -N '' -f "$private_key" >/dev/null || return 1

  "$ssh_keygen_bin" -y -f "$private_key" >/dev/null 2>&1 || skip "ssh private key precheck failed outside sandbox"

  HOME="$fake_home" safehouse_denied -- "$ssh_keygen_bin" -y -f "$private_key"

  HOME="$fake_home" safehouse_denied --enable=ssh -- "$ssh_keygen_bin" -y -f "$private_key"
}

@test "[POLICY-ONLY] default profile includes the core ssh-agent deny profile" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_includes_source "$profile" "50-integrations-core/ssh-agent-default-deny.sb"
}

@test "[POLICY-ONLY] default profile denies /usr/bin/ssh and outbound TCP 22" {
  local profile
  profile="$(safehouse_profile)"

  sft_assert_contains "$profile" "(deny process-exec"
  sft_assert_contains "$profile" "(literal \"/usr/bin/ssh\")"
  sft_assert_contains "$profile" "(deny network-outbound
    (remote tcp \"*:22\")"
}

@test "[POLICY-ONLY] enable=ssh adds the ssh integration marker" {
  local profile
  profile="$(safehouse_profile --enable=ssh)"

  sft_assert_includes_source "$profile" "50-integrations-core/ssh-agent-default-deny.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/ssh.sb"
  sft_assert_order "$profile" "$(sft_source_marker "50-integrations-core/ssh-agent-default-deny.sb")" "$(sft_source_marker "55-integrations-optional/ssh.sb")"
}

@test "[POLICY-ONLY] enable=ssh re-allows /usr/bin/ssh and outbound TCP 22" {
  local profile
  profile="$(safehouse_profile --enable=ssh)"

  sft_assert_contains "$profile" "(allow process-exec
    (literal \"/usr/bin/ssh\")"
  sft_assert_contains "$profile" "(allow network-outbound
    (remote tcp \"*:22\")"
}

@test "[POLICY-ONLY] current SSH_AUTH_SOCK exact path is emitted when present" {
  local fake_home sock profile

  fake_home="$(sft_fake_home)" || return 1
  sock="${fake_home}/.cache/ssh-agent/custom.sock"
  mkdir -p "$(dirname "$sock")"

  profile="$(safehouse_profile_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- --enable=ssh)"

  sft_assert_contains "$profile" "(path-literal \"${sock}\")"
}

@test "[EXECUTION] ssh agent sockets require enable=ssh" { # https://github.com/eugene1g/agent-safehouse/issues/36
  local fake_home ssh_dir sock key ssh_keygen_bin ssh_add_bin
  local ls_status default_agent_status enable_ls_status enable_agent_status

  ssh_keygen_bin="$(sft_command_path_or_skip ssh-keygen)" || return 1
  ssh_add_bin="$(sft_command_path_or_skip ssh-add)" || return 1
  fake_home="$(sft_fake_home)" || return 1
  ssh_dir="${fake_home}/.ssh"
  sock="${ssh_dir}/agent/s.issue36"
  key="${ssh_dir}/id_issue36"
  mkdir -p "${ssh_dir}/agent"
  chmod 700 "$ssh_dir" "${ssh_dir}/agent"

  start_test_ssh_agent "$sock" "$key" "$ssh_keygen_bin" "$ssh_add_bin" || return 1

  safehouse_run_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- /bin/ls "$sock"
  ls_status="$status"

  safehouse_run_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- "$ssh_add_bin" -l
  default_agent_status="$status"

  safehouse_run_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- --enable=ssh -- /bin/ls "$sock"
  enable_ls_status="$status"

  safehouse_run_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- --enable=ssh -- "$ssh_add_bin" -l
  enable_agent_status="$status"

  cleanup_ssh_agent

  [ "$ls_status" -ne 0 ]
  [ "$default_agent_status" -ne 0 ]
  [ "$enable_ls_status" -eq 0 ]
  [ "$enable_agent_status" -eq 0 ]
}

@test "[EXECUTION] custom SSH_AUTH_SOCK paths require enable=ssh" {
  local fake_home sock key ssh_keygen_bin ssh_add_bin
  local default_agent_status env_pass_agent_status enable_agent_status

  ssh_keygen_bin="$(sft_command_path_or_skip ssh-keygen)" || return 1
  ssh_add_bin="$(sft_command_path_or_skip ssh-add)" || return 1
  fake_home="$(sft_fake_home)" || return 1
  sock="${fake_home}/.cache/ssh-agent/custom.sock"
  key="${fake_home}/.ssh/id_custom_sock"

  start_test_ssh_agent "$sock" "$key" "$ssh_keygen_bin" "$ssh_add_bin" || return 1

  safehouse_run_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- "$ssh_add_bin" -l
  default_agent_status="$status"

  safehouse_run_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- --env-pass=SSH_AUTH_SOCK -- "$ssh_add_bin" -l
  env_pass_agent_status="$status"

  safehouse_run_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- --enable=ssh -- "$ssh_add_bin" -l
  enable_agent_status="$status"

  cleanup_ssh_agent

  [ "$default_agent_status" -ne 0 ]
  [ "$env_pass_agent_status" -ne 0 ]
  [ "$enable_agent_status" -eq 0 ]
}

@test "[EXECUTION] 1Password-style SSH agent sockets require enable=ssh and not enable=1password" {
  local fake_home sock key ssh_keygen_bin ssh_add_bin
  local default_agent_status onepassword_agent_status enable_agent_status

  ssh_keygen_bin="$(sft_command_path_or_skip ssh-keygen)" || return 1
  ssh_add_bin="$(sft_command_path_or_skip ssh-add)" || return 1
  fake_home="$(sft_fake_home)" || return 1
  sock="${fake_home}/.1password/agent.sock"
  key="${fake_home}/.ssh/id_1password_sock"

  start_test_ssh_agent "$sock" "$key" "$ssh_keygen_bin" "$ssh_add_bin" || return 1

  safehouse_run_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- "$ssh_add_bin" -l
  default_agent_status="$status"

  safehouse_run_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- --enable=1password -- "$ssh_add_bin" -l
  onepassword_agent_status="$status"

  safehouse_run_env HOME="$fake_home" SSH_AUTH_SOCK="$sock" -- --enable=ssh -- "$ssh_add_bin" -l
  enable_agent_status="$status"

  cleanup_ssh_agent

  [ "$default_agent_status" -ne 0 ]
  [ "$onepassword_agent_status" -ne 0 ]
  [ "$enable_agent_status" -eq 0 ]
}

@test "SSH_AUTH_SOCK launchd listener paths stay denied to generic file access by default and are allowed with enable=ssh" {
  local ssh_auth_sock

  ssh_auth_sock="${SSH_AUTH_SOCK:-}"
  [ -n "$ssh_auth_sock" ] || skip "SSH_AUTH_SOCK is unset"
  [ -e "$ssh_auth_sock" ] || skip "SSH_AUTH_SOCK path does not exist"

  if [[ ! "$ssh_auth_sock" =~ ^/private/tmp/com\.apple\.launchd\.[^/]+/Listeners$ ]] && [[ ! "$ssh_auth_sock" =~ ^/tmp/com\.apple\.launchd\.[^/]+/Listeners$ ]]; then
    skip "SSH_AUTH_SOCK does not match a launchd listener path"
  fi

  safehouse_denied -- /bin/ls "$ssh_auth_sock"

  safehouse_ok --enable=ssh -- /bin/ls "$ssh_auth_sock" >/dev/null
}
