#!/usr/bin/env bats
# bats file_tags=suite:e2e

load ../test_helper.bash
load tmux_utils.bash
load agent_tui_harness.bash

@test "[E2E-TUI] tmux literal wait matches question marks literally" {
  local literal_prompt='What is the capital of England? [literal] (chars) + .*'

  sft_tmux_start_session cat
  sft_tmux_type_and_wait_visible "${literal_prompt}" 2 0.1

  run sft_tmux_capture
  [ "${status}" -eq 0 ]
  [[ "${output}" == *"${literal_prompt}"* ]]
}

@test "[E2E-TUI] prompt visibility regex handles normalized agent echoes" {
  local fake_agent_code=""

  sft_require_cmd_or_skip "python3"

  fake_agent_code=$'import sys, termios, tty\nfd = sys.stdin.fileno()\nold = termios.tcgetattr(fd)\nbuf = []\nprint("Ready", flush=True)\ntry:\n    tty.setcbreak(fd)\n    while True:\n        ch = sys.stdin.read(1)\n        if not ch:\n            break\n        if ch in "\\r\\n":\n            print("* " + "".join(buf).replace("?", ""), flush=True)\n            print("London", flush=True)\n            break\n        buf.append(ch)\n        print("* " + "".join(buf).replace("?", ""), flush=True)\n        sys.stdout.flush()\nfinally:\n    termios.tcsetattr(fd, termios.TCSADRAIN, old)\n'

  AGENT_TUI_PROMPT_VISIBLE_MODE="regex"
  AGENT_TUI_PROMPT_VISIBLE_REGEX='What is the capital of England\?? Reply with only the city name\.'
  AGENT_TUI_SUBMIT_DELAY_SECS=0

  sft_tmux_start_session python3 -u -c "${fake_agent_code}"
  sft_tmux_wait_until "Ready" 2 0.1
  sft_tmux_assert_roundtrip
}
