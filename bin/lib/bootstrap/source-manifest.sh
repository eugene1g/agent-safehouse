# shellcheck shell=bash
# shellcheck disable=SC2034

SAFEHOUSE_LIB_SOURCE_MANIFEST=(
  # Bootstrap + support
  "bootstrap/constants.sh"
  "support/errors.sh"
  "support/collections.sh"
  "support/strings.sh"
  "support/env.sh"
  "support/paths.sh"
  "support/git-discovery.sh"
  "support/sb.sh"

  # Policy pipeline
  "policy/constants.sh"
  "policy/sources.sh"
  "policy/metadata.sh"
  "policy/selection.sh"
  "policy/request.sh"
  "policy/plan.sh"
  "policy/render.sh"
  "policy/explain.sh"

  # Runtime + commands
  "runtime/environment.sh"
  "runtime/launch.sh"
  "commands/update.sh"
  "commands/policy.sh"
  "commands/execute.sh"

  # CLI entrypoints
  "cli/output.sh"
  "cli/parse.sh"
  "commands/main.sh"
)
