# shellcheck shell=bash

safehouse_fail() {
  local line

  for line in "$@"; do
    printf '%s\n' "$line" >&2
  done

  return 1
}

safehouse_die() {
  local status="$1"
  shift

  safehouse_fail "$@" || true
  exit "$status"
}
