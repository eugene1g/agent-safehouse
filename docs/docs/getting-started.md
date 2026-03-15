# Getting Started

## Install

Homebrew:

```bash
brew install eugene1g/safehouse/agent-safehouse
```

Standalone script:

```bash
mkdir -p ~/.local/bin
curl -fsSL https://github.com/eugene1g/agent-safehouse/releases/latest/download/safehouse.sh \
  -o ~/.local/bin/safehouse
chmod +x ~/.local/bin/safehouse
```

## Optional Local Overrides

For single files, prefer a direct path grant instead of an appended profile:

```bash
safehouse --add-dirs-ro=~/.gitignore -- claude --dangerously-skip-permissions
```

Create a local profile file only for recurring machine-specific exceptions:

```bash
mkdir -p ~/.config/agent-safehouse
cat > ~/.config/agent-safehouse/local-overrides.sb <<'EOF2'
;; Local user overrides
(allow file-read*
  (home-literal "/.lldbinit")
  (home-subpath "/Library/Application Support/CleanShot/media")
)
EOF2
```

## Shell Functions (Recommended)

Prefer selective env passthrough by default. `safeenv` forwards the entire inherited host environment, including secrets such as `AWS_SECRET_ACCESS_KEY`, `GITHUB_TOKEN`, and provider API keys. Use `safekeys` for the common agent-key case and reserve `safeenv` for wrappers that genuinely need broad host env access.

POSIX shells (`zsh` / `bash`):

```bash
# ~/.bashrc or ~/.zshrc
SAFEHOUSE_APPEND_PROFILE="$HOME/.config/agent-safehouse/local-overrides.sb"

safe() { safehouse --add-dirs-ro=~/mywork --append-profile="$SAFEHOUSE_APPEND_PROFILE" "$@"; }
safeenv() { safe --env "$@"; }
safekeys() { safe --env-pass=OPENAI_API_KEY,ANTHROPIC_API_KEY,GEMINI_API_KEY "$@"; }
claude()   { safe claude --dangerously-skip-permissions "$@"; }
codex()    { safe codex --dangerously-bypass-approvals-and-sandbox "$@"; }
amp()      { safe amp --dangerously-allow-all "$@"; }
opencode() { OPENCODE_PERMISSION='{"*":"allow"}' safekeys opencode "$@"; }
gemini()   { NO_BROWSER=true safekeys gemini --yolo "$@"; }
goose()    { safe goose "$@"; }
kilo()     { safe kilo "$@"; }
pi()       { safe pi "$@"; }
```

`fish`:

```fish
# ~/.config/fish/config.fish
set -gx SAFEHOUSE_APPEND_PROFILE "$HOME/.config/agent-safehouse/local-overrides.sb"

function safe
    safehouse --add-dirs-ro="$HOME/mywork" --append-profile="$SAFEHOUSE_APPEND_PROFILE" $argv
end

function safeenv
    safe --env $argv
end

function safekeys
    safe --env-pass=OPENAI_API_KEY,ANTHROPIC_API_KEY,GEMINI_API_KEY $argv
end

function claude
    safe claude --dangerously-skip-permissions $argv
end

function codex
    safe codex --dangerously-bypass-approvals-and-sandbox $argv
end

function amp
    safe amp --dangerously-allow-all $argv
end

function opencode
    set -lx OPENCODE_PERMISSION '{"*":"allow"}'
    safekeys opencode $argv
end

function gemini
    set -lx NO_BROWSER true
    safekeys gemini --yolo $argv
end

function goose
    safe goose $argv
end

function kilo
    safe kilo $argv
end

function pi
    safe pi $argv
end
```

Run the real unsandboxed binary with `command <agent>` when needed.

## First Commands

```bash
# Generate policy for current repo and print policy path
safehouse

# Run an agent inside sandbox
cd ~/projects/my-app
safehouse claude --dangerously-skip-permissions
```

## Desktop Apps

Download the standalone release asset:

```bash
curl -fsSL https://github.com/eugene1g/agent-safehouse/releases/latest/download/safehouse.sh \
  -o ~/Downloads/safehouse
chmod +x ~/Downloads/safehouse
```

Known app bundles are matched to their app profile automatically, so Claude
Desktop usually does not need extra `--enable` flags:

```bash
~/Downloads/safehouse -- /Applications/Claude.app/Contents/MacOS/Claude --no-sandbox
~/Downloads/safehouse -- "/Applications/Visual Studio Code.app/Contents/MacOS/Electron" --no-sandbox
```

If you use Claude Desktop "Allow bypass permissions mode", launching Claude Desktop through Safehouse is intended to keep tool execution constrained by the outer Safehouse policy.
