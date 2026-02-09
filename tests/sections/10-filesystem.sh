#!/usr/bin/env bash

run_section_filesystem() {
  section_begin "Default Workdir Access (No Git Root)"
  assert_allowed "$POLICY_DEFAULT" "write and read file in CWD" /bin/sh -c "echo hello > '${TEST_CWD}/testfile' && cat '${TEST_CWD}/testfile'"
  assert_allowed "$POLICY_DEFAULT" "create file in CWD" /usr/bin/touch "${TEST_CWD}/newfile"
  assert_allowed "$POLICY_DEFAULT" "create directory in CWD" /bin/mkdir "${TEST_CWD}/newdir"

  section_begin "Denied Writes Outside Default Workdir"
  assert_denied_strict "$POLICY_DEFAULT" "write to HOME root" /usr/bin/touch "$TEST_HOME_CANARY"
  assert_denied_strict "$POLICY_DEFAULT" "write to HOME directory outside grants" /usr/bin/touch "${TEST_DENIED_DIR}/blocked.txt"

  section_begin "Extra Directory Grants"
  assert_allowed_strict "$POLICY_EXTRA" "read from --add-dirs-ro path" /bin/cat "${TEST_RO_DIR}/readable.txt"
  assert_denied_strict "$POLICY_EXTRA" "write to --add-dirs-ro path" /usr/bin/touch "${TEST_RO_DIR}/should-fail.txt"
  assert_allowed_strict "$POLICY_EXTRA" "read from --add-dirs path" /bin/cat "${TEST_RW_DIR}/writable.txt"
  assert_allowed_strict "$POLICY_EXTRA" "write to --add-dirs path" /usr/bin/touch "${TEST_RW_DIR}/should-succeed.txt"

  section_begin "Explicit --workdir"
  assert_allowed_strict "$POLICY_WORKDIR_EXPLICIT" "write to explicit --workdir path" /usr/bin/touch "${TEST_RW_DIR}/explicit-workdir-ok.txt"
  assert_denied_strict "$POLICY_WORKDIR_EXPLICIT" "HOME path outside explicit --workdir remains denied" /usr/bin/touch "${TEST_DENIED_DIR}/explicit-workdir-blocked.txt"

  section_begin "Empty --workdir"
  assert_denied_strict "$POLICY_WORKDIR_EMPTY" "empty --workdir disables automatic CWD access" /usr/bin/touch "${TEST_CWD}/workdir-empty-blocked.txt"
  assert_allowed_strict "$POLICY_WORKDIR_EMPTY_EXTRA" "read from --add-dirs-ro path when auto-workdir is disabled" /bin/cat "${TEST_RO_DIR}/readable.txt"
  assert_denied_strict "$POLICY_WORKDIR_EMPTY_EXTRA" "write to --add-dirs-ro path when auto-workdir is disabled" /usr/bin/touch "${TEST_RO_DIR}/workdir-empty-ro-blocked.txt"
  assert_allowed_strict "$POLICY_WORKDIR_EMPTY_EXTRA" "write to --add-dirs path when auto-workdir is disabled" /usr/bin/touch "${TEST_RW_DIR}/workdir-empty-rw-ok.txt"

  section_begin "Git Root Auto-Detection"
  if [[ -n "${POLICY_GIT_AUTO:-}" ]]; then
    assert_allowed_strict "$POLICY_GIT_AUTO" "missing --workdir uses git root when invoked from nested repo path" /usr/bin/touch "${TEST_GIT_REPO}/git-root-ok.txt"
    assert_allowed_strict "$POLICY_GIT_AUTO" "nested path remains writable via detected git root workdir" /usr/bin/touch "${TEST_GIT_SUBDIR}/git-subdir-ok.txt"
    assert_denied_strict "$POLICY_GIT_AUTO" "HOME path outside detected git workdir remains denied" /usr/bin/touch "${TEST_DENIED_DIR}/git-workdir-blocked.txt"
  else
    log_skip "missing --workdir uses git root when invoked from nested repo path (git not found)"
    log_skip "nested path remains writable via detected git root workdir (git not found)"
    log_skip "paths outside detected git workdir remain denied (git not found)"
  fi
}

register_section run_section_filesystem
