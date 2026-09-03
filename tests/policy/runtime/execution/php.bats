#!/usr/bin/env bats
# bats file_tags=suite:policy
#
# Execution tests for the PHP toolchain profile (profiles/30-toolchains/php.sb).
# Verifies real Composer operations behave as intended under the default
# sandbox: listing/describing/running already-installed global packages
# works, but `composer global require`ing a new package into the Composer
# home does not. https://github.com/eugene1g/agent-safehouse/issues/102
#
load ../../../test_helper.bash

PHP_FIXTURE_PKG="squizlabs/php_codesniffer"
PHP_FIXTURE_BIN="phpcs"

setup() {
  sft_setup_test_env

  command -v composer >/dev/null 2>&1 || skip "composer is not installed"

  # Composer defaults its home to ~/.composer, but this VM's real composer
  # home was created at the XDG path ~/.config/composer (composer's own
  # default when ~/.config already exists). Pin it explicitly and pass it
  # through the sandbox's env sanitization (COMPOSER_HOME isn't on the
  # default passthrough allowlist) so behavior doesn't depend on ambient
  # directory-existence heuristics.
  COMPOSER_HOME="${SAFEHOUSE_HOST_HOME}/.config/composer"
  export COMPOSER_HOME
  PHP_FIXTURE_BIN_PATH="${COMPOSER_HOME}/vendor/bin/${PHP_FIXTURE_BIN}"

  if [ ! -x "$PHP_FIXTURE_BIN_PATH" ]; then
    HOME="$SAFEHOUSE_HOST_HOME" composer global require --no-interaction "$PHP_FIXTURE_PKG" \
      || skip "could not install ${PHP_FIXTURE_PKG} fixture globally"
  fi
}

@test "[EXECUTION] composer --version succeeds under the default sandbox" {
  HOME="$SAFEHOUSE_HOST_HOME" COMPOSER_HOME="$COMPOSER_HOME" safehouse_ok --env-pass=COMPOSER_HOME -- composer --version
}

@test "[EXECUTION] composer global show lists already-installed global packages" {
  HOME="$SAFEHOUSE_HOST_HOME" COMPOSER_HOME="$COMPOSER_HOME" run safehouse_ok --env-pass=COMPOSER_HOME -- composer global show
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "$PHP_FIXTURE_PKG"
}

@test "[EXECUTION] composer global show describes an installed package" {
  HOME="$SAFEHOUSE_HOST_HOME" COMPOSER_HOME="$COMPOSER_HOME" run safehouse_ok --env-pass=COMPOSER_HOME -- composer global show "$PHP_FIXTURE_PKG"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "PHP_CodeSniffer"
}

@test "[EXECUTION] composer global require of a new package is denied" {
  HOME="$SAFEHOUSE_HOST_HOME" COMPOSER_HOME="$COMPOSER_HOME" run safehouse_ok --env-pass=COMPOSER_HOME -- composer global require --no-interaction psr/container
  [ "$status" -ne 0 ]
}

@test "[EXECUTION] an already-installed global binary runs" {
  HOME="$SAFEHOUSE_HOST_HOME" run safehouse_ok -- "$PHP_FIXTURE_BIN_PATH" --version
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "PHP_CodeSniffer"
}
