#!/usr/bin/env bash

run_section_wrapper_and_cli() {
  local dry_run_status

  section_begin "safehouse Wrapper"
  set +e
  SAFEHOUSE_DRY_RUN_POLICY="$($SAFEHOUSE --dry-run -- /usr/bin/touch "$DRY_RUN_CANARY" 2>/dev/null)"
  dry_run_status=$?
  set -e

  if [[ "$dry_run_status" -eq 0 ]]; then
    log_pass "safehouse --dry-run exits zero"
  else
    log_fail "safehouse --dry-run exits zero (got ${dry_run_status})"
  fi

  if [[ -n "${SAFEHOUSE_DRY_RUN_POLICY:-}" && -f "$SAFEHOUSE_DRY_RUN_POLICY" ]]; then
    log_pass "safehouse --dry-run outputs an existing policy path"
  else
    log_fail "safehouse --dry-run outputs an existing policy path"
  fi

  if [[ -e "$DRY_RUN_CANARY" ]]; then
    log_fail "safehouse --dry-run does not execute wrapped command"
  else
    log_pass "safehouse --dry-run does not execute wrapped command"
  fi

  assert_command_exit_code 7 "safehouse returns wrapped command exit code" "$SAFEHOUSE" -- /bin/sh -c 'exit 7'

  rm -f "$SAFEHOUSE_OUTPUT_POLICY"
  assert_command_succeeds "safehouse --output runs wrapped command" "$SAFEHOUSE" --output "$SAFEHOUSE_OUTPUT_POLICY" -- /usr/bin/true

  if [[ -f "$SAFEHOUSE_OUTPUT_POLICY" ]]; then
    log_pass "safehouse --output keeps generated policy file"
  else
    log_fail "safehouse --output keeps generated policy file"
  fi

  assert_command_fails "safehouse fails when command is missing" "$SAFEHOUSE"

  section_begin "generate-policy.sh CLI Validation"
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

  section_begin "Static Policy Script"
  assert_command_succeeds "generate-static-policy script succeeds" "${REPO_ROOT}/scripts/generate-static-policy.sh"
  assert_policy_contains "${REPO_ROOT}/profiles/00-base.sb" "base profile exposes explicit HOME replacement placeholder" "__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__"
  assert_policy_contains "${REPO_ROOT}/generated/agent-safehouse-policy.sb" "static policy file contains sandbox header" "(version 1)"
  assert_policy_contains "${REPO_ROOT}/generated/agent-safehouse-policy.sb" "static policy file uses deterministic template HOME" "/private/tmp/agent-safehouse-static-template/home"
  assert_policy_not_contains "${REPO_ROOT}/generated/agent-safehouse-policy.sb" "static policy file resolves HOME replacement placeholder" "__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__"
}

register_section run_section_wrapper_and_cli
