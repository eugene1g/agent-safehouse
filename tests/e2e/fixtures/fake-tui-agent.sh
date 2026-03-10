#!/usr/bin/env bash

set -uo pipefail

canary_path="${SAFEHOUSE_E2E_CANARY_PATH:-./safehouse-e2e-canary.txt}"
forbidden_path="${SAFEHOUSE_E2E_FORBIDDEN_PATH:-${HOME}/.safehouse-e2e-forbidden.txt}"
forbidden_read_path="${SAFEHOUSE_E2E_FORBIDDEN_READ_PATH:-${HOME}/.safehouse-e2e-forbidden-read.txt}"
git_repo_path="${PWD}/safehouse-e2e-git-repo"
makefile_path="${PWD}/Makefile.safehouse-e2e"
make_output_path="${PWD}/safehouse-e2e-make-output.txt"

menu_items=(
  "Write canary file"
  "Attempt forbidden write"
  "Attempt forbidden read"
  "Run native Apple git"
  "Run native Apple make"
  "Exit"
)
selection=0

emit_header() {
  local idx

  echo "SAFEHOUSE_FAKE_TUI_READY"
  for idx in "${!menu_items[@]}"; do
    echo "MENU:${idx}:${menu_items[$idx]}"
  done
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
  if [[ "$selection" -lt $((${#menu_items[@]} - 1)) ]]; then
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
      rm -rf "$git_repo_path"
      if /usr/bin/git init -q "$git_repo_path" >/dev/null 2>&1 && [[ -f "$git_repo_path/.git/HEAD" ]]; then
        echo "EVENT:NATIVE_GIT_OK:${git_repo_path}"
      else
        echo "EVENT:NATIVE_GIT_FAIL:${git_repo_path}"
      fi
      ;;
    4)
      rm -f "$make_output_path"
      if /usr/bin/make -f "$makefile_path" safehouse-e2e >/dev/null 2>&1 && [[ -f "$make_output_path" ]]; then
        echo "EVENT:NATIVE_MAKE_OK:${make_output_path}"
      else
        echo "EVENT:NATIVE_MAKE_FAIL:${make_output_path}"
      fi
      ;;
    5)
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
