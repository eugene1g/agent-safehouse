#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=spotlight includes its optional profile source" {
  local profile
  profile="$(safehouse_profile --enable=spotlight)"

  sft_assert_includes_source "$profile" "55-integrations-optional/spotlight.sb"
}

@test "[EXECUTION] mdls metadata queries require enable=spotlight" {
  local metadata_file

  metadata_file="$(sft_external_path "spotlight" "note.txt")" || return 1
  printf '%s\n' "hello" > "$metadata_file"

  /usr/bin/mdls -name kMDItemFSName "$metadata_file" >/dev/null 2>&1 || skip "mdls precheck failed outside sandbox"

  safehouse_denied \
    --workdir '' \
    --add-dirs-ro "$metadata_file" \
    -- /usr/bin/mdls -name kMDItemFSName "$metadata_file"

  safehouse_ok \
    --workdir '' \
    --add-dirs-ro "$metadata_file" \
    --enable=spotlight \
    -- /usr/bin/mdls -name kMDItemFSName "$metadata_file" >/dev/null
}
