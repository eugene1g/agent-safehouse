#!/usr/bin/env bats
# bats file_tags=suite:policy

load ../../test_helper.bash

sft_setup_grant_merge_fixture() {
  grant_merge_ro_dir="$(sft_external_dir "merge-ro")" || return 1
  grant_merge_ro_dir2="$(sft_external_dir "merge-ro2")" || return 1
  grant_merge_rw_dir="$(sft_external_dir "merge-rw")" || return 1
  grant_merge_overlap_dir="$(sft_external_dir "merge-overlap")" || return 1
  grant_merge_space_parent="$(sft_external_dir "merge-space-parent")" || return 1
  grant_merge_space_dir="${grant_merge_space_parent}/dir with space"
  grant_merge_ro_file_dir="$(sft_external_dir "merge-ro-file")" || return 1
  grant_merge_rw_file_dir="$(sft_external_dir "merge-rw-file")" || return 1
  grant_merge_ro_file_path="${grant_merge_ro_file_dir}/read-only.txt"
  grant_merge_rw_file_path="${grant_merge_rw_file_dir}/read-write.txt"

  mkdir -p "$grant_merge_space_dir" || return 1
  printf '%s\n' "ro-two" > "${grant_merge_ro_dir2}/readable2.txt"
  printf '%s\n' "ro-file" > "$grant_merge_ro_file_path"
  printf '%s\n' "rw-file" > "$grant_merge_rw_file_path"

  grant_merge_args=(
    --workdir ''
    --add-dirs-ro "${grant_merge_ro_dir}:${grant_merge_ro_dir2}:${grant_merge_overlap_dir}:${grant_merge_space_dir}"
    --add-dirs-ro "$grant_merge_ro_file_path"
    --add-dirs "${grant_merge_rw_dir}:${grant_merge_overlap_dir}:${grant_merge_space_dir}"
    --add-dirs "$grant_merge_rw_file_path"
  )
}

@test "[EXECUTION] directory grants keep read-only and read-write semantics separate" {
  sft_setup_grant_merge_fixture || return 1

  safehouse_ok "${grant_merge_args[@]}" -- /bin/cat "${grant_merge_ro_dir2}/readable2.txt" >/dev/null

  safehouse_denied "${grant_merge_args[@]}" -- /usr/bin/touch "${grant_merge_ro_dir2}/should-fail.txt"
  sft_assert_path_absent "${grant_merge_ro_dir2}/should-fail.txt"

  safehouse_ok "${grant_merge_args[@]}" -- /usr/bin/touch "${grant_merge_rw_dir}/should-succeed.txt"
  sft_assert_file_exists "${grant_merge_rw_dir}/should-succeed.txt"
}

@test "[EXECUTION] overlap and spaces in granted directory paths still preserve write access" {
  sft_setup_grant_merge_fixture || return 1

  safehouse_ok "${grant_merge_args[@]}" -- /usr/bin/touch "${grant_merge_space_dir}/space-write-ok.txt"
  sft_assert_file_exists "${grant_merge_space_dir}/space-write-ok.txt"

  safehouse_ok "${grant_merge_args[@]}" -- /usr/bin/touch "${grant_merge_overlap_dir}/overlap-write-ok.txt"
  sft_assert_file_exists "${grant_merge_overlap_dir}/overlap-write-ok.txt"
}

@test "[EXECUTION] file-level grants preserve read-only and read-write behavior" {
  sft_setup_grant_merge_fixture || return 1

  safehouse_ok "${grant_merge_args[@]}" -- /bin/cat "$grant_merge_ro_file_path" >/dev/null
  safehouse_denied "${grant_merge_args[@]}" -- /bin/sh -c "echo denied >> '$grant_merge_ro_file_path'"

  safehouse_ok "${grant_merge_args[@]}" -- /bin/sh -c "echo allowed >> '$grant_merge_rw_file_path'"
}
