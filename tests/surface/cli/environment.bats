#!/usr/bin/env bats
# bats file_tags=suite:surface

load ../../test_helper.bash

@test "[EXECUTION] default sanitized mode drops unrelated host vars while preserving core runtime env" {
  SAFEHOUSE_TEST_SECRET="safehouse-secret" \
  safehouse_ok -- /bin/sh -c '
    [ -z "${SAFEHOUSE_TEST_SECRET+x}" ] &&
    [ -n "${HOME:-}" ] &&
    [ -n "${PATH:-}" ] &&
    [ -n "${SHELL:-}" ] &&
    [ -n "${TMPDIR:-}" ]
  '
}

@test "[EXECUTION] default sanitized mode preserves allowlisted SDK and proxy/browser vars" {
  SAFEHOUSE_TEST_SECRET="safehouse-secret" \
  SDKROOT="/tmp/safehouse-sdkroot" \
  HTTP_PROXY="http://proxy.example:8080" \
  NO_BROWSER="true" \
  safehouse_ok -- /bin/sh -c '
    [ "${SDKROOT:-}" = "/tmp/safehouse-sdkroot" ] &&
    [ "${HTTP_PROXY:-}" = "http://proxy.example:8080" ] &&
    [ "${NO_BROWSER:-}" = "true" ]
  '
}

@test "[EXECUTION] --env passes through the caller environment" {
  SAFEHOUSE_TEST_SECRET="secret-value" safehouse_ok --env -- /bin/sh -c '[ "${SAFEHOUSE_TEST_SECRET:-}" = "secret-value" ]'
}

@test "[EXECUTION] leading NAME=VALUE tokens after -- set one-off child env vars" {
  SAFEHOUSE_TEST_SECRET="host-secret" \
    safehouse_ok -- SAFEHOUSE_TEST_SECRET="command-secret" /bin/sh -c '[ "${SAFEHOUSE_TEST_SECRET:-}" = "command-secret" ]'
}

@test "[EXECUTION] --env-pass passes only selected host variables" {
  SAFEHOUSE_TEST_PASS_ONE="pass-one" SAFEHOUSE_TEST_PASS_TWO="pass-two" \
    safehouse_ok --env-pass=SAFEHOUSE_TEST_PASS_ONE -- /bin/sh -c '
      [ "${SAFEHOUSE_TEST_PASS_ONE:-}" = "pass-one" ] &&
      [ -z "${SAFEHOUSE_TEST_PASS_TWO+x}" ]
    '
}

@test "[EXECUTION] SAFEHOUSE_ENV_PASS passes only selected host variables" {
  SAFEHOUSE_ENV_PASS="SAFEHOUSE_TEST_PASS_ONE" \
  SAFEHOUSE_TEST_PASS_ONE="pass-one" \
  SAFEHOUSE_TEST_PASS_TWO="pass-two" \
    safehouse_ok -- /bin/sh -c '
      [ "${SAFEHOUSE_TEST_PASS_ONE:-}" = "pass-one" ] &&
      [ -z "${SAFEHOUSE_TEST_PASS_TWO+x}" ]
    '
}

@test "--env and --env-pass cannot be combined" {
  safehouse_denied --env --env-pass=SAFEHOUSE_TEST_PASS_ONE -- /usr/bin/true
}

@test "[EXECUTION] --env=FILE loads file overrides over sanitized defaults" {
  local env_file
  env_file="$(sft_workspace_path "safehouse.env")"

  cat > "$env_file" <<'EOF'
SAFEHOUSE_TEST_SECRET=file-secret
PATH=/safehouse/env-path
HOME=/safehouse/env-home
EOF

  SAFEHOUSE_TEST_HOST_ONLY="host-only" \
    safehouse_ok --env="$env_file" -- /bin/sh -c '
      [ "${SAFEHOUSE_TEST_SECRET:-}" = "file-secret" ] &&
      [ "${PATH:-}" = "/safehouse/env-path" ] &&
      [ "${HOME:-}" = "/safehouse/env-home" ] &&
      [ -z "${SAFEHOUSE_TEST_HOST_ONLY+x}" ] &&
      [ -n "${SHELL:-}" ] &&
      [ -n "${TMPDIR:-}" ]
    '
}

@test "[EXECUTION] --env-pass can override a matching value loaded from --env=FILE" {
  local env_file
  env_file="$(sft_workspace_path "safehouse.env")"

  cat > "$env_file" <<'EOF'
SAFEHOUSE_TEST_SECRET=file-secret
PATH=/safehouse/env-path
HOME=/safehouse/env-home
EOF

  SAFEHOUSE_TEST_SECRET="host-secret" \
    safehouse_ok --env="$env_file" --env-pass=SAFEHOUSE_TEST_SECRET -- /bin/sh -c '
      [ "${SAFEHOUSE_TEST_SECRET:-}" = "host-secret" ] &&
      [ "${PATH:-}" = "/safehouse/env-path" ]
    '
}

@test "[EXECUTION] playwright-chrome injects its profile env default when the caller does not set it" {
  safehouse_ok --enable=playwright-chrome -- /bin/sh -c '[ "${PLAYWRIGHT_MCP_SANDBOX:-}" = "false" ]'
}

@test "[EXECUTION] caller-provided PLAYWRIGHT_MCP_SANDBOX overrides the playwright-chrome profile default" {
  PLAYWRIGHT_MCP_SANDBOX="true" \
    safehouse_ok --enable=playwright-chrome -- /bin/sh -c '[ "${PLAYWRIGHT_MCP_SANDBOX:-}" = "true" ]'
}

@test "[EXECUTION] default sanitized mode sets APP_SANDBOX_CONTAINER_ID=agent-safehouse" {
  safehouse_ok -- /bin/sh -c '[ "${APP_SANDBOX_CONTAINER_ID:-}" = "agent-safehouse" ]'
}

@test "[EXECUTION] --env preserves caller-provided APP_SANDBOX_CONTAINER_ID" {
  APP_SANDBOX_CONTAINER_ID="caller-container" \
    safehouse_ok --env -- /bin/sh -c '[ "${APP_SANDBOX_CONTAINER_ID:-}" = "caller-container" ]'
}

@test "[EXECUTION] --env=FILE preserves file-provided APP_SANDBOX_CONTAINER_ID" {
  local env_file
  env_file="$(sft_workspace_path "safehouse.env")"

  cat > "$env_file" <<'EOF'
APP_SANDBOX_CONTAINER_ID=file-container
EOF

  safehouse_ok --env="$env_file" -- /bin/sh -c '[ "${APP_SANDBOX_CONTAINER_ID:-}" = "file-container" ]'
}

@test "[EXECUTION] --env-pass=APP_SANDBOX_CONTAINER_ID preserves host value" {
  APP_SANDBOX_CONTAINER_ID="host-container" \
    safehouse_ok --env-pass=APP_SANDBOX_CONTAINER_ID -- /bin/sh -c '[ "${APP_SANDBOX_CONTAINER_ID:-}" = "host-container" ]'
}
