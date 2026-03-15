#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "tilde expansion works for add-dirs, workdir, append-profile, and env files" {
  local fake_home ro_dir rw_dir workdir append_file env_file profile
  local ro_rel rw_rel workdir_rel

  fake_home="$(sft_fake_home)" || return 1
  ro_dir="${fake_home}/.safehouse-tilde-ro"
  rw_dir="${fake_home}/.safehouse-tilde-rw"
  workdir="${fake_home}/.safehouse-tilde-workdir"
  append_file="${fake_home}/.safehouse-tilde-append.sb"
  env_file="${fake_home}/.safehouse-tilde-env"
  mkdir -p "$ro_dir" "$rw_dir" "$workdir"
  printf '%s\n' ';; #safehouse-test-id:append-profile-tilde#' > "$append_file"
  printf '%s\n' 'SAFEHOUSE_TEST_SECRET=tilde-secret' > "$env_file"

  ro_rel="${ro_dir#"${fake_home}/"}"
  rw_rel="${rw_dir#"${fake_home}/"}"
  workdir_rel="${workdir#"${fake_home}/"}"

  profile="$(HOME="$fake_home" safehouse_profile \
    --add-dirs-ro="~/${ro_rel}" \
    --add-dirs="~/${rw_rel}" \
    --workdir="~/${workdir_rel}" \
    --append-profile="~/.safehouse-tilde-append.sb")"

  sft_assert_contains "$profile" "(subpath \"${ro_dir}\")"
  sft_assert_contains "$profile" "file-read* file-write* (subpath \"${rw_dir}\")"
  sft_assert_contains "$profile" "(subpath \"${workdir}\")"
  sft_assert_contains "$profile" "#safehouse-test-id:append-profile-tilde#"

  HOME="$fake_home" safehouse_ok --env="~/.safehouse-tilde-env" -- /bin/sh -c '[ "${SAFEHOUSE_TEST_SECRET:-}" = "tilde-secret" ]'
}

@test "[POLICY-ONLY] trusted workdir config expands tilde values" {
  local fake_home fake_project ro_dir rw_dir profile
  local ro_rel rw_rel

  fake_home="$(sft_fake_home)" || return 1
  fake_project="$(sft_workspace_path "tilde-config-project")"
  ro_dir="${fake_home}/.safehouse-tilde-config-ro"
  rw_dir="${fake_home}/.safehouse-tilde-config-rw"
  mkdir -p "$fake_project" "$ro_dir" "$rw_dir"
  ro_rel="${ro_dir#"${fake_home}/"}"
  rw_rel="${rw_dir#"${fake_home}/"}"

  cat > "${fake_project}/.safehouse" <<EOF
add-dirs-ro=~/${ro_rel}
add-dirs=~/${rw_rel}
EOF

  profile="$(HOME="$fake_home" safehouse_profile_in_dir "$fake_project" --trust-workdir-config)"

  sft_assert_contains "$profile" "(subpath \"${ro_dir}\")"
  sft_assert_contains "$profile" "file-read* file-write* (subpath \"${rw_dir}\")"
}
