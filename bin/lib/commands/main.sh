# shellcheck shell=bash
# shellcheck disable=SC2154

safehouse_main() {
  cli_parse "$@" || return 1

  case "$cli_mode" in
    help)
      cli_print_usage
      return 0
      ;;
    version)
      cli_print_version
      return 0
      ;;
    update)
      if [[ "$cli_update_action" == "help" ]]; then
        cmd_update_print_usage
        return 0
      fi
      cmd_update_run "$cli_update_channel"
      return $?
      ;;
  esac

  if [[ "$cli_stdout_policy" -eq 1 || "$cli_has_command" -eq 0 ]]; then
    cmd_policy_run
    return $?
  fi

  cmd_execute_run
  return $?
}
