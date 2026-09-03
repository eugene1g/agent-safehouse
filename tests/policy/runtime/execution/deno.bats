#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the Deno toolchain profile (profiles/30-toolchains/deno.sb).
# Verifies real deno operations behave as intended under the default sandbox:
# using an already-installed global script works, but `deno install`ing a new
# one does not. https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

DENO_FIXTURE_BIN="safehouse-fixture-deno"

deno_write_fixture_script() {
  local path="$1"

  cat > "$path" <<'EOF'
console.log("safehouse-fixture-ok");
EOF
}

setup() {
  sft_setup_test_env

  command -v deno >/dev/null 2>&1 || skip "deno is not installed"

  DENO_FIXTURE_BIN_PATH="${SAFEHOUSE_HOST_HOME}/.deno/bin/${DENO_FIXTURE_BIN}"
  if [ ! -x "$DENO_FIXTURE_BIN_PATH" ]; then
    # `deno install -f <local-file>` records an absolute reference to the
    # source rather than copying it, so the source must live somewhere
    # durable (not /tmp, which an ephemeral VM restart clears) and readable
    # from inside the sandbox later -- ~/.deno itself is already read-only
    # granted for that reason, so park the fixture source there too.
    local src="${SAFEHOUSE_HOST_HOME}/.deno/fixtures/safehouse-fixture-deno.ts"
    mkdir -p "$(dirname "$src")"
    deno_write_fixture_script "$src"
    HOME="$SAFEHOUSE_HOST_HOME" deno install -g -n "$DENO_FIXTURE_BIN" -f "$src" \
      || skip "could not install ${DENO_FIXTURE_BIN} fixture globally"
  fi
}

@test "[EXECUTION] deno --version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- deno --version
}

@test "[EXECUTION] listing ~/.deno/bin shows already-installed scripts" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- /bin/ls "${SAFEHOUSE_HOST_HOME}/.deno/bin"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$DENO_FIXTURE_BIN"
}

@test "[EXECUTION] deno info describes a remote module's dependency graph" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- deno info jsr:@std/path
}

@test "[EXECUTION] deno install of a new script is denied" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- deno install -g -n safehouse-fixture-deno-new -f jsr:@std/path
  [ "$status" -ne 0 ]
}

@test "[EXECUTION] an already-installed global script runs" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- "$DENO_FIXTURE_BIN_PATH"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "safehouse-fixture-ok"
}
