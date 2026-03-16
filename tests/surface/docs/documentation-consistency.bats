#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "plain-text LLM instructions do not reference the deprecated workdir placeholder flow" {
  local instructions_path

  instructions_path="${SAFEHOUSE_REPO_ROOT}/docs/public/llm-instructions.txt"

  sft_assert_file_not_contains "$instructions_path" "__WORKDIR_BLOCK_START__"
  sft_assert_file_not_contains "$instructions_path" "Use `sed` to replace `__SAFEHOUSE_WORKDIR__`"
  sft_assert_file_contains "$instructions_path" "Do not invent placeholder tokens such as"
}

@test "getting-started docs do not contain unresolved release placeholders and prefer selective env passthrough in wrappers" {
  local getting_started_path

  getting_started_path="${SAFEHOUSE_REPO_ROOT}/docs/docs/getting-started.md"

  sft_assert_file_not_contains "$getting_started_path" "__SAFEHOUSE_RELEASE_RAW_DIST_BASE_URL__"
  sft_assert_file_contains "$getting_started_path" 'opencode() { OPENCODE_PERMISSION='
  sft_assert_file_contains "$getting_started_path" 'safekeys opencode'
  sft_assert_file_contains "$getting_started_path" 'safekeys gemini --yolo'
}

@test "docs do not mention the unsupported forbidden-exec-sugid marker" {
  local overview_path assumptions_path

  overview_path="${SAFEHOUSE_REPO_ROOT}/docs/docs/overview.md"
  assumptions_path="${SAFEHOUSE_REPO_ROOT}/docs/docs/default-assumptions.md"

  sft_assert_file_not_contains "$overview_path" "forbidden-exec-sugid"
  sft_assert_file_not_contains "$assumptions_path" "forbidden-exec-sugid"
}

@test "docs explain HOME_DIR as narrow home-relative access, not broad home reads" {
  local readme_path assumptions_path architecture_path usage_path

  readme_path="${SAFEHOUSE_REPO_ROOT}/README.md"
  assumptions_path="${SAFEHOUSE_REPO_ROOT}/docs/docs/default-assumptions.md"
  architecture_path="${SAFEHOUSE_REPO_ROOT}/docs/docs/policy-architecture.md"
  usage_path="${SAFEHOUSE_REPO_ROOT}/docs/docs/usage.md"

  sft_assert_file_contains "$readme_path" "does not grant recursive read access to your home directory"
  sft_assert_file_contains "$assumptions_path" 'Directory-root reads for `~/.config` and `~/.cache`'
  sft_assert_file_contains "$architecture_path" 'It is not a blanket grant for `$HOME`.'
  sft_assert_file_contains "$usage_path" 'So `stat "$HOME"` can succeed while `ls "$HOME"` and `cat ~/secret.txt` still fail unless another rule grants the path.'
}

@test "docs feature lists cover the runtime-supported enable catalog" {
  local options_path assumptions_path
  local supported_csv raw_feature feature
  local -a raw_features=()

  options_path="${SAFEHOUSE_REPO_ROOT}/docs/docs/options.md"
  assumptions_path="${SAFEHOUSE_REPO_ROOT}/docs/docs/default-assumptions.md"

  safehouse_run --help
  [ "$status" -eq 0 ]

  supported_csv="$(awk -F'Supported values: ' 'index($0, "Supported values: ") { print $2; exit }' <<<"$output")"
  [ -n "$supported_csv" ]

  IFS=',' read -r -a raw_features <<<"$supported_csv"
  for raw_feature in "${raw_features[@]}"; do
    feature="$(printf '%s\n' "$raw_feature" | xargs)"
    [[ -n "$feature" ]] || continue
    sft_assert_file_contains "$options_path" "\`${feature}\`"
    sft_assert_file_contains "$assumptions_path" "\`${feature}\`"
  done
}
