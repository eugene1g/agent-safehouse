#!/usr/bin/env bash

run_section_wrapper_and_cli() {
  local no_command_policy no_command_status
  local stdout_first_line stdout_canary output_policy config_file config_policy
  local dist_path dist_no_command_policy dist_no_command_status dist_stdout_first_line
  local dist_stdout_canary dist_output_policy dist_policy_from_bin dist_policy_from_dist

  section_begin "safehouse.sh Entry Point"
  set +e
  no_command_policy="$("$SAFEHOUSE" 2>/dev/null)"
  no_command_status=$?
  set -e
  if [[ "$no_command_status" -eq 0 && -n "${no_command_policy:-}" && -f "$no_command_policy" ]]; then
    log_pass "safehouse.sh with no command generates policy and exits zero"
    rm -f "$no_command_policy"
  else
    log_fail "safehouse.sh with no command generates policy and exits zero"
  fi

  config_file="${TEST_CWD}/.safehouse"
  cat > "$config_file" <<EOF
add-dirs-ro=${TEST_RO_DIR_2}
add-dirs=${TEST_RW_DIR_2}
EOF
  set +e
  config_policy="$(cd "$TEST_CWD" && "$SAFEHOUSE" 2>/dev/null)"
  local config_status=$?
  set -e
  if [[ "$config_status" -eq 0 && -n "${config_policy:-}" && -f "$config_policy" ]]; then
    log_pass "safehouse.sh auto-loads .safehouse config from selected workdir"
    assert_policy_contains "$config_policy" "safehouse.sh .safehouse emits read-only grant" "(subpath \"${TEST_RO_DIR_2}\")"
    assert_policy_contains "$config_policy" "safehouse.sh .safehouse emits read/write grant" "file-read* file-write* (subpath \"${TEST_RW_DIR_2}\")"
    rm -f "$config_policy"
  else
    log_fail "safehouse.sh auto-loads .safehouse config from selected workdir"
  fi
  rm -f "$config_file"

  assert_command_fails "safehouse.sh does not accept --dry-run" "$SAFEHOUSE" --dry-run -- /usr/bin/true
  assert_command_fails "safehouse.sh does not accept --enable=browser-nm" "$SAFEHOUSE" --enable=browser-nm

  stdout_first_line="$("$SAFEHOUSE" --stdout 2>/dev/null | sed -n '1p')"
  if [[ "$stdout_first_line" == "(version 1)" ]]; then
    log_pass "safehouse.sh --stdout prints policy text"
  else
    log_fail "safehouse.sh --stdout prints policy text"
  fi

  stdout_canary="${TEST_CWD}/safehouse-stdout-canary.$$"
  rm -f "$stdout_canary"
  assert_command_succeeds "safehouse.sh --stdout with command exits zero" "$SAFEHOUSE" --stdout -- /usr/bin/touch "$stdout_canary"
  if [[ -e "$stdout_canary" ]]; then
    log_fail "safehouse.sh --stdout with command does not execute wrapped command"
  else
    log_pass "safehouse.sh --stdout with command does not execute wrapped command"
  fi

  assert_command_exit_code 6 "safehouse.sh returns wrapped command exit code" "$SAFEHOUSE" -- /bin/sh -c 'exit 6'
  assert_command_exit_code 5 "safehouse.sh returns wrapped command exit code without -- separator" "$SAFEHOUSE" /bin/sh -c 'exit 5'

  output_policy="${TEST_CWD}/safehouse-output-policy.sb"
  rm -f "$output_policy"
  assert_command_succeeds "safehouse.sh --output runs wrapped command" "$SAFEHOUSE" --output "$output_policy" -- /usr/bin/true
  if [[ -f "$output_policy" ]]; then
    log_pass "safehouse.sh --output keeps generated policy file"
    rm -f "$output_policy"
  else
    log_fail "safehouse.sh --output keeps generated policy file"
  fi

  section_begin "Policy CLI Validation"
  if "$GENERATOR" --add-dirs 2>/dev/null; then
    log_fail "--add-dirs with no value should fail"
  else
    log_pass "--add-dirs with no value exits non-zero"
  fi
  if "$GENERATOR" --add-dirs-ro 2>/dev/null; then
    log_fail "--add-dirs-ro with no value should fail"
  else
    log_pass "--add-dirs-ro with no value exits non-zero"
  fi
  if "$GENERATOR" --workdir 2>/dev/null; then
    log_fail "--workdir with no value should fail"
  else
    log_pass "--workdir with no value exits non-zero"
  fi
  if "$GENERATOR" --append-profile 2>/dev/null; then
    log_fail "--append-profile with no value should fail"
  else
    log_pass "--append-profile with no value exits non-zero"
  fi
  if "$GENERATOR" --output 2>/dev/null; then
    log_fail "--output with no value should fail"
  else
    log_pass "--output with no value exits non-zero"
  fi
  if "$GENERATOR" --bogus-flag 2>/dev/null; then
    log_fail "unknown flag should fail"
  else
    log_pass "unknown flag exits non-zero"
  fi
  if "$GENERATOR" --enable=bogus 2>/dev/null; then
    log_fail "unknown --enable feature should fail"
  else
    log_pass "unknown --enable feature exits non-zero"
  fi

  section_begin "Dist Artifact Generator Script"
  assert_command_succeeds "generate-dist script regenerates committed dist artifacts" "${REPO_ROOT}/scripts/generate-dist.sh"
  assert_policy_contains "${REPO_ROOT}/profiles/00-base.sb" "base profile exposes explicit HOME replacement placeholder" "__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__"
  assert_policy_contains "${REPO_ROOT}/dist/safehouse.generated.sb" "default static policy file contains sandbox header" "(version 1)"
  assert_policy_contains "${REPO_ROOT}/dist/safehouse.generated.sb" "default static policy file uses deterministic template HOME" "/private/tmp/agent-safehouse-static-template/home"
  assert_policy_not_contains "${REPO_ROOT}/dist/safehouse.generated.sb" "default static policy file resolves HOME replacement placeholder" "__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__"
  assert_policy_contains "${REPO_ROOT}/dist/safehouse-for-apps.generated.sb" "apps static policy file contains sandbox header" "(version 1)"
  assert_policy_contains "${REPO_ROOT}/dist/safehouse-for-apps.generated.sb" "apps static policy file uses deterministic template HOME" "/private/tmp/agent-safehouse-static-template/home"
  assert_policy_not_contains "${REPO_ROOT}/dist/safehouse-for-apps.generated.sb" "apps static policy file resolves HOME replacement placeholder" "__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__"
  assert_policy_contains "${REPO_ROOT}/dist/safehouse-for-apps.generated.sb" "apps static policy includes electron integration profile" "#safehouse-test-id:electron-integration#"
  assert_policy_contains "${REPO_ROOT}/dist/safehouse-for-apps.generated.sb" "apps static policy includes macOS GUI integration profile" ";; Integration: macOS GUI"

  section_begin "Dist Binary Generator Script"
  dist_path="${TEST_CWD}/safehouse-dist.sh"
  dist_stdout_canary="${TEST_CWD}/dist-stdout-canary.$$"
  dist_output_policy="${TEST_CWD}/dist-output-policy.sb"
  dist_policy_from_bin="${TEST_CWD}/bin-policy-parity.sb"
  dist_policy_from_dist="${TEST_CWD}/dist-policy-parity.sb"
  rm -f "$dist_path" "$dist_stdout_canary" "$dist_output_policy" "$dist_policy_from_bin" "$dist_policy_from_dist"

  assert_command_succeeds "generate-dist script succeeds" "${REPO_ROOT}/scripts/generate-dist.sh" --output "$dist_path"
  if [[ -x "$dist_path" ]]; then
    log_pass "dist safehouse output is executable"
  else
    log_fail "dist safehouse output is executable"
  fi

  set +e
  dist_no_command_policy="$("$dist_path" 2>/dev/null)"
  dist_no_command_status=$?
  set -e

  if [[ "$dist_no_command_status" -eq 0 && -n "${dist_no_command_policy:-}" && -f "$dist_no_command_policy" ]]; then
    log_pass "dist safehouse with no command generates policy and exits zero"
  else
    log_fail "dist safehouse with no command generates policy and exits zero"
  fi

  if [[ -n "${dist_no_command_policy:-}" && -f "$dist_no_command_policy" ]]; then
    rm -f "$dist_no_command_policy"
  fi

  dist_stdout_first_line="$("$dist_path" --stdout 2>/dev/null | sed -n '1p')"
  if [[ "$dist_stdout_first_line" == "(version 1)" ]]; then
    log_pass "dist safehouse --stdout outputs policy text"
  else
    log_fail "dist safehouse --stdout outputs policy text"
  fi

  assert_command_succeeds "dist safehouse --stdout with command exits zero" "$dist_path" --stdout -- /usr/bin/touch "$dist_stdout_canary"
  if [[ -e "$dist_stdout_canary" ]]; then
    log_fail "dist safehouse --stdout with command does not execute wrapped command"
  else
    log_pass "dist safehouse --stdout with command does not execute wrapped command"
  fi

  assert_command_succeeds "dist safehouse --output runs wrapped command" "$dist_path" --output "$dist_output_policy" -- /usr/bin/true
  if [[ -f "$dist_output_policy" ]]; then
    log_pass "dist safehouse --output keeps generated policy file"
  else
    log_fail "dist safehouse --output keeps generated policy file"
  fi

  assert_command_exit_code 9 "dist safehouse returns wrapped command exit code" "$dist_path" -- /bin/sh -c 'exit 9'

  assert_command_succeeds "bin safehouse writes parity policy file" "$SAFEHOUSE" --output "$dist_policy_from_bin"
  assert_command_succeeds "dist safehouse writes parity policy file" "$dist_path" --output "$dist_policy_from_dist"
  if cmp -s "$dist_policy_from_bin" "$dist_policy_from_dist"; then
    log_pass "dist safehouse policy output matches bin/safehouse.sh byte-for-byte"
  else
    log_fail "dist safehouse policy output matches bin/safehouse.sh byte-for-byte"
  fi

  rm -f "$dist_stdout_canary" "$dist_output_policy" "$dist_policy_from_bin" "$dist_policy_from_dist"
}

register_section run_section_wrapper_and_cli
