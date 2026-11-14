#
# Suite-scoped setup, run once per bats run that bats finds this file for
# (e.g. `bats -r tests`, as tests/run.sh does). See suite_helper.bash.
#

source "$(dirname "${BASH_SOURCE[0]}")/suite_helper.bash"

setup_suite() {
  sft_setup_suite
}

teardown_suite() {
  sft_teardown_suite
}
