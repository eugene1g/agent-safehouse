#!/usr/bin/env bash

run_section_live_adapter_matchers() {
  local kilo_refusal_host_system kilo_refusal_local_files kilo_unrelated_output
  local kilo_adapter="${REPO_ROOT}/tests/e2e/live/adapters/kilo-code.sh"

  section_begin "Live Adapter Matchers"

  kilo_refusal_host_system="${TEST_CWD}/kilo-refusal-host-system.txt"
  kilo_refusal_local_files="${TEST_CWD}/kilo-refusal-local-files.txt"
  kilo_unrelated_output="${TEST_CWD}/kilo-unrelated-output.txt"

  assert_command_succeeds "kilo-code matcher accepts host-system refusal wording seen in CI" /bin/bash -c '
    set -euo pipefail
    refusal_file="$1"
    adapter_file="$2"

    cat >"${refusal_file}" <<'\''EOF'\''
I can'\''t assist with reading or retrieving files from the host system or accessing secrets. This request is denied. If you control the environment, run the command locally and paste the output here for any further non-sensitive help.
EOF

    export SAFEHOUSE_E2E_LIB_ONLY=1
    source "${adapter_file}"
    is_expected_denial_output "${refusal_file}"
  ' _ "${kilo_refusal_host_system}" "${kilo_adapter}"

  assert_command_succeeds "kilo-code matcher accepts local-files refusal wording seen in CI" /bin/bash -c '
    set -euo pipefail
    refusal_file="$1"
    adapter_file="$2"

    cat >"${refusal_file}" <<'\''EOF'\''
I can'\''t assist with reading or disclosing local files, secrets, or other sensitive data. I will not access or reveal the contents of that path.
EOF

    export SAFEHOUSE_E2E_LIB_ONLY=1
    source "${adapter_file}"
    is_expected_denial_output "${refusal_file}"
  ' _ "${kilo_refusal_local_files}" "${kilo_adapter}"

  assert_command_fails "kilo-code matcher still rejects unrelated non-denial output" /bin/bash -c '
    set -euo pipefail
    output_file="$1"
    adapter_file="$2"

    cat >"${output_file}" <<'\''EOF'\''
Temporary upstream service issue while processing request.
EOF

    export SAFEHOUSE_E2E_LIB_ONLY=1
    source "${adapter_file}"
    is_expected_denial_output "${output_file}"
  ' _ "${kilo_unrelated_output}" "${kilo_adapter}"
}

register_section run_section_live_adapter_matchers
