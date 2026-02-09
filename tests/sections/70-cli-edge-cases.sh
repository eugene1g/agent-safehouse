#!/usr/bin/env bash

run_section_cli_edge_cases() {
  local policy_enable_arg policy_enable_csv policy_workdir_empty_eq missing_path home_not_dir output_space output_nested args_file
  local marker_dynamic marker_workdir marker_local_overrides

  marker_dynamic="#safehouse-test-id:dynamic-cli-grants#"
  marker_workdir="#safehouse-test-id:workdir-grant#"
  marker_local_overrides="#safehouse-test-id:local-overrides#"

  section_begin "Binary Entry Points"
  assert_command_succeeds "bin/generate-policy.sh works from /tmp via absolute path" /bin/sh -c "cd /tmp && '${GENERATOR}' >/dev/null"
  assert_command_succeeds "bin/safehouse works from /tmp via absolute path" /bin/sh -c "cd /tmp && '${SAFEHOUSE}' -- /usr/bin/true"

  section_begin "Enable Flag Parsing"
  policy_enable_arg="${TEST_CWD}/policy-enable-arg.sb"
  policy_enable_csv="${TEST_CWD}/policy-enable-csv.sb"
  assert_command_succeeds "--enable docker parses as separate argument form" "$GENERATOR" --output "$policy_enable_arg" --enable docker
  assert_policy_contains "$policy_enable_arg" "--enable docker includes docker grants" "/var/run/docker.sock"
  assert_policy_contains "$policy_enable_arg" "--enable docker preserves default browser native messaging grants" "/NativeMessagingHosts"
  assert_command_succeeds "--enable=docker,browser-nm parses CSV with whitespace" "$GENERATOR" --output "$policy_enable_csv" "--enable=docker, browser-nm"
  assert_policy_contains "$policy_enable_csv" "CSV --enable includes docker grants" "/var/run/docker.sock"
  assert_policy_contains "$policy_enable_csv" "CSV --enable includes browser native messaging grants" "/NativeMessagingHosts"

  section_begin "Workdir Flag Parsing"
  policy_workdir_empty_eq="${TEST_CWD}/policy-workdir-empty-equals.sb"
  assert_command_succeeds "--workdir= (empty) is accepted and disables automatic workdir grant" "$GENERATOR" --output "$policy_workdir_empty_eq" --workdir=
  assert_policy_not_contains "$policy_workdir_empty_eq" "--workdir= omits automatic workdir grant marker" "$marker_workdir"

  section_begin "Generator Path/Home Validation"
  missing_path="/tmp/safehouse-missing-path-$$"
  rm -rf "$missing_path"
  assert_command_fails "--add-dirs fails for nonexistent path" "$GENERATOR" --add-dirs "$missing_path"
  assert_command_fails "--add-dirs-ro fails for nonexistent path" "$GENERATOR" --add-dirs-ro "$missing_path"
  assert_command_fails "--workdir fails for nonexistent path" "$GENERATOR" --workdir "$missing_path"
  assert_command_fails "generator fails when HOME is unset" /usr/bin/env -u HOME "$GENERATOR"
  home_not_dir="${TEST_CWD}/home-not-a-directory.txt"
  printf 'not-a-directory\n' > "$home_not_dir"
  assert_command_fails "generator fails when HOME is not a directory" /usr/bin/env HOME="$home_not_dir" "$GENERATOR"

  section_begin "Policy Emission Order"
  assert_policy_order_literal "$POLICY_MERGE" "dynamic grants are emitted before workdir grant" "$marker_dynamic" "$marker_workdir"
  assert_policy_order_literal "$POLICY_MERGE" "workdir grant is emitted before local overrides" "$marker_workdir" "$marker_local_overrides"
  assert_policy_order_literal "$POLICY_MERGE" "dynamic grants are emitted before local overrides" "$marker_dynamic" "$marker_local_overrides"

  section_begin "Output Path Edge Cases"
  output_space="${TEST_CWD}/output dir/policy with spaces.sb"
  output_nested="${TEST_CWD}/nested/output/path/policy.sb"
  assert_command_succeeds "--output supports paths with spaces" "$GENERATOR" --output "$output_space"
  if [[ -f "$output_space" ]]; then
    log_pass "--output with spaces creates file"
  else
    log_fail "--output with spaces creates file"
  fi
  assert_policy_contains "$output_space" "--output with spaces writes a valid policy" "(version 1)"
  rm -rf "${TEST_CWD}/nested"
  assert_command_succeeds "--output auto-creates missing parent directories" "$GENERATOR" --output "$output_nested"
  if [[ -f "$output_nested" ]]; then
    log_pass "--output created nested parent directories"
  else
    log_fail "--output created nested parent directories"
  fi
  printf 'sentinel-old\n' > "$output_nested"
  assert_command_succeeds "--output overwrites existing policy file" "$GENERATOR" --output "$output_nested"
  if grep -Fq "sentinel-old" "$output_nested"; then
    log_fail "--output overwrite replaces previous file contents"
  else
    log_pass "--output overwrite replaces previous file contents"
  fi

  section_begin "safehouse Argument Passthrough"
  args_file="/tmp/safehouse-args-$$.txt"
  rm -f "$args_file"
  assert_command_succeeds "safehouse preserves quoted and spaced wrapped command arguments" "$SAFEHOUSE" -- /bin/sh -c 'printf "[%s]|[%s]|[%s]|[%s]\n" "$1" "$2" "$3" "$4" > "$5"' sh "two words" 'quote"double' "single'quote" '$dollar value' "$args_file"
  if [[ -f "$args_file" ]] && grep -Fxq "[two words]|[quote\"double]|[single'quote]|[\$dollar value]" "$args_file"; then
    log_pass "safehouse preserves exact wrapped command argument boundaries"
  else
    log_fail "safehouse preserves exact wrapped command argument boundaries"
  fi
  rm -f "$args_file"
}

register_section run_section_cli_edge_cases
