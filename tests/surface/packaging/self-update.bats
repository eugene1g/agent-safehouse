#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

sft_make_install_copy() {
  local target_path="$1"

  cp "$DIST_SAFEHOUSE" "$target_path" || return 1
  chmod 755 "$target_path" || return 1
}

@test "standalone update --help prints subcommand usage" {
  safehouse_run update --help
  [ "$status" -eq 0 ]

  sft_assert_contains "$output" "Usage:"
  sft_assert_contains "$output" "update [--head]"
  sft_assert_contains "$output" "SAFEHOUSE_SELF_UPDATE_URL"
}

@test "repo checkout update fails with source-checkout guidance" {
  run "${SAFEHOUSE_REPO_ROOT}/bin/safehouse.sh" update
  [ "$status" -ne 0 ]

  sft_assert_contains "$output" "safehouse update only supports standalone installed scripts."
  sft_assert_contains "$output" "Current executable appears to be running from a source checkout:"
  sft_assert_contains "$output" "regenerate dist artifacts if needed."
}

# Successful standalone update flows.

@test "standalone update replaces the install from a local override source" {
  local install_path candidate_path

  install_path="$(sft_workspace_path "safehouse-update-install.sh")"
  candidate_path="$(sft_workspace_path "safehouse-update-candidate.sh")"

  sft_make_install_copy "$install_path"
  sft_make_install_copy "$candidate_path"
  printf '\n# safehouse-test-id:self-update-updated\n' >> "$candidate_path"

  run /usr/bin/env SAFEHOUSE_SELF_UPDATE_URL="$candidate_path" "$install_path" update
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Updated "
  cmp -s "$install_path" "$candidate_path"
}

@test "standalone update --head replaces the install from the head source" {
  local install_path candidate_path

  install_path="$(sft_workspace_path "safehouse-update-head.sh")"
  candidate_path="$(sft_workspace_path "safehouse-update-head-candidate.sh")"

  sft_make_install_copy "$install_path"
  sft_make_install_copy "$candidate_path"
  printf '\n# safehouse-test-id:self-update-head\n' >> "$candidate_path"

  run /usr/bin/env SAFEHOUSE_SELF_UPDATE_URL="$candidate_path" "$install_path" update --head
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Updated "
  cmp -s "$install_path" "$candidate_path"
}

@test "standalone update reports already up to date for identical assets" {
  local install_path candidate_path

  install_path="$(sft_workspace_path "safehouse-update-noop.sh")"
  candidate_path="$(sft_workspace_path "safehouse-update-noop-candidate.sh")"

  sft_make_install_copy "$install_path"
  sft_make_install_copy "$candidate_path"

  run /usr/bin/env SAFEHOUSE_SELF_UPDATE_URL="$candidate_path" "$install_path" update
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Already up to date:"
  cmp -s "$install_path" "$candidate_path"
}

# Defensive failure handling for standalone update.

@test "standalone update rejects invalid candidates without replacing the install" {
  local install_path candidate_path baseline

  install_path="$(sft_workspace_path "safehouse-update-invalid.sh")"
  candidate_path="$(sft_workspace_path "safehouse-update-invalid-candidate.sh")"
  baseline="$(sft_workspace_path "safehouse-update-invalid-baseline.sh")"

  sft_make_install_copy "$install_path"
  cp "$install_path" "$baseline"
  cat > "$candidate_path" <<'EOF'
#!/usr/bin/env bash
echo "not-a-safehouse-release"
EOF
  chmod 755 "$candidate_path"

  run /usr/bin/env SAFEHOUSE_SELF_UPDATE_URL="$candidate_path" "$install_path" update
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "Downloaded update candidate does not look like a valid standalone safehouse release asset."
  cmp -s "$install_path" "$baseline"
}

@test "standalone update reports mv failures and cleans temporary files" {
  local install_path candidate_path baseline stub_bin_dir resolved_install
  local -a leaked_files

  install_path="$(sft_workspace_path "safehouse-update-mv-fail.sh")"
  candidate_path="$(sft_workspace_path "safehouse-update-mv-fail-candidate.sh")"
  baseline="$(sft_workspace_path "safehouse-update-mv-fail-baseline.sh")"
  stub_bin_dir="$(sft_workspace_path "safehouse-update-stubs")"
  resolved_install="$(cd "$(dirname "$install_path")" && pwd -P)/$(basename "$install_path")"

  sft_make_install_copy "$install_path"
  sft_make_install_copy "$candidate_path"
  cp "$install_path" "$baseline"
  printf '\n# safehouse-test-id:self-update-mv-fail\n' >> "$candidate_path"

  mkdir -p "$stub_bin_dir"
  cat > "${stub_bin_dir}/mv" <<'EOF'
#!/bin/sh
exit 1
EOF
  chmod 755 "${stub_bin_dir}/mv"

  run /usr/bin/env PATH="${stub_bin_dir}:${PATH:-/usr/bin:/bin:/usr/sbin:/sbin}" SAFEHOUSE_SELF_UPDATE_URL="$candidate_path" "$install_path" update
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "Failed to replace the current safehouse install with the downloaded update."
  sft_assert_contains "$output" "Target: ${resolved_install}"
  cmp -s "$install_path" "$baseline"

  shopt -s nullglob
  leaked_files=("${install_path}".*)
  shopt -u nullglob
  [ "${#leaked_files[@]}" -eq 0 ]
}

@test "standalone update rejects symlinked installs" {
  local target_path symlink_path candidate_path baseline

  target_path="$(sft_workspace_path "safehouse-update-target.sh")"
  symlink_path="$(sft_workspace_path "safehouse-update-symlink.sh")"
  candidate_path="$(sft_workspace_path "safehouse-update-symlink-candidate.sh")"
  baseline="$(sft_workspace_path "safehouse-update-symlink-baseline.sh")"

  sft_make_install_copy "$target_path"
  sft_make_install_copy "$candidate_path"
  cp "$target_path" "$baseline"
  /bin/ln -sf "$target_path" "$symlink_path"

  run /usr/bin/env SAFEHOUSE_SELF_UPDATE_URL="$candidate_path" "$symlink_path" update
  [ "$status" -ne 0 ]
  sft_assert_contains "$output" "safehouse update does not replace symlinked installs"
  sft_assert_contains "$output" "brew upgrade agent-safehouse"
  [ -L "$symlink_path" ]
  cmp -s "$target_path" "$baseline"
}
