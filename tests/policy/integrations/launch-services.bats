#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

# Launch Services is opt-in because `lsd`/`launchd` start the handler outside the
# sandbox, with the user's full privileges.

@test "[POLICY-ONLY] default profile grants no lsopen and omits the launch-services source" {
  local profile

  profile="$(safehouse_profile)"

  sft_assert_omits_source "$profile" "55-integrations-optional/launch-services.sb"
  sft_assert_not_contains "$profile" "(allow lsopen)"
}

@test "[POLICY-ONLY] enable=launch-services adds the lsopen grant without pulling in macos-gui" {
  local profile

  profile="$(safehouse_profile --enable=launch-services)"

  sft_assert_includes_source "$profile" "55-integrations-optional/launch-services.sb"
  sft_assert_contains "$profile" "(allow lsopen)"
  sft_assert_omits_source "$profile" "55-integrations-optional/macos-gui.sb"
}

@test "[POLICY-ONLY] no agent or app profile pulls launch-services back in by default" {
  local profile

  profile="$(safehouse_profile --enable=all-agents,all-apps)"

  sft_assert_omits_source "$profile" "55-integrations-optional/launch-services.sb"
  sft_assert_not_contains "$profile" "(allow lsopen)"
}

# NOTE: This EXECUTION test checks only the denial. Testing the allow direction
#       would leave a GUI application running outside the sandbox with no way to
#       clean it up, so the allow case is covered by the POLICY-ONLY tests above.
@test "[EXECUTION] open cannot reach Launch Services without enable=launch-services" {
  local target

  target="$(sft_external_path "launch-services" "note.txt")" || return 1
  printf '%s\n' "hello" > "$target"

  safehouse_denied \
    --workdir '' \
    --add-dirs-ro "$target" \
    -- /usr/bin/open "$target"
}
