#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the Go toolchain profile (profiles/30-toolchains/go.sb).
# Verifies real `go` operations behave as intended under the default sandbox:
# using an already-installed global binary works, but `go install`ing a new
# one into GOPATH/bin does not. https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

GO_FIXTURE_BIN="safehouse-fixture-go"

go_write_fixture_module() {
  local dir="$1"

  mkdir -p "$dir"
  cat > "${dir}/go.mod" <<EOF
module ${GO_FIXTURE_BIN}

go 1.21
EOF
  cat > "${dir}/main.go" <<'EOF'
package main

func main() {
	println("safehouse-fixture-ok")
}
EOF
}

setup() {
  sft_setup_test_env

  command -v go >/dev/null 2>&1 || skip "go is not installed"

  GO_FIXTURE_GOBIN="$(HOME="$SAFEHOUSE_HOST_HOME" go env GOPATH)/bin"
  if [ ! -x "${GO_FIXTURE_GOBIN}/${GO_FIXTURE_BIN}" ]; then
    local install_dir
    install_dir="$(mktemp -d "${BATS_SUITE_TMPDIR:-/tmp}/safehouse-go-fixture.XXXXXX")/${GO_FIXTURE_BIN}"
    go_write_fixture_module "$install_dir"
    ( cd "$install_dir" && HOME="$SAFEHOUSE_HOST_HOME" go install . ) \
      || skip "could not install ${GO_FIXTURE_BIN} fixture globally"
  fi
}

@test "[EXECUTION] go version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- go version
}

@test "[EXECUTION] listing GOPATH/bin shows already-installed binaries" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- /bin/ls "$GO_FIXTURE_GOBIN"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$GO_FIXTURE_BIN"
}

@test "[EXECUTION] go version -m describes an installed binary's module info" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- go version -m "${GO_FIXTURE_GOBIN}/${GO_FIXTURE_BIN}"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$GO_FIXTURE_BIN"
}

@test "[EXECUTION] go install of a local module is denied" {
  go_write_fixture_module "${SAFEHOUSE_WORKSPACE}/fixture"

  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- /bin/sh -c 'cd "$1" && go install .' _ "${SAFEHOUSE_WORKSPACE}/fixture"
  [ "$status" -ne 0 ]
}

@test "[EXECUTION] an already-installed global binary runs" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- "${GO_FIXTURE_GOBIN}/${GO_FIXTURE_BIN}"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "safehouse-fixture-ok"
}
