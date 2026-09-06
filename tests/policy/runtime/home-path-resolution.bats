#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

@test "[EXECUTION] batched home aliases preserve writable, read-only, and sibling boundaries for agents" {
  local agent fake_home target_root state_dir prefs_path sibling_path home_prefs fake_command
  local source_policy dist_policy policy_file

  for agent in codex claude; do
    fake_home="$(mktemp -d "${SAFEHOUSE_FAKE_HOME_ROOT}/${agent}.XXXXXX")"
    target_root="$(sft_external_dir "${agent}-home-targets")"
    state_dir="${target_root}/state-with-\"quote\"-and-\\-backslash"
    prefs_path="${target_root}/preferences.json"
    sibling_path="${target_root}/unrelated.txt"
    mkdir -p "$state_dir"
    printf '%s\n' state-readable > "${state_dir}/existing.txt"
    printf '%s\n' preferences-readable > "$prefs_path"
    printf '%s\n' private-sibling > "$sibling_path"
    ln -s "$state_dir" "${fake_home}/.${agent}"
    if [[ "$agent" == codex ]]; then
      home_prefs="${fake_home}/Library/Preferences/com.openai.codex.plist"
    else
      home_prefs="${fake_home}/Library/Application Support/Claude/claude_desktop_config.json"
    fi
    mkdir -p "$(dirname "$home_prefs")"
    ln -s "$prefs_path" "$home_prefs"
    fake_command="$(sft_workspace_path "$agent")"
    sft_make_fake_command "$fake_command"

    source_policy="$(HOME="$fake_home" "${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" --stdout --workdir='' -- "$fake_command")"
    dist_policy="$(HOME="$fake_home" safehouse_profile --workdir='' -- "$fake_command")"
    [ "$source_policy" = "$dist_policy" ]
    policy_file="$(sft_workspace_path "${agent}.sb")"
    printf '%s\n' "$dist_policy" > "$policy_file"

    run sandbox-exec -f "$policy_file" -- /bin/cat "${state_dir}/existing.txt"
    [ "$status" -eq 0 ]
    [ "$output" = state-readable ]
    run sandbox-exec -f "$policy_file" -- /bin/sh -c 'printf "%s\n" created > "$1"' _ "${state_dir}/created.txt"
    [ "$status" -eq 0 ]
    sft_assert_file_contains "${state_dir}/created.txt" created
    run sandbox-exec -f "$policy_file" -- /bin/cat "$prefs_path"
    [ "$status" -eq 0 ]
    [ "$output" = preferences-readable ]
    run sandbox-exec -f "$policy_file" -- /bin/sh -c 'printf "%s\n" overwritten > "$1"' _ "$prefs_path"
    [ "$status" -ne 0 ]
    sft_assert_file_contains "$prefs_path" preferences-readable
    run sandbox-exec -f "$policy_file" -- /bin/cat "$sibling_path"
    [ "$status" -ne 0 ]
  done
}

@test "[EXECUTION] new launches follow changed HOME and symlinks without retaining old target access" {
  local home_one home_two target_one target_two fake_command policy policy_file selected_home

  home_one="${HOME}"
  home_two="$(mktemp -d "${SAFEHOUSE_FAKE_HOME_ROOT}/other-home.XXXXXX")"
  target_one="$(sft_external_dir first-home-target)"
  target_two="$(sft_external_dir second-home-target)"
  printf '%s\n' first > "${target_one}/state.txt"
  printf '%s\n' second > "${target_two}/state.txt"
  ln -s "$target_one" "${home_one}/.codex"
  ln -s "$target_two" "${home_two}/.codex"
  fake_command="$(sft_workspace_path codex)"
  sft_make_fake_command "$fake_command"
  policy_file="$(sft_workspace_path home-change.sb)"

  for selected_home in "$home_one" "$home_two"; do
    policy="$(HOME="$selected_home" safehouse_profile --workdir='' -- "$fake_command")"
    printf '%s\n' "$policy" > "$policy_file"
    if [[ "$selected_home" == "$home_one" ]]; then
      run sandbox-exec -f "$policy_file" -- /bin/cat "${target_one}/state.txt"
      [ "$status" -eq 0 ]
      run sandbox-exec -f "$policy_file" -- /bin/cat "${target_two}/state.txt"
      [ "$status" -ne 0 ]
    else
      run sandbox-exec -f "$policy_file" -- /bin/cat "${target_two}/state.txt"
      [ "$status" -eq 0 ]
      run sandbox-exec -f "$policy_file" -- /bin/cat "${target_one}/state.txt"
      [ "$status" -ne 0 ]
    fi
  done

  ln -sfn "$target_one" "${home_two}/.codex"
  policy="$(HOME="$home_two" safehouse_profile --workdir='' -- "$fake_command")"
  printf '%s\n' "$policy" > "$policy_file"
  run sandbox-exec -f "$policy_file" -- /bin/cat "${target_one}/state.txt"
  [ "$status" -eq 0 ]
  run sandbox-exec -f "$policy_file" -- /bin/cat "${target_two}/state.txt"
  [ "$status" -ne 0 ]
}
