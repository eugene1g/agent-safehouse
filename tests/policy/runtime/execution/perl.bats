#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the Perl toolchain profile (profiles/30-toolchains/perl.sb).
# Verifies real cpanm/local::lib operations behave as intended under the
# default sandbox: listing/describing/running already-installed modules
# works, but `cpanm`-installing a new module into ~/perl5 does not.
# https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

PERL_FIXTURE_MODULE="Perl::Tidy"
PERL_FIXTURE_BIN="perltidy"

setup() {
  sft_setup_test_env

  command -v cpanm >/dev/null 2>&1 || skip "cpanm is not installed"

  PERL5_LOCAL_LIB="${SAFEHOUSE_HOST_HOME}/perl5"
  PERL5LIB="${PERL5_LOCAL_LIB}/lib/perl5"
  export PERL5LIB
  PERL_FIXTURE_BIN_PATH="${PERL5_LOCAL_LIB}/bin/${PERL_FIXTURE_BIN}"

  if [ ! -x "$PERL_FIXTURE_BIN_PATH" ]; then
    HOME="$SAFEHOUSE_HOST_HOME" cpanm --local-lib="$PERL5_LOCAL_LIB" --notest "$PERL_FIXTURE_MODULE" \
      || skip "could not install ${PERL_FIXTURE_MODULE} fixture globally"
  fi
}

@test "[EXECUTION] cpanm --version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok -- cpanm --version
}

@test "[EXECUTION] listing the local::lib tree shows already-installed modules" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- /bin/ls "${PERL5_LOCAL_LIB}/lib/perl5"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Perl"
}

@test "[EXECUTION] perldoc describes an installed module's location" {
  HOME="$SAFEHOUSE_HOST_HOME" PERL5LIB="$PERL5LIB" run safehouse_ok --env-pass=PERL5LIB -- perldoc -l "$PERL_FIXTURE_MODULE"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Tidy"
}

@test "[EXECUTION] cpanm install of a new module into ~/perl5 is denied" {
  HOME="$SAFEHOUSE_HOST_HOME" PERL5LIB="$PERL5LIB" run safehouse_ok --env-pass=PERL5LIB -- cpanm --local-lib="$PERL5_LOCAL_LIB" --notest JSON::PP
  [ "$status" -ne 0 ]
}

@test "[EXECUTION] an already-installed local::lib binary runs" {
  HOME="$SAFEHOUSE_HOST_HOME" PERL5LIB="$PERL5LIB" run safehouse_ok --env-pass=PERL5LIB -- "$PERL_FIXTURE_BIN_PATH" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "perltidy"
}
