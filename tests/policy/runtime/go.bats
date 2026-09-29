#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Go toolchain settings file (GOENV) contract.
#
load ../../test_helper.bash

GO_SENTINEL_PROXY="https://safehouse-goenv-sentinel.invalid"

@test "[POLICY-ONLY] go toolchain grants read-only access to the macOS GOENV file" { # https://github.com/eugene1g/agent-safehouse/issues/85
  local profile go_section
  profile="$(safehouse_profile)"
  go_section="$(sft_profile_source_section "$profile" "30-toolchains/go.sb")"

  sft_assert_contains "$go_section" "(allow file-read*
    (home-literal \"/Library/Application Support/go/env\")
)"
  sft_assert_not_contains "$profile" "(home-subpath \"/.config/go\")"
}

@test "[EXECUTION] go honors go env -w settings from the macOS GOENV file inside the sandbox" { # https://github.com/eugene1g/agent-safehouse/issues/85
  local go_bin goenv_file
  go_bin="$(sft_command_path_or_skip go)" || return 1
  goenv_file="$(sft_write_goenv_fixture)" || return 1

  run env -u GOENV -u GOPROXY -u GOFLAGS "$go_bin" env GOENV GOPROXY
  if [[ "$status" -ne 0 ]] || [[ "$output" != "${goenv_file}"$'\n'"${GO_SENTINEL_PROXY}" ]]; then
    skip "go does not use ${goenv_file} outside the sandbox"
  fi

  safehouse_run_env -u GOENV -u GOPROXY -u GOFLAGS -- "$go_bin" env GOPROXY
  [ "$status" -eq 0 ]
  [ "$output" = "$GO_SENTINEL_PROXY" ]
}

@test "[EXECUTION] go env -w cannot modify the GOENV file inside the sandbox" { # https://github.com/eugene1g/agent-safehouse/issues/85
  local go_bin goenv_file
  go_bin="$(sft_command_path_or_skip go)" || return 1
  goenv_file="$(sft_write_goenv_fixture)" || return 1

  safehouse_denied_env -u GOENV -u GOPROXY -u GOFLAGS -- "$go_bin" env -w GOPROXY=https://changed-in-sandbox.invalid
  sft_assert_file_content "$goenv_file" "GOPROXY=${GO_SENTINEL_PROXY}"
}

@test "[EXECUTION] the Linux-only ~/.config/go path is not writable inside the sandbox" { # https://github.com/eugene1g/agent-safehouse/issues/85
  local config_go_dir
  config_go_dir="${HOME}/.config/go"
  mkdir -p "$config_go_dir" || return 1

  safehouse_denied -- /bin/sh -c 'printf "GOPROXY=off\n" > "$1"' _ "${config_go_dir}/env"
  sft_assert_path_absent "${config_go_dir}/env"
}

sft_write_goenv_fixture() {
  local goenv_dir goenv_file

  goenv_dir="${HOME}/Library/Application Support/go"
  goenv_file="${goenv_dir}/env"
  mkdir -p "$goenv_dir" || return 1
  printf 'GOPROXY=%s\n' "$GO_SENTINEL_PROXY" > "$goenv_file" || return 1

  printf '%s\n' "$goenv_file"
}
