#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[POLICY-ONLY] enable=gpu adds GPU grants without GUI or Electron integrations" {
  local profile gpu_section

  profile="$(safehouse_profile --enable=gpu)"

  sft_assert_includes_source "$profile" "55-integrations-optional/gpu.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/macos-gui.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/electron.sb"
  sft_assert_omits_source "$profile" "55-integrations-optional/chromium-headless.sb"

  gpu_section="$(sft_profile_source_section "$profile" "55-integrations-optional/gpu.sb")"
  sft_assert_contains "$gpu_section" '(global-name "com.apple.MTLCompilerService")'
  sft_assert_contains "$gpu_section" '(global-name "com.apple.SafariPlatformSupport.Helper")'
  sft_assert_contains "$gpu_section" '(iokit-user-client-class "IOSurfaceRootUserClient")'
  sft_assert_contains "$gpu_section" '(iokit-user-client-class "AGXDeviceUserClient")'
  sft_assert_contains "$gpu_section" '(literal "/private/var/db/.AppleSetupDone")'
}

@test "[POLICY-ONLY] electron and chromium-headless keep GPU grants via the shared gpu integration" {
  local electron_profile headless_profile

  electron_profile="$(safehouse_profile --enable=electron)"
  headless_profile="$(safehouse_profile --enable=chromium-headless)"

  sft_assert_includes_source "$electron_profile" "55-integrations-optional/gpu.sb"
  sft_assert_includes_source "$headless_profile" "55-integrations-optional/gpu.sb"
  sft_assert_contains "$electron_profile" '(iokit-user-client-class "AGXDeviceUserClient")'
  sft_assert_contains "$headless_profile" '(iokit-user-client-class "AGXDeviceUserClient")'
}
