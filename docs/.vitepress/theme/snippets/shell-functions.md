```bash
# ~/.zshrc or ~/.bashrc
safe() { safehouse --add-dirs-ro=~/mywork "$@"; }

# Sandboxed — the default. Just type the command name.
claude()   { safe claude --dangerously-skip-permissions "$@"; }
codex()    { safe codex --dangerously-bypass-approvals-and-sandbox "$@"; }
amp()      { safe amp --dangerously-allow-all "$@"; }
gemini()   { NO_BROWSER=true safe gemini --yolo "$@"; }

# Unsandboxed — bypass the function with `command`
# command claude               — plain interactive session
```
