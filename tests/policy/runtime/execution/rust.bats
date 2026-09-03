#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the Rust/Cargo toolchain profile (profiles/30-toolchains/rust.sb).
# Verifies real cargo operations behave as intended under the default sandbox:
# using an already-installed global binary works, but installing (or
# reinstalling) a binary into ~/.cargo/bin does not.
# https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

RUST_FIXTURE_BIN="safehouse-fixture-hello"

rust_write_fixture_crate() {
  local dir="$1"

  mkdir -p "${dir}/src"
  cat > "${dir}/Cargo.toml" <<EOF
[package]
name = "${RUST_FIXTURE_BIN}"
version = "0.1.0"
edition = "2021"
EOF
  cat > "${dir}/src/main.rs" <<'EOF'
fn main() {
    println!("safehouse-fixture-ok");
}
EOF
}

setup() {
  sft_setup_test_env

  command -v cargo >/dev/null 2>&1 || skip "cargo is not installed"

  if ! command -v "$RUST_FIXTURE_BIN" >/dev/null 2>&1; then
    local install_dir
    install_dir="$(mktemp -d "${BATS_SUITE_TMPDIR:-/tmp}/safehouse-rust-fixture.XXXXXX")"
    rust_write_fixture_crate "$install_dir"
    # cargo/rustup resolve CARGO_HOME/RUSTUP_HOME from $HOME, which
    # sft_setup_test_env already repointed at an isolated fake home; use the
    # real host home so this unsandboxed setup step reaches the real toolchain.
    ( cd "$install_dir" && HOME="$SAFEHOUSE_HOST_HOME" cargo install --path . --offline --quiet ) \
      || skip "could not install ${RUST_FIXTURE_BIN} fixture globally"
  fi
}

@test "[EXECUTION] cargo --version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- cargo --version
}

@test "[EXECUTION] cargo install --list shows already-installed binaries" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- cargo install --list
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$RUST_FIXTURE_BIN"
}

@test "[EXECUTION] cargo search reads package metadata from the registry" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- cargo search ripgrep --limit 1
}

@test "[EXECUTION] cargo install of a local crate is denied" {
  rust_write_fixture_crate "${SAFEHOUSE_WORKSPACE}/fixture"

  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- cargo install --path "${SAFEHOUSE_WORKSPACE}/fixture" --offline
  [ "$status" -ne 0 ]
}

@test "[EXECUTION] an already-installed global binary runs" {
  run safehouse_ok -- "$RUST_FIXTURE_BIN"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "safehouse-fixture-ok"
}
