#!/usr/bin/env bash

validate_test_args() {
  local runner_path="$1"
  shift

  if [[ $# -ne 0 ]]; then
    echo "ERROR: $(basename "$runner_path") does not accept arguments." >&2
    exit 1
  fi
}

validate_prerequisites() {
  if [[ ! -x "$GENERATOR" ]]; then
    echo "ERROR: policy generator is missing or not executable: $GENERATOR" >&2
    exit 1
  fi

  if [[ ! -x "$SAFEHOUSE" ]]; then
    echo "ERROR: safehouse wrapper is missing or not executable: $SAFEHOUSE" >&2
    exit 1
  fi
}

preflight_sandbox_exec() {
  local preflight_policy
  preflight_policy="$(mktemp /tmp/safehouse-preflight.XXXXXX)"
  printf '(version 1)\n(allow default)\n' > "$preflight_policy"

  if ! sandbox-exec -f "$preflight_policy" -- /bin/echo preflight-ok >/dev/null 2>&1; then
    rm -f "$preflight_policy"
    echo "ERROR: sandbox-exec cannot run (nested sandbox or SIP restriction)." >&2
    echo "Run this script from a normal terminal session, not from inside an agent sandbox." >&2
    exit 2
  fi

  rm -f "$preflight_policy"
}

setup_test_environment() {
  echo "Setting up test environment..."

  TEST_CWD="$(mktemp -d /tmp/safehouse-test-cwd.XXXXXX)"
  TEST_RW_DIR="$(mktemp -d /tmp/safehouse-test-rw.XXXXXX)"
  TEST_RO_DIR="${HOME}/.safehouse-test-ro.$$"
  TEST_RO_DIR_2="${HOME}/.safehouse-test-ro2.$$"
  TEST_RW_DIR_2="${HOME}/.safehouse-test-rw2.$$"
  TEST_OVERLAP_DIR="${HOME}/.safehouse-test-overlap.$$"
  TEST_SPACE_PARENT="${HOME}/.safehouse-test-space-parent.$$"
  TEST_SPACE_DIR="${TEST_SPACE_PARENT}/dir with space"
  TEST_DENIED_DIR="${HOME}/.safehouse-test-denied.$$"
  TEST_GIT_REPO="$(mktemp -d /tmp/safehouse-test-git.XXXXXX)"
  TEST_GIT_SUBDIR="${TEST_GIT_REPO}/nested/work"
  TEST_RO_FILE="${HOME}/.safehouse-test-ro-file.$$"
  TEST_RW_FILE="${HOME}/.safehouse-test-rw-file.$$"
  TEST_TMP_CANARY="/tmp/safehouse-test-tmp-canary.$$"
  TEST_HOME_CANARY="${HOME}/.safehouse-test-home-canary.$$"
  SAFEHOUSE_OUTPUT_POLICY="${TEST_CWD}/safehouse-output-policy.sb"
  DRY_RUN_CANARY="${TEST_CWD}/safehouse-dry-run-canary.$$"

  mkdir -p "$TEST_RO_DIR" "$TEST_RO_DIR_2" "$TEST_RW_DIR_2" "$TEST_OVERLAP_DIR" "$TEST_SPACE_DIR" "$TEST_DENIED_DIR" "$TEST_GIT_SUBDIR"

  echo "test-ro-content" > "${TEST_RO_DIR}/readable.txt"
  echo "test-ro2-content" > "${TEST_RO_DIR_2}/readable2.txt"
  echo "test-rw-content" > "${TEST_RW_DIR}/writable.txt"
  echo "test-rw2-content" > "${TEST_RW_DIR_2}/writable2.txt"
  echo "test-space-content" > "${TEST_SPACE_DIR}/space.txt"
  echo "test-overlap-content" > "${TEST_OVERLAP_DIR}/overlap.txt"
  echo "test-ro-file-content" > "$TEST_RO_FILE"
  echo "test-rw-file-content" > "$TEST_RW_FILE"

  echo "Generating default policy (CWD=${TEST_CWD})..."
  POLICY_DEFAULT="$(cd "$TEST_CWD" && "$GENERATOR")"

  echo "Generating policy with extra dirs (ro=${TEST_RO_DIR}, rw=${TEST_RW_DIR})..."
  POLICY_EXTRA="$(cd "$TEST_CWD" && "$GENERATOR" --add-dirs-ro="$TEST_RO_DIR" --add-dirs="$TEST_RW_DIR")"

  echo "Generating feature-toggle policies (--enable=docker, --enable=kubectl, --enable=macos-gui, --enable=electron)..."
  POLICY_DOCKER="$(cd "$TEST_CWD" && "$GENERATOR" --enable=docker)"
  POLICY_KUBECTL="$(cd "$TEST_CWD" && "$GENERATOR" --enable=kubectl)"
  POLICY_MACOS_GUI="$(cd "$TEST_CWD" && "$GENERATOR" --enable=macos-gui)"
  POLICY_ELECTRON="$(cd "$TEST_CWD" && "$GENERATOR" --enable=electron)"

  echo "Generating merged grant policy (repeat flags, colon lists, overlap, spaces, file grants)..."
  POLICY_MERGE="$(cd "$TEST_CWD" && "$GENERATOR" \
    --add-dirs-ro="${TEST_RO_DIR}:${TEST_RO_DIR_2}:${TEST_OVERLAP_DIR}:${TEST_SPACE_DIR}" \
    --add-dirs-ro="$TEST_RO_FILE" \
    --add-dirs="${TEST_RW_DIR}:${TEST_RW_DIR_2}:${TEST_OVERLAP_DIR}:${TEST_SPACE_DIR}" \
    --add-dirs="$TEST_RW_FILE")"

  echo "Generating policy with explicit --workdir=${TEST_RW_DIR}..."
  POLICY_WORKDIR_EXPLICIT="$(cd "$TEST_CWD" && "$GENERATOR" --workdir "$TEST_RW_DIR")"

  echo "Generating policy with --workdir empty (auto grant disabled)..."
  POLICY_WORKDIR_EMPTY="$(cd "$TEST_CWD" && "$GENERATOR" --workdir "")"

  echo "Generating policy with --workdir empty plus extra dirs..."
  POLICY_WORKDIR_EMPTY_EXTRA="$(cd "$TEST_CWD" && "$GENERATOR" --workdir "" --add-dirs-ro="$TEST_RO_DIR" --add-dirs="$TEST_RW_DIR")"

  if command -v git >/dev/null 2>&1; then
    (
      cd "$TEST_GIT_REPO"
      git init -q
    )
    echo "Generating policy from git subdir (auto-detect git root as workdir)..."
    POLICY_GIT_AUTO="$(cd "$TEST_GIT_SUBDIR" && "$GENERATOR")"
  else
    echo "Skipping git-root auto-detect policy generation (git not found)."
    POLICY_GIT_AUTO=""
  fi
}

cleanup_test_environment() {
  rm -rf \
    "$TEST_CWD" \
    "$TEST_RO_DIR" \
    "$TEST_RO_DIR_2" \
    "$TEST_RW_DIR" \
    "$TEST_RW_DIR_2" \
    "$TEST_OVERLAP_DIR" \
    "$TEST_SPACE_PARENT" \
    "$TEST_DENIED_DIR" \
    "$TEST_GIT_REPO"

  rm -f "$TEST_RO_FILE" "$TEST_RW_FILE" "$TEST_TMP_CANARY" "$TEST_HOME_CANARY" "$SAFEHOUSE_OUTPUT_POLICY" "$DRY_RUN_CANARY"

  if [[ -n "${POLICY_DEFAULT:-}" && -f "${POLICY_DEFAULT:-}" ]]; then
    rm -f "$POLICY_DEFAULT"
  fi
  if [[ -n "${POLICY_EXTRA:-}" && -f "${POLICY_EXTRA:-}" ]]; then
    rm -f "$POLICY_EXTRA"
  fi
  if [[ -n "${POLICY_DOCKER:-}" && -f "${POLICY_DOCKER:-}" ]]; then
    rm -f "$POLICY_DOCKER"
  fi
  if [[ -n "${POLICY_KUBECTL:-}" && -f "${POLICY_KUBECTL:-}" ]]; then
    rm -f "$POLICY_KUBECTL"
  fi
  if [[ -n "${POLICY_MACOS_GUI:-}" && -f "${POLICY_MACOS_GUI:-}" ]]; then
    rm -f "$POLICY_MACOS_GUI"
  fi
  if [[ -n "${POLICY_ELECTRON:-}" && -f "${POLICY_ELECTRON:-}" ]]; then
    rm -f "$POLICY_ELECTRON"
  fi
  if [[ -n "${POLICY_MERGE:-}" && -f "${POLICY_MERGE:-}" ]]; then
    rm -f "$POLICY_MERGE"
  fi
  if [[ -n "${POLICY_WORKDIR_EXPLICIT:-}" && -f "${POLICY_WORKDIR_EXPLICIT:-}" ]]; then
    rm -f "$POLICY_WORKDIR_EXPLICIT"
  fi
  if [[ -n "${POLICY_WORKDIR_EMPTY:-}" && -f "${POLICY_WORKDIR_EMPTY:-}" ]]; then
    rm -f "$POLICY_WORKDIR_EMPTY"
  fi
  if [[ -n "${POLICY_WORKDIR_EMPTY_EXTRA:-}" && -f "${POLICY_WORKDIR_EMPTY_EXTRA:-}" ]]; then
    rm -f "$POLICY_WORKDIR_EMPTY_EXTRA"
  fi
  if [[ -n "${POLICY_GIT_AUTO:-}" && -f "${POLICY_GIT_AUTO:-}" ]]; then
    rm -f "$POLICY_GIT_AUTO"
  fi
  if [[ -n "${SAFEHOUSE_DRY_RUN_POLICY:-}" && -f "${SAFEHOUSE_DRY_RUN_POLICY:-}" ]]; then
    rm -f "$SAFEHOUSE_DRY_RUN_POLICY"
  fi
}
