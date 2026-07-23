#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] codex grants narrow read access to ChatGPT-bundled node_repl resources" {
  local profile codex_section

  profile="$(safehouse_profile -- codex)"
  codex_section="$(sft_profile_source_section "$profile" "60-agents/codex.sb")"

  sft_assert_contains "$codex_section" '(allow file-read*
    (subpath "/Applications/ChatGPT.app/Contents/Resources/cua_node")
    (literal "/Applications/ChatGPT.app/Contents/Resources/codex")
)'
  sft_assert_not_contains "$codex_section" '(subpath "/Applications/ChatGPT.app")'
  sft_assert_not_contains "$codex_section" '(subpath "/Applications")'
}
