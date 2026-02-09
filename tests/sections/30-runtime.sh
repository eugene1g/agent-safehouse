#!/usr/bin/env bash

run_section_runtime() {
  section_begin "System Runtime"
  assert_allowed "$POLICY_DEFAULT" "read /usr/bin" /bin/ls /usr/bin
  assert_allowed_if_exists "$POLICY_DEFAULT" "read /opt (Homebrew)" "/opt" /bin/ls /opt
  assert_allowed "$POLICY_DEFAULT" "read system frameworks" /bin/ls /System/Library/Frameworks
  assert_allowed "$POLICY_DEFAULT" "read /dev/null" /bin/cat /dev/null
  assert_allowed "$POLICY_DEFAULT" "read /dev/urandom (1 byte)" /bin/dd if=/dev/urandom bs=1 count=1
  assert_allowed "$POLICY_DEFAULT" "read /tmp" /bin/ls /tmp
  assert_allowed_strict "$POLICY_DEFAULT" "write to /tmp" /usr/bin/touch "$TEST_TMP_CANARY"
  assert_allowed "$POLICY_DEFAULT" "read shell startup (/etc/zshrc)" /bin/cat /private/etc/zshrc

  section_begin "Clipboard"
  assert_allowed_if_exists "$POLICY_DEFAULT" "pbcopy" "pbcopy" /bin/sh -c 'echo safehouse-test | /usr/bin/pbcopy'

  section_begin "Network"
  assert_allowed_strict "$POLICY_DEFAULT" "outbound HTTPS (curl example.com)" /usr/bin/curl -sf --max-time 5 https://example.com

  section_begin "Process Execution"
  assert_allowed "$POLICY_DEFAULT" "fork + exec (sh -c echo)" /bin/sh -c 'echo sandbox-ok'
  assert_allowed "$POLICY_DEFAULT" "nested subprocesses (sh > sh > echo)" /bin/sh -c '/bin/sh -c "echo nested-ok"'
}

register_section run_section_runtime
