# shellcheck shell=bash

safehouse_validate_env_var_name() {
  local var_name="$1"

  [[ "$var_name" =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]
}
