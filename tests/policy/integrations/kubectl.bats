#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=kubectl includes its optional profile source" {
  local profile
  profile="$(safehouse_profile --enable=kubectl)"

  sft_assert_includes_source "$profile" "55-integrations-optional/kubectl.sb"
}

@test "[EXECUTION] kubectl can read kubeconfig only when enable=kubectl is set" {
  local kubectl_bin fake_home kube_dir

  kubectl_bin="$(sft_command_path_or_skip kubectl)" || return 1
  fake_home="$(sft_fake_home)" || return 1
  kube_dir="${fake_home}/.kube"
  mkdir -p "$kube_dir/cache"
  cat > "${kube_dir}/config" <<'EOF'
apiVersion: v1
clusters:
- cluster:
    server: https://example.invalid
  name: example
contexts:
- context:
    cluster: example
    user: example
  name: example
current-context: example
kind: Config
preferences: {}
users:
- name: example
  user:
    token: test
EOF

  HOME="$fake_home" "$kubectl_bin" config view --raw >/dev/null 2>&1 || skip "kubectl config precheck failed outside sandbox"

  HOME="$fake_home" safehouse_denied -- "$kubectl_bin" config view --raw

  HOME="$fake_home" run safehouse_ok --enable=kubectl -- "$kubectl_bin" config view --raw
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "current-context: example"
}

@test "krew state stays denied by default and becomes readable when enable=kubectl is set" {
  local fake_home krew_dir

  fake_home="$(sft_fake_home)" || return 1
  krew_dir="${fake_home}/.krew"
  mkdir -p "$krew_dir"

  HOME="$fake_home" safehouse_denied -- /bin/ls "$krew_dir"
  HOME="$fake_home" safehouse_ok --enable=kubectl -- /bin/ls "$krew_dir" >/dev/null
}
