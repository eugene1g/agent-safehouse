#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the runtime-managers toolchain profile
# (profiles/30-toolchains/runtime-managers.sb). Verifies real mise
# operations behave as intended under the default sandbox:
# listing/describing/running an already-installed tool version works, but
# `mise install`ing a new version into ~/.local/share/mise/installs does
# not. https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

MISE_FIXTURE_TOOL="jq"
MISE_FIXTURE_VERSION="1.8.2"

setup() {
  sft_setup_test_env

  command -v mise >/dev/null 2>&1 || skip "mise is not installed"

  if [ ! -x "${SAFEHOUSE_HOST_HOME}/.local/share/mise/installs/${MISE_FIXTURE_TOOL}/${MISE_FIXTURE_VERSION}/bin/${MISE_FIXTURE_TOOL}" ]; then
    HOME="$SAFEHOUSE_HOST_HOME" mise use -g -y "${MISE_FIXTURE_TOOL}@${MISE_FIXTURE_VERSION}" \
      || skip "could not install ${MISE_FIXTURE_TOOL}@${MISE_FIXTURE_VERSION} fixture globally"
  fi
}

@test "[EXECUTION] mise --version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- mise --version
}

@test "[EXECUTION] mise list shows already-installed tool versions" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- mise list
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$MISE_FIXTURE_TOOL"
}

@test "[EXECUTION] mise where describes an installed tool's install path" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- mise where "$MISE_FIXTURE_TOOL"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" ".local/share/mise/installs/${MISE_FIXTURE_TOOL}"
}

@test "[EXECUTION] mise install of a new tool version is denied" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- mise install "${MISE_FIXTURE_TOOL}@1.7.1"
  [ "$status" -ne 0 ]
  [ ! -e "${SAFEHOUSE_HOST_HOME}/.local/share/mise/installs/${MISE_FIXTURE_TOOL}/1.7.1" ]
}

@test "[EXECUTION] an already-installed tool version runs" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- mise exec "$MISE_FIXTURE_TOOL" -- jq --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "jq-${MISE_FIXTURE_VERSION}"
}
