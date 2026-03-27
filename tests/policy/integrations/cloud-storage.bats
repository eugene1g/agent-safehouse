#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

# --- Policy-only (structure) tests -------------------------------------------

@test "[POLICY-ONLY] enable=cloud-storage includes the cloud-storage integration layer" {
  #safehouse-test-id:cloud-storage-profile-included#
  local profile

  profile="$(safehouse_profile --enable=cloud-storage)"

  sft_assert_includes_source "$profile" "55-integrations-optional/cloud-storage.sb"
}

@test "[POLICY-ONLY] cloud-storage profile is not included by default" {
  #safehouse-test-id:cloud-storage-not-default#
  local profile

  profile="$(safehouse_profile)"

  sft_assert_omits_source "$profile" "55-integrations-optional/cloud-storage.sb"
}
