#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the Java toolchain profile (profiles/30-toolchains/java.sb).
# Verifies real SDKMAN/Gradle operations behave as intended under the default
# sandbox: listing/describing already-installed candidates and running an
# installed one (gradle) works, but `sdk install`ing a new candidate version
# into ~/.sdkman/candidates does not. https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

# `sdk` is a shell function defined by sourcing sdkman-init.sh, not a binary on
# PATH, so every invocation needs to source it first inside the sandboxed shell.
SDK_INIT='source "$HOME/.sdkman/bin/sdkman-init.sh"'

setup() {
  sft_setup_test_env

  # `sdk` is a shell function (not exported), so it isn't visible via `command
  # -v` in bats' non-interactive test subshells; check for the init script's
  # presence on disk instead.
  [ -s "${SAFEHOUSE_HOST_HOME}/.sdkman/bin/sdkman-init.sh" ] || skip "sdkman is not installed"

  # `gradle` is only on PATH -- and its launcher can only find a JVM -- once
  # sdkman-init.sh has set up JAVA_HOME/PATH (deliberately not done ambiently;
  # see the VM's ~/.bash_profile), so every gradle invocation below sources it
  # first, same as the `sdk` calls.
  HOME="$SAFEHOUSE_HOST_HOME" bash -c "${SDK_INIT} && command -v gradle" >/dev/null 2>&1 || skip "gradle is not installed"

  JAVA_CANDIDATE_VERSION="$(HOME="$SAFEHOUSE_HOST_HOME" bash -c "${SDK_INIT} && sdk current java" | awk '{print $NF}')"
  [ -n "$JAVA_CANDIDATE_VERSION" ] || skip "could not determine installed java candidate version"
}

@test "[EXECUTION] sdk version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- bash -c "${SDK_INIT} && sdk version"
}

@test "[EXECUTION] sdk current lists already-installed candidates" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- bash -c "${SDK_INIT} && sdk current"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "gradle"
}

@test "[EXECUTION] sdk home describes an installed candidate's install path" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- bash -c "${SDK_INIT} && sdk home java ${JAVA_CANDIDATE_VERSION}"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" ".sdkman/candidates/java/${JAVA_CANDIDATE_VERSION}"
}

@test "[EXECUTION] sdk install of a new candidate version is denied" {
  # `sdk install` swallows the mv/ln errors from the read-only candidates dir
  # internally and still exits 0 ("Done installing!"), so the exit code alone
  # doesn't prove the denial -- assert on the filesystem instead: the new
  # candidate version must never actually land under ~/.sdkman/candidates.
  # Uses maven (a small download) rather than gradle/java to keep this test fast.
  [ ! -e "${SAFEHOUSE_HOST_HOME}/.sdkman/candidates/maven/3.9.9" ] || skip "maven 3.9.9 is already installed; pick a version that isn't"

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- bash -c "${SDK_INIT} && yes | sdk install maven 3.9.9" || true

  [ ! -e "${SAFEHOUSE_HOST_HOME}/.sdkman/candidates/maven/3.9.9" ]
}

@test "[EXECUTION] an already-installed candidate (gradle) runs" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- bash -c "${SDK_INIT} && gradle --version"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Gradle"
}
