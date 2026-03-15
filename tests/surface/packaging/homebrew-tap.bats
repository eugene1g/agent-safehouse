#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

sft_write_publish_homebrew_tap_stubs() {
  local stub_bin="$1"

  cat > "${stub_bin}/gh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

if [[ "$#" -ge 3 && "$1" == "release" && "$2" == "view" ]]; then
  cat <<'EOF_JSON'
{"isDraft":false,"url":"https://github.com/example/agent-safehouse/releases/tag/v1.2.3","assets":[{"name":"safehouse.sh"}]}
EOF_JSON
  exit 0
fi

echo "unexpected gh invocation: $*" >&2
exit 1
EOF

  cat > "${stub_bin}/jq" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

cat >/dev/null
expr="${*: -1}"

case "$expr" in
  ".isDraft")
    printf "false\n"
    ;;
  ".assets | length")
    printf "1\n"
    ;;
  "[.assets[] | select(.name == \"safehouse.sh\")] | length")
    printf "1\n"
    ;;
  ".assets[] | select(.name == \"safehouse.sh\") | .name")
    printf "safehouse.sh\n"
    ;;
  ".url")
    printf "https://github.com/example/agent-safehouse/releases/tag/v1.2.3\n"
    ;;
  *)
    echo "unexpected jq invocation: $*" >&2
    exit 1
    ;;
esac
EOF

  cat > "${stub_bin}/curl" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

output_path=""
while [[ "$#" -gt 0 ]]; do
  case "$1" in
    -o)
      output_path="$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done

[[ -n "$output_path" ]] || {
  echo "curl stub expected -o PATH" >&2
  exit 1
}

cp "$SAFEHOUSE_FAKE_ASSET" "$output_path"
EOF

  chmod 755 "${stub_bin}/gh" "${stub_bin}/jq" "${stub_bin}/curl"
}

@test "publish-homebrew-tap installs dist/safehouse.sh for HEAD builds" {
  local test_root tap_dir stub_bin fake_asset formula_path

  test_root="$(sft_workspace_path "homebrew-test")"
  tap_dir="${test_root}/homebrew-safehouse"
  stub_bin="${test_root}/stubs"
  fake_asset="${test_root}/safehouse.sh"
  formula_path="${tap_dir}/Formula/agent-safehouse.rb"

  mkdir -p "$tap_dir" "$stub_bin"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$fake_asset"
  chmod 755 "$fake_asset"

  git init -q "$tap_dir"
  git -C "$tap_dir" config user.name "Safehouse Test"
  git -C "$tap_dir" config user.email "safehouse-test@example.com"
  git -C "$tap_dir" remote add origin "https://github.com/example/homebrew-safehouse.git"

  sft_write_publish_homebrew_tap_stubs "$stub_bin"

  PATH="${stub_bin}:/usr/bin:/bin:/usr/sbin:/sbin" \
  SAFEHOUSE_FAKE_ASSET="$fake_asset" \
    "${SAFEHOUSE_REPO_ROOT}/scripts/publish-homebrew-tap.sh" \
    1.2.3 \
    --tap-dir "$tap_dir" \
    --tap-repo "example/homebrew-safehouse" \
    --main-repo "example/agent-safehouse"

  sft_assert_file_contains "$formula_path" 'url "https://github.com/example/agent-safehouse/releases/download/v1.2.3/safehouse.sh"'
  sft_assert_file_contains "$formula_path" 'head "https://github.com/example/agent-safehouse.git", branch: "main"'
  sft_assert_file_contains "$formula_path" 'artifact_path = build.head? ? "dist/safehouse.sh" : "safehouse.sh"'
  sft_assert_file_contains "$formula_path" 'bin.install artifact_path => "safehouse"'
  sft_assert_file_not_contains "$formula_path" 'bin.install "safehouse.sh" => "safehouse"'
  git -C "$tap_dir" rev-parse HEAD >/dev/null
}
