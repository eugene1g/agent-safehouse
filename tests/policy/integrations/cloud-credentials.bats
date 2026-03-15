#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=cloud-credentials includes its optional profile source" {
  local profile
  profile="$(safehouse_profile --enable=cloud-credentials)"

  sft_assert_includes_source "$profile" "55-integrations-optional/cloud-credentials.sb"
}

@test "[EXECUTION] aws cli can read ~/.aws config only when enable=cloud-credentials is set" {
  local aws_bin aws_dir fake_home

  aws_bin="$(sft_command_path_or_skip aws)" || return 1

  fake_home="$(sft_fake_home)" || return 1
  aws_dir="${fake_home}/.aws"
  mkdir -p "$aws_dir"
  cat > "${aws_dir}/config" <<'EOF'
[default]
region = us-east-1
output = json
EOF
  cat > "${aws_dir}/credentials" <<'EOF'
[default]
aws_access_key_id = AKIAEXAMPLE
aws_secret_access_key = SECRETEXAMPLE
EOF

  HOME="$fake_home" "$aws_bin" configure get region >/dev/null 2>&1 || skip "aws config precheck failed outside sandbox"

  HOME="$fake_home" safehouse_run -- "$aws_bin" configure get region
  [ "$status" -ne 0 ]
  [ -z "$output" ]

  HOME="$fake_home" run safehouse_ok --enable=cloud-credentials -- "$aws_bin" configure get region
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "us-east-1"
}

@test "azure and azd state directories stay denied by default and become readable when enabled" {
  local fake_home azure_dir azd_dir

  fake_home="$(sft_fake_home)" || return 1
  azure_dir="${fake_home}/.azure"
  azd_dir="${fake_home}/.azd"
  mkdir -p "$azure_dir" "$azd_dir"
  printf '%s\n' "{}" > "${azure_dir}/config"
  printf '%s\n' "{}" > "${azd_dir}/env.json"

  HOME="$fake_home" safehouse_denied -- /bin/ls "$azure_dir"

  HOME="$fake_home" safehouse_denied -- /bin/ls "$azd_dir"

  HOME="$fake_home" safehouse_ok --enable=cloud-credentials -- /bin/ls "$azure_dir" >/dev/null
  HOME="$fake_home" safehouse_ok --enable=cloud-credentials -- /bin/ls "$azd_dir" >/dev/null
}
