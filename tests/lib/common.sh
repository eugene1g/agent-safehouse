#!/usr/bin/env bash

pass_count=0
fail_count=0
skip_count=0
errors=()

color_green="\033[0;32m"
color_red="\033[0;31m"
color_yellow="\033[0;33m"
color_reset="\033[0m"

current_section=""
SECTIONS=()

register_section() {
  SECTIONS+=("$1")
}

log_pass() {
  pass_count=$((pass_count + 1))
  printf "${color_green}  PASS${color_reset}  %s\n" "$1"
}

log_fail() {
  fail_count=$((fail_count + 1))
  errors+=("$1")
  printf "${color_red}  FAIL${color_reset}  %s\n" "$1"
}

log_skip() {
  skip_count=$((skip_count + 1))
  printf "${color_yellow}  SKIP${color_reset}  %s\n" "$1"
}

section_begin() {
  local name="$1"

  if [[ -n "$current_section" ]]; then
    section_end
  fi

  current_section="$name"

  echo ""
  echo "=== ${current_section} ==="
}

section_end() {
  if [[ -z "$current_section" ]]; then
    return
  fi

  current_section=""
}

run_unsandboxed() {
  "$@" >/dev/null 2>&1
}

sandbox_run() {
  local policy="$1"
  shift
  (cd "$TEST_CWD" && sandbox-exec -f "$policy" -- "$@") >/dev/null 2>&1
  return $?
}

assert_allowed() {
  local policy="$1"
  local description="$2"
  shift 2
  if sandbox_run "$policy" "$@"; then
    log_pass "$description"
  else
    log_fail "$description (expected allowed, got denied)"
  fi
}

assert_denied() {
  local policy="$1"
  local description="$2"
  shift 2
  if sandbox_run "$policy" "$@"; then
    log_fail "$description (expected denied, got allowed)"
  else
    log_pass "$description"
  fi
}

assert_allowed_strict() {
  local policy="$1"
  local description="$2"
  shift 2

  if run_unsandboxed "$@"; then
    assert_allowed "$policy" "$description" "$@"
  else
    log_skip "$description (precheck outside sandbox failed)"
  fi
}

assert_denied_strict() {
  local policy="$1"
  local description="$2"
  shift 2

  if run_unsandboxed "$@"; then
    assert_denied "$policy" "$description" "$@"
  else
    log_skip "$description (precheck outside sandbox failed)"
  fi
}

path_or_command_exists() {
  local probe="$1"
  [[ -e "$probe" ]] || command -v "$probe" >/dev/null 2>&1
}

assert_allowed_if_exists() {
  local policy="$1"
  local description="$2"
  local check_path="$3"
  shift 3
  if path_or_command_exists "$check_path"; then
    assert_allowed_strict "$policy" "$description" "$@"
  else
    log_skip "$description (${check_path} not found)"
  fi
}

assert_denied_if_exists() {
  local policy="$1"
  local description="$2"
  local check_path="$3"
  shift 3
  if path_or_command_exists "$check_path"; then
    assert_denied_strict "$policy" "$description" "$@"
  else
    log_skip "$description (${check_path} not found)"
  fi
}

assert_policy_contains() {
  local policy="$1"
  local description="$2"
  local needle="$3"
  if grep -Fq -- "$needle" "$policy"; then
    log_pass "$description"
  else
    log_fail "$description (expected policy to contain: $needle)"
  fi
}

assert_policy_not_contains() {
  local policy="$1"
  local description="$2"
  local needle="$3"
  if grep -Fq -- "$needle" "$policy"; then
    log_fail "$description (expected policy to omit: $needle)"
  else
    log_pass "$description"
  fi
}

assert_policy_order_literal() {
  local policy="$1"
  local description="$2"
  local earlier="$3"
  local later="$4"
  local earlier_line later_line

  earlier_line="$(grep -Fn -- "$earlier" "$policy" | head -n 1 | cut -d: -f1 || true)"
  later_line="$(grep -Fn -- "$later" "$policy" | head -n 1 | cut -d: -f1 || true)"

  if [[ -z "$earlier_line" || -z "$later_line" ]]; then
    log_fail "$description (missing marker(s) in policy)"
    return
  fi

  if [[ "$earlier_line" -lt "$later_line" ]]; then
    log_pass "$description"
  else
    log_fail "$description (expected marker order was reversed)"
  fi
}

assert_command_succeeds() {
  local description="$1"
  shift
  if run_unsandboxed "$@"; then
    log_pass "$description"
  else
    log_fail "$description (expected success, got failure)"
  fi
}

assert_command_fails() {
  local description="$1"
  shift
  if run_unsandboxed "$@"; then
    log_fail "$description (expected failure, got success)"
  else
    log_pass "$description"
  fi
}

assert_command_exit_code() {
  local expected_code="$1"
  local description="$2"
  shift 2

  local actual_code
  set +e
  "$@" >/dev/null 2>&1
  actual_code=$?
  set -e

  if [[ "$actual_code" -eq "$expected_code" ]]; then
    log_pass "$description"
  else
    log_fail "$description (expected exit ${expected_code}, got ${actual_code})"
  fi
}

run_registered_sections() {
  local section_fn
  for section_fn in "${SECTIONS[@]}"; do
    "$section_fn"
  done
}

print_summary_and_exit() {
  section_end

  echo ""
  echo "==========================================="
  local total
  total=$((pass_count + fail_count + skip_count))
  printf "  Total: %d  |  " "$total"
  printf "${color_green}Pass: %d${color_reset}  |  " "$pass_count"
  printf "${color_red}Fail: %d${color_reset}  |  " "$fail_count"
  printf "${color_yellow}Skip: %d${color_reset}\n" "$skip_count"
  echo "==========================================="

  if [[ "$fail_count" -gt 0 ]]; then
    echo ""
    echo "Failures:"
    local err
    for err in "${errors[@]}"; do
      printf "  ${color_red}✗${color_reset} %s\n" "$err"
    done
    exit 1
  fi

  exit 0
}
