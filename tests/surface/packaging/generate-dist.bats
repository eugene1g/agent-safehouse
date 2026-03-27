#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

generate_dist_repo_root() {
  cd "${BATS_TEST_DIRNAME}/../../.." && pwd -P
}

generate_dist_base_fixture_path() {
  printf '%s/generate-dist-fixture\n' "${BATS_FILE_TMPDIR}"
}

fast_copy_tree() {
  local source_path="$1"
  local target_path="$2"

  if cp -cR "$source_path" "$target_path" 2>/dev/null; then
    return 0
  fi

  cp -R "$source_path" "$target_path"
}

copy_generate_dist_fixture() {
  local target_dir="$1"
  local base_fixture

  base_fixture="$(generate_dist_base_fixture_path)"

  mkdir -p "$target_dir"
  fast_copy_tree "${base_fixture}/bin" "${target_dir}/bin"
  fast_copy_tree "${base_fixture}/profiles" "${target_dir}/profiles"
  fast_copy_tree "${base_fixture}/scripts" "${target_dir}/scripts"
  cp "${base_fixture}/VERSION" "${target_dir}/VERSION"
}

setup_file() {
  local repo_root base_fixture

  repo_root="$(generate_dist_repo_root)"
  base_fixture="$(generate_dist_base_fixture_path)"
  rm -rf "${base_fixture}"
  mkdir -p "${base_fixture}"

  cp -RX "${repo_root}/bin" "${base_fixture}/"
  cp -RX "${repo_root}/profiles" "${base_fixture}/"
  cp -RX "${repo_root}/scripts" "${base_fixture}/"
  cp "${repo_root}/VERSION" "${base_fixture}/"
}

teardown_file() {
  local base_fixture

  base_fixture="$(generate_dist_base_fixture_path)"
  if [[ -d "${base_fixture}" ]]; then
    rm -rf "${base_fixture}"
  fi
}

rewrite_file_with_sed() {
  local path="$1"
  local script="$2"
  local tmp_path="${path}.tmp"

  sed "$script" "$path" > "$tmp_path"
  mv "$tmp_path" "$path"
}

@test "generate-dist.sh supports --output for a standalone dist executable" {
  local custom_dist
  custom_dist="$(sft_workspace_path "safehouse-dist.sh")"

  "${SAFEHOUSE_REPO_ROOT}/scripts/generate-dist.sh" --output "$custom_dist"

  [ -x "$custom_dist" ]
  sft_assert_file_contains "$custom_dist" "# Project: https://agent-safehouse.dev"
  sft_assert_file_contains "$custom_dist" "# Embedded Profiles Last Modified (UTC): "
  sft_assert_file_contains "$custom_dist" "SAFEHOUSE_SELF_UPDATE_VALIDATION_MARKER=standalone-release-asset-v1"
  sft_assert_file_not_contains "$custom_dist" "apple-build-tools"
  sft_assert_file_not_contains "$custom_dist" "SAFEHOUSE_CLAUDE_POLICY_URL"

  run "$custom_dist" --stdout --enable=keychain -- /usr/bin/true

  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$(sft_source_marker "55-integrations-optional/keychain.sb")"
}

@test "generate-dist.sh supports --output-dir without recreating deprecated dist artifacts" {
  local output_dir dist_path

  output_dir="$(sft_workspace_path "dist-output")"
  dist_path="${output_dir}/safehouse.sh"

  "${SAFEHOUSE_REPO_ROOT}/scripts/generate-dist.sh" --output-dir "$output_dir"

  [ -x "$dist_path" ]
  [ ! -e "${output_dir}/Claude.app.sandboxed.command" ]
  [ ! -e "${output_dir}/Claude.app.sandboxed-offline.command" ]
  [ ! -e "${output_dir}/profiles" ]
}

@test "generate-dist.sh allows basename fallback when an agent profile omits explicit command metadata" {
  local repo_copy output_dir custom_dist fake_opencode_bin

  repo_copy="$(sft_workspace_path "repo-copy-basename-fallback")"
  output_dir="${repo_copy}/dist-out"
  custom_dist="${output_dir}/safehouse.sh"
  fake_opencode_bin="$(sft_workspace_path "opencode")"
  copy_generate_dist_fixture "$repo_copy"
  sft_assert_file_not_contains "${repo_copy}/profiles/60-agents/opencode.sb" ';; $$command=opencode$$'
  sft_make_fake_command "$fake_opencode_bin"

  run env REPO_COPY="$repo_copy" OUTPUT_DIR="$output_dir" /bin/bash -lc 'cd "$REPO_COPY" || exit 1; ./scripts/generate-dist.sh --output-dir "$OUTPUT_DIR"'

  [ "$status" -eq 0 ]
  [ -x "$custom_dist" ]

  run "$custom_dist" --stdout -- "$fake_opencode_bin"

  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$(sft_source_marker "60-agents/opencode.sb")"
}

@test "generate-dist.sh fails when an agent profile declares duplicate command aliases" {
  local repo_copy output_dir

  repo_copy="$(sft_workspace_path "repo-copy-duplicate-command")"
  output_dir="${repo_copy}/dist-out"
  copy_generate_dist_fixture "$repo_copy"
  rewrite_file_with_sed "${repo_copy}/profiles/60-agents/copilot-cli.sb" 's/^;; \$\$command=copilot,copilot-cli\$\$$/;; $$command=copilot,copilot$$/'
  sft_assert_file_contains "${repo_copy}/profiles/60-agents/copilot-cli.sb" ';; $$command=copilot,copilot$$'

  run env REPO_COPY="$repo_copy" OUTPUT_DIR="$output_dir" /bin/bash -lc 'cd "$REPO_COPY" || exit 1; ./scripts/generate-dist.sh --output-dir "$OUTPUT_DIR"'

  [ "$status" -ne 0 ]
  sft_assert_contains "$output" 'Agent profile profiles/60-agents/copilot-cli.sb declares duplicate $$command alias: copilot'
}

@test "generate-dist.sh fails when two agent profiles declare the same command alias" {
  local repo_copy output_dir

  repo_copy="$(sft_workspace_path "repo-copy-conflicting-command")"
  output_dir="${repo_copy}/dist-out"
  copy_generate_dist_fixture "$repo_copy"
  rewrite_file_with_sed "${repo_copy}/profiles/60-agents/claude-code.sb" 's/^;; \$\$command=claude,claude-code\$\$$/;; $$command=copilot$$/'
  sft_assert_file_contains "${repo_copy}/profiles/60-agents/claude-code.sb" ';; $$command=copilot$$'

  run env REPO_COPY="$repo_copy" OUTPUT_DIR="$output_dir" /bin/bash -lc 'cd "$REPO_COPY" || exit 1; ./scripts/generate-dist.sh --output-dir "$OUTPUT_DIR"'

  [ "$status" -ne 0 ]
  sft_assert_contains "$output" 'Command alias copilot is declared by multiple agent profiles: profiles/60-agents/claude-code.sb, profiles/60-agents/copilot-cli.sb'
}
