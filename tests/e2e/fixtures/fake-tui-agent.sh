#!/usr/bin/env bash

set -uo pipefail

canary_path="${SAFEHOUSE_E2E_CANARY_PATH:-./safehouse-e2e-canary.txt}"
forbidden_path="${SAFEHOUSE_E2E_FORBIDDEN_PATH:-${HOME}/.safehouse-e2e-forbidden.txt}"
forbidden_read_path="${SAFEHOUSE_E2E_FORBIDDEN_READ_PATH:-${HOME}/.safehouse-e2e-forbidden-read.txt}"

menu_items=(
  "Write canary file"
  "Attempt forbidden write"
  "Attempt forbidden read"
  "Exit"
)
selection=0

emit_header() {
  echo "SAFEHOUSE_FAKE_TUI_READY"
  echo "MENU:0:${menu_items[0]}"
  echo "MENU:1:${menu_items[1]}"
  echo "MENU:2:${menu_items[2]}"
  echo "MENU:3:${menu_items[3]}"
  echo "HINT: Use Up/Down or j/k, then Enter."
  echo "EVENT:SELECT:0"
}

emit_selection() {
  echo "EVENT:SELECT:${selection}"
}

move_up() {
  if [[ "$selection" -gt 0 ]]; then
    selection=$((selection - 1))
  fi
  emit_selection
}

move_down() {
  if [[ "$selection" -lt 3 ]]; then
    selection=$((selection + 1))
  fi
  emit_selection
}

perform_selection() {
  case "$selection" in
    0)
      if printf 'SAFEHOUSE_E2E_OK\n' >"$canary_path" 2>/dev/null; then
        echo "EVENT:WRITE_OK:${canary_path}"
      else
        echo "EVENT:WRITE_FAIL:${canary_path}"
      fi
      ;;
    1)
      if printf 'SAFEHOUSE_E2E_DENY\n' >"$forbidden_path" 2>/dev/null; then
        echo "EVENT:FORBIDDEN_WRITE_ALLOWED:${forbidden_path}"
      else
        echo "EVENT:FORBIDDEN_WRITE_DENIED:${forbidden_path}"
      fi
      ;;
    2)
      if cat "$forbidden_read_path" >/dev/null 2>&1; then
        echo "EVENT:FORBIDDEN_READ_ALLOWED:${forbidden_read_path}"
      else
        echo "EVENT:FORBIDDEN_READ_DENIED:${forbidden_read_path}"
      fi
      ;;
    3)
      echo "EVENT:EXIT"
      return 1
      ;;
  esac

  return 0
}

mkdir -p "$(dirname "$canary_path")"

emit_header

while true; do
  if ! IFS= read -rsn1 key; then
    break
  fi

  case "$key" in
    $'\x1b')
      if IFS= read -rsn1 -t 1 next && [[ "$next" == "[" ]]; then
        if IFS= read -rsn1 -t 1 arrow; then
          case "$arrow" in
            A) move_up ;;
            B) move_down ;;
          esac
        fi
      fi
      ;;
    k) move_up ;;
    j) move_down ;;
    "" | $'\n' | $'\r')
      if ! perform_selection; then
        exit 0
      fi
      ;;
  esac
done

echo "EVENT:EOF"
exit 0
