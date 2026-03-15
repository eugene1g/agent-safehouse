#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "[POLICY-ONLY] direct .app command paths get a read-only app bundle grant" {
  local app_dir app_bin profile resolved_app_dir

  app_dir="$(sft_workspace_path "FakeApp.app")"
  app_bin="${app_dir}/Contents/MacOS/fake-binary"

  sft_make_fake_command "$app_bin"
  profile="$(safehouse_profile -- "$app_bin")"
  resolved_app_dir="$(cd "$app_dir" && pwd -P)"

  sft_assert_contains "$profile" "(subpath \"${resolved_app_dir}\")"
  sft_assert_contains "$profile" "file-read*"
}

@test "[POLICY-ONLY] PATH lookup also applies app bundle detection, while non-app commands do not" {
  local app_dir app_bin app_cmd app_profile non_app_cmd non_app_profile resolved_app_dir

  app_dir="$(sft_workspace_path "LookupApp.app")"
  app_bin="${app_dir}/Contents/MacOS/lookup-binary"
  app_cmd="$(sft_workspace_path "lookup-app-cmd")"
  non_app_cmd="$(sft_workspace_path "plain-cmd")"

  sft_make_fake_command "$app_bin"
  sft_make_fake_command "$non_app_cmd"
  /bin/ln -sf "$app_bin" "$app_cmd"
  resolved_app_dir="$(cd "$app_dir" && pwd -P)"

  app_profile="$(PATH="${SAFEHOUSE_WORKSPACE}:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" safehouse_profile_in_dir "$SAFEHOUSE_WORKSPACE" -- lookup-app-cmd)"
  non_app_profile="$(safehouse_profile -- "$non_app_cmd")"

  sft_assert_contains "$app_profile" "(subpath \"${resolved_app_dir}\")"
  sft_assert_not_contains "$non_app_profile" "LookupApp.app"
}
