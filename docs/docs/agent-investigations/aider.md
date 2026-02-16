# Aider -- Sandbox Analysis Report

**Analysis Date:** 2026-02-11
**Repository:** https://github.com/Aider-AI/aider
**Git Commit:** `7a1bd15f0c78160129c3b7ffc5ffc94bd992bbbe`
**Latest Version:** 0.86.3.dev
**License:** Apache-2.0
**Source Availability:** Open source

---

## 1. Overview

Aider is a **Python-based** AI coding assistant that operates primarily as a terminal CLI application. The package name is `aider-chat` and requires Python `>=3.10,<3.13`.

The version is managed via `setuptools_scm` and written to `aider/_version.py` at build time. The `__init__.py` has a fallback `safe_version` in case the SCM version import fails.

```python
# aider/__init__.py
__version__ = "0.86.3.dev"
```

Entry point:
```python
# pyproject.toml
[project.scripts]
aider = "aider.main:main"
```

---

## 2. UI & Execution Modes

### Primary UI: Terminal CLI

Aider is fundamentally a **terminal-based CLI application**. The terminal UI is built with:

- **`prompt_toolkit`** -- Provides the interactive command-line input with completion, history, key bindings, vi/emacs editing modes, and multiline support.
- **`rich`** -- Renders styled/colored terminal output, markdown formatting, syntax-highlighted code blocks, panels, and live-updating streams.
- **`rich.live.Live`** / `rich.markdown.Markdown` -- Used in `aider/mdstream.py` for streaming markdown output.

**Source:** `aider/io.py`
```python
from prompt_toolkit.completion import Completer, Completion, ThreadedCompleter
from prompt_toolkit.shortcuts import CompleteStyle, PromptSession
from rich.console import Console
from rich.markdown import Markdown
```

### Secondary UI: Streamlit Web GUI (Optional)

Aider has an optional `--gui` / `--browser` mode that launches a **Streamlit** web application:

**Source:** `aider/main.py`
```python
def launch_gui(args):
    from streamlit.web import cli
    from aider import gui
    # ...
    target = gui.__file__
    st_args = ["run", target]
    st_args += [
        "--browser.gatherUsageStats=false",
        "--runner.magicEnabled=false",
        "--server.runOnSave=false",
    ]
    cli.main(st_args)
```

**Source:** `aider/gui.py`
```python
import streamlit as st
```

This requires the `aider-chat[browser]` optional dependency. Streamlit runs its own HTTP server and opens a browser tab. **This is not the default mode.**

### Summary

| UI Type | Framework | Default? | Port Binding |
|---------|-----------|----------|-------------|
| Terminal CLI | prompt_toolkit + rich | Yes | No |
| Web GUI | Streamlit | No (--gui flag) | Yes (Streamlit's default port) |

---

## 3. Authentication & Credentials

### 3.1 Credential Storage

Aider does **NOT** use macOS Keychain, the `security` CLI tool, or the `keyring` Python library. There are zero imports or references to any system credential store.

Credentials are stored via:

| Method | Location | Format |
|--------|----------|--------|
| OAuth keys | `~/.aider/oauth-keys.env` | Dotenv (`KEY="value"`) |
| .env files | CWD, git root, home dir | Dotenv |
| YAML config | `.aider.conf.yml` (CWD, git root, home) | YAML |
| Environment vars | Process environment | Various `*_API_KEY` vars |
| CLI args | Command line | Plain text |

### 3.2 API Key Sources and Priority Order

#### Command-line Arguments
```python
# aider/args.py
group.add_argument("--openai-api-key", help="Specify the OpenAI API key")
group.add_argument("--anthropic-api-key", help="Specify the Anthropic API key")
group.add_argument("--api-key", action="append", metavar="PROVIDER=KEY",
    help="Set an API key for a provider (eg: --api-key provider=<key> sets PROVIDER_API_KEY=<key>)")
group.add_argument("--set-env", action="append", metavar="ENV_VAR_NAME=value",
    help="Set an environment variable")
```

#### Environment Variables (via `AIDER_` prefix auto-mapping)
```python
# aider/args.py
parser = configargparse.ArgumentParser(
    auto_env_var_prefix="AIDER_",
)
```

Every CLI argument can be set via an `AIDER_` prefixed environment variable. Additionally, aider checks specific API key environment variables directly:

**Source:** `aider/onboarding.py`
```python
model_key_pairs = [
    ("ANTHROPIC_API_KEY", "sonnet"),
    ("DEEPSEEK_API_KEY", "deepseek"),
    ("OPENAI_API_KEY", "gpt-4o"),
    ("GEMINI_API_KEY", "gemini/gemini-2.5-pro-exp-03-25"),
    ("VERTEXAI_PROJECT", "vertex_ai/gemini-2.5-pro-exp-03-25"),
]
openrouter_key = os.environ.get("OPENROUTER_API_KEY")
```

Also checked: `GITHUB_COPILOT_TOKEN`, `AWS_PROFILE`.

#### `.env` File Loading (via python-dotenv)

**Source:** `aider/main.py`
```python
from dotenv import load_dotenv

def load_dotenv_files(git_root, dotenv_fname, encoding="utf-8"):
    dotenv_files = generate_search_path_list(".env", git_root, dotenv_fname)
    oauth_keys_file = Path.home() / ".aider" / "oauth-keys.env"
    if oauth_keys_file.exists():
        dotenv_files.insert(0, str(oauth_keys_file.resolve()))
    # ...
    for fname in dotenv_files:
        if Path(fname).exists():
            load_dotenv(fname, override=True, encoding=encoding)
```

`.env` file search order:
1. `~/.aider/oauth-keys.env` (if exists)
2. `~/.env`
3. `<git_root>/.env`
4. `./.env` (current directory)
5. Custom via `--env-file`

#### YAML Configuration File
```python
conf_fname = Path(".aider.conf.yml")
# Search order:
# 1. .aider.conf.yml in CWD
# 2. .aider.conf.yml in git root
# 3. ~/.aider.conf.yml
```

API keys can be set in the YAML config file as well.

### 3.3 OAuth Flows

#### OpenRouter OAuth Flow

Aider implements a full **OAuth PKCE flow** for OpenRouter authentication:

**Source:** `aider/onboarding.py`
```python
def start_openrouter_oauth_flow(io, analytics):
    port = find_available_port(start_port=8484, end_port=8584)
    callback_url = f"http://localhost:{port}/callback/aider"
    # Starts temporary HTTP server on localhost
    with socketserver.TCPServer(("localhost", port), OAuthCallbackHandler) as httpd:
        # ...
    auth_url = "https://openrouter.ai/auth?..."
    webbrowser.open(auth_url)  # Opens browser for user authentication
    # After success, saves key to:
    config_dir = os.path.expanduser("~/.aider")
    key_file = os.path.join(config_dir, "oauth-keys.env")
    # Writes: OPENROUTER_API_KEY="<key>"
```

This flow:
- Binds a temporary HTTP server on **localhost ports 8484-8584**
- Opens a browser to `https://openrouter.ai/auth`
- Receives the callback with the auth code
- Exchanges the code for an API key via `https://openrouter.ai/api/v1/auth/keys`
- Saves the key to `~/.aider/oauth-keys.env`

#### GitHub Copilot Token Exchange

**Source:** `aider/models.py`
```python
url = "https://api.github.com/copilot_internal/v2/token"
res = requests.get(url, headers=headers)
# Exchanges GITHUB_COPILOT_TOKEN for an ephemeral OpenAI API key
os.environ[openai_api_key] = token
```

### 3.4 Credential File Locations and Formats

| Location | Format | Purpose |
|----------|--------|---------|
| `~/.aider/oauth-keys.env` | Dotenv (`KEY="value"`) | OAuth-obtained API keys |
| `~/.env`, `<git_root>/.env`, `./.env` | Dotenv | Environment variables |
| `.aider.conf.yml` (CWD, git root, `~`) | YAML | Configuration including API keys |
| Process environment | Various `*_API_KEY` vars | API keys |
| Command line | Plain text | API keys via CLI args |

---

## 4. Configuration & Filesystem

### 4.1 User-Level Config Paths

| Path | Purpose |
|------|---------|
| `~/.aider/` | Main config/data directory |
| `~/.aider/analytics.json` | Analytics UUID and opt-in state |
| `~/.aider/oauth-keys.env` | OAuth-obtained API keys |
| `~/.aider/installs.json` | Track first-run per version/executable |
| `~/.aider/caches/` | Cache directory root |
| `~/.aider/caches/versioncheck` | Timestamp file for update check throttling |
| `~/.aider/caches/model_prices_and_context_window.json` | Cached LiteLLM model pricing data |
| `~/.aider/caches/openrouter_models.json` | Cached OpenRouter model list |
| `~/.aider/caches/help.<version>/` | LlamaIndex vector store for /help command |
| `~/.aider.conf.yml` | Global configuration file |
| `~/.aider.model.settings.yml` | Global model settings |
| `~/.aider.model.metadata.json` | Global model metadata |
| `~/.env` | Global environment file (loaded if exists) |

**Source:** `aider/analytics.py`
```python
data_file = Path.home() / ".aider" / "analytics.json"
```

**Source:** `aider/models.py`
```python
self.cache_dir = Path.home() / ".aider" / "caches"
self.cache_file = self.cache_dir / "model_prices_and_context_window.json"
```

**Source:** `aider/versioncheck.py`
```python
VERSION_CHECK_FNAME = Path.home() / ".aider" / "caches" / "versioncheck"
```

### 4.2 Project-Level Config Paths

| Path | Purpose | Read/Write |
|------|---------|------------|
| `<git_root>/.aider.conf.yml` | Project-level config | R |
| `<git_root>/.aider.input.history` | Input command history (prompt_toolkit FileHistory) | RW |
| `<git_root>/.aider.chat.history.md` | Markdown chat history log | RW |
| `<git_root>/.aider.model.settings.yml` | Project model settings | R |
| `<git_root>/.aider.model.metadata.json` | Project model metadata | R |
| `<git_root>/.aider.tags.cache.v4/` | diskcache SQLite database for repo map tags | RW |
| `<git_root>/.aiderignore` | gitignore-style file to exclude files from aider | R |
| `<git_root>/.env` | Project environment variables | R |
| `<git_root>/.gitignore` | May be modified to add `.aider*` and `.env` patterns | RW |

**Source:** `aider/args.py`
```python
default_input_history_file = (
    os.path.join(git_root, ".aider.input.history") if git_root else ".aider.input.history"
)
default_chat_history_file = (
    os.path.join(git_root, ".aider.chat.history.md") if git_root else ".aider.chat.history.md"
)
```

**Source:** `aider/repomap.py`
```python
TAGS_CACHE_DIR = f".aider.tags.cache.v{CACHE_VERSION}"
# Creates SQLite-based diskcache in <git_root>/.aider.tags.cache.v4/
```

#### Current Working Directory Files

| Path | Purpose |
|------|---------|
| `./.aider.conf.yml` | CWD-level config (checked first) |
| `./.aider.model.settings.yml` | CWD model settings |
| `./.aider.model.metadata.json` | CWD model metadata |
| `./.env` | CWD environment file |
| `./.aider.input.history` | Fallback if no git root |
| `./.aider.chat.history.md` | Fallback if no git root |

### 4.3 System/Enterprise Config Paths

N/A

### 4.4 Data & State Directories

| Path | Purpose |
|------|---------|
| `~/.aider/` | Main data directory |
| `~/.aider/analytics.json` | Analytics UUID + preferences |
| `~/.aider/installs.json` | Version tracking |
| `~/.aider/caches/` | Cache root (model pricing, version check, help index) |
| `<git_root>/.aider.tags.cache.v4/` | diskcache SQLite database for repo map tags |

#### Optional Files Created

| Path | Purpose |
|------|---------|
| `<git_root>/.aider.llm.history` | LLM conversation log (only if `--llm-history-file` set) |
| Analytics log file | Custom path via `--analytics-log` |
| `<cwd>/clipboard_image.png` | When pasting images |

### 4.5 Workspace Files Read

| Path | Purpose |
|------|---------|
| `<git_root>/.aiderignore` | gitignore-style file to exclude files |
| `<git_root>/.aider.conf.yml` | Project config |
| `<git_root>/.aider.model.settings.yml` | Project model settings |
| `<git_root>/.aider.model.metadata.json` | Project model metadata |
| `<git_root>/.env` | Project environment variables |
| User project files | Code files being edited |

### 4.6 Temp Directory Usage

Aider uses Python's standard `tempfile` module and **does respect `TMPDIR`** (since Python's `tempfile` respects it by default).

**Voice recording:**
```python
# aider/voice.py
temp_wav = tempfile.mktemp(suffix=".wav")
new_filename = tempfile.mktemp(suffix=f".{use_audio_format}")
```

**Editor integration:**
```python
# aider/editor.py
fd, filepath = tempfile.mkstemp(**kwargs)  # suffix, prefix, dir can be passed
```

**Clipboard image pasting:**
```python
# aider/commands.py
temp_dir = tempfile.mkdtemp()
temp_file_path = os.path.join(temp_dir, basename)
```

**Utility classes for testing:**
```python
# aider/utils.py
class IgnorantTemporaryDirectory:
    self.temp_dir = tempfile.TemporaryDirectory(ignore_cleanup_errors=True)

class ChdirTemporaryDirectory(IgnorantTemporaryDirectory):
    # Changes CWD into a temp dir

class GitTemporaryDirectory(ChdirTemporaryDirectory):
    # Creates a temp dir with a git repo inside
```

All temp file creation goes through Python's `tempfile` module, which respects `TMPDIR`, `TEMP`, and `TMP` environment variables. Aider does NOT create its own temp directory hierarchy.

#### Git Repository Access

Aider makes extensive use of **GitPython** to interact with git repositories:

- `git.Repo(search_parent_directories=True)` -- searches upward for git repos
- `git.Repo.init()` -- can create new git repos
- Reads tracked files, commit history, diffs
- Creates commits with `repo.index.commit()`
- Modifies `.gitignore`
- Reads/writes git config (user.name, user.email)
- Uses `repo.ignored()` to check gitignore patterns

---

## 5. Tools Available to the LLM

Aider gives the LLM the following capabilities:

1. **File editing**: The LLM can read and modify code files in the user's project. Aider supports multiple "edit formats" (whole file replacement, diff-based edits, search/replace blocks) for applying changes.

2. **Shell commands** (via `/run` and `/test`): User-invoked commands that execute shell commands. The LLM can suggest commands, but execution requires user approval via the `/run` or `/test` slash commands.

3. **Git operations**: Aider automatically commits changes made by the LLM via GitPython. The LLM does not directly invoke git, but aider manages git on its behalf.

4. **Web scraping** (via `/web` command): Fetches and processes content from arbitrary URLs, optionally using Playwright for JavaScript-rendered pages.

5. **Linting** (via `/lint`): Runs flake8 or configured linters on modified files.

6. **Voice input** (via `/voice`): Records audio and transcribes via OpenAI Whisper API.

Note: Aider's tool model is more constrained than many agents -- the LLM primarily edits files and suggests commands, rather than having direct shell execution capability.

---

## 6. Host System Interactions

### 6.1 Subprocess Execution

| Tool | Where | Purpose |
|------|-------|---------|
| **git** | `aider/commands.py`, `aider/repo.py`, `aider/report.py` | Version control operations, commit creation, diff viewing |
| **Shell commands** | `aider/run_cmd.py` | User-invoked `/run` and `/test` commands; lint commands |
| **pip** | `aider/utils.py` | Runtime installation of optional dependencies |
| **ensurepip** | `aider/utils.py` | Ensures pip is available before installing |
| **flake8** | `aider/linter.py` | Python linting |
| **System editor** | `aider/editor.py` | Opens vim/vi/notepad for `/editor` command |
| **pexpect** | `aider/run_cmd.py` | Interactive command execution (non-Windows) |
| **Notification commands** | `aider/io.py` | `terminal-notifier`, `osascript`, `notify-send`, `zenity` |
| **playwright** | `aider/scrape.py` | Optional browser automation for web scraping |

**Source:** `aider/run_cmd.py`
```python
def run_cmd(command, verbose=False, error_print=None, cwd=None):
    if sys.stdin.isatty() and hasattr(pexpect, "spawn") and platform.system() != "Windows":
        return run_cmd_pexpect(command, verbose, cwd)
    return run_cmd_subprocess(command, verbose, cwd)
```

Shell commands are executed via `subprocess.Popen(command, shell=True)` or `pexpect.spawn(shell, args=["-i", "-c", command])`. The `SHELL` environment variable is used to determine which shell to use, defaulting to `/bin/sh`.

### 6.2 Network Requests

| Endpoint | Purpose | Module |
|----------|---------|--------|
| LLM API endpoints (via litellm) | Chat completions, transcription | `aider/models.py`, `aider/voice.py` |
| `https://pypi.org/pypi/aider-chat/json` | Version check | `aider/versioncheck.py` |
| `https://raw.githubusercontent.com/BerriAI/litellm/main/model_prices_and_context_window.json` | Model pricing data | `aider/models.py` |
| `https://openrouter.ai/api/v1/models` | OpenRouter model list | `aider/openrouter.py` |
| `https://openrouter.ai/api/v1/auth/key` | OpenRouter tier check | `aider/onboarding.py` |
| `https://openrouter.ai/api/v1/auth/keys` | OAuth code exchange | `aider/onboarding.py` |
| `https://openrouter.ai/auth` | OAuth browser redirect | `aider/onboarding.py` |
| `https://openrouter.ai/<model>` | Model page scraping for info | `aider/models.py` |
| `https://api.github.com/copilot_internal/v2/token` | GitHub Copilot token exchange | `aider/models.py` |
| `https://us.i.posthog.com` | Analytics (PostHog) | `aider/analytics.py` |
| Arbitrary URLs | Web scraping via `/web` command | `aider/scrape.py` |
| `https://download.pytorch.org/whl/cpu` | PyTorch CPU wheels for /help feature | `aider/help.py` |
| HuggingFace Hub | Embedding model download for /help | `aider/help.py` |

**LLM API calls** are routed through the `litellm` library, which supports 100+ providers including OpenAI, Anthropic, Google, Azure, AWS Bedrock, etc. The actual endpoints depend on user configuration.

### 6.3 Port Binding

| Port Range | Purpose | When |
|-----------|---------|------|
| 8484-8584 (localhost) | OAuth callback server | During OpenRouter OAuth flow |
| Streamlit's port (default 8501) | Web GUI | When `--gui` flag is used |

**Source:** `aider/onboarding.py`
```python
def find_available_port(start_port=8484, end_port=8584):
    for port in range(start_port, end_port + 1):
        with socketserver.TCPServer(("localhost", port), None):
            return port
```

### 6.4 Browser Launching

**Source:** `aider/io.py`, `aider/main.py`, `aider/onboarding.py`, `aider/report.py`
```python
import webbrowser
webbrowser.open(url)
```

Used for:
- OpenRouter OAuth flow
- Opening release notes
- Filing GitHub issues from crash reports
- Offering to open documentation URLs
- Opening arbitrary URLs via `io.offer_url()`

### 6.5 Clipboard Access

**Source:** `aider/copypaste.py`
```python
import pyperclip

class ClipboardWatcher:
    def start(self):
        self.last_clipboard = pyperclip.paste()
        # Polls clipboard every 0.5 seconds in a daemon thread
```

**Source:** `aider/commands.py`
```python
import pyperclip
from PIL import ImageGrab  # Clipboard image support

# /paste command - reads clipboard (text and images)
text = pyperclip.paste()
image = ImageGrab.grabclipboard()

# /copy command - writes to clipboard
pyperclip.copy(last_assistant_message)
```

The `pyperclip` library uses platform-specific mechanisms:
- **macOS**: `pbcopy` / `pbpaste`
- **Linux**: `xclip` or `xsel`
- **Windows**: `ctypes` win32 API

Clipboard watching is activated by `--copy-paste` flag.

### 6.6 File System Watchers

**Source:** `aider/watch.py`
```python
from watchfiles import watch

class FileWatcher:
    def watch_files(self):
        for changes in watch(
            *roots_to_watch,
            watch_filter=self.filter_func,
            stop_event=self.stop_event,
            ignore_permission_denied=True,
        ):
```

Uses `watchfiles` (Rust-based, uses inotify/kqueue/FSEvents) to monitor the working directory for file changes. Activated with `--watch-files` flag. Watches the git root or CWD and filters based on gitignore patterns.

### 6.7 Other

#### Sound/Audio System Access

**Source:** `aider/voice.py`
```python
import sounddevice as sd
import soundfile as sf
from pydub import AudioSegment
```

The `/voice` command:
- Opens an audio input stream via `sounddevice` (PortAudio binding)
- Records WAV audio to temp files
- Optionally converts to MP3 via `pydub` (requires ffmpeg)
- Sends audio to OpenAI Whisper API for transcription

#### Notification System

**Source:** `aider/io.py`
```python
def get_default_notification_command(self):
    system = platform.system()
    if system == "Darwin":
        if shutil.which("terminal-notifier"):
            return f"terminal-notifier -title 'Aider' -message '{NOTIFICATION_MESSAGE}'"
        return f'osascript -e \'display notification "{NOTIFICATION_MESSAGE}" with title "Aider"\''
    elif system == "Linux":
        for cmd in ["notify-send", "zenity"]:
            if shutil.which(cmd):
                # ...
```

On macOS, uses `terminal-notifier` or `osascript` for desktop notifications. Activated with `--notifications` flag. Falls back to terminal bell (`\a`).

Custom notification commands can be specified with `--notifications-command`.

#### Runtime Package Installation

Aider can install packages at runtime via pip:

```python
# aider/utils.py
def run_install(cmd):
    ensurepip_cmd = [sys.executable, "-m", "ensurepip", "--upgrade"]
    subprocess.run(ensurepip_cmd, capture_output=True, check=False)
    process = subprocess.Popen(cmd, ...)
```

Packages that may be installed at runtime:
- `aider-chat[browser]` -- Streamlit for web GUI
- `aider-chat[help]` -- LlamaIndex + HuggingFace for /help command
- `aider-chat[playwright]` -- Playwright for web scraping
- Playwright Chromium browser (`playwright install --with-deps chromium`)
- `aider-chat` itself (self-update)
- `git+https://github.com/Aider-AI/aider.git` (install from main branch)
- `boto3` (for AWS Bedrock, suggested but not auto-installed)

#### Shell Integration

```python
# aider/run_cmd.py
shell = os.environ.get("SHELL", "/bin/sh")
```

Also uses `psutil` to detect parent shell process on Windows (PowerShell vs cmd.exe).

#### Editor Environment Variables

```python
# aider/editor.py
editor = os.environ.get("VISUAL", os.environ.get("EDITOR", default))
```

---

## 7. Extension Points

### 7.1 Hook/Lifecycle System

None identified.

### 7.2 Plugin/Extension Architecture

None identified.

### 7.3 MCP Integration

None identified.

### 7.4 Custom Commands/Skills/Agents

Aider provides built-in slash commands (`/run`, `/test`, `/web`, `/voice`, `/editor`, `/paste`, `/copy`, `/lint`, `/help`, etc.) but does not support user-defined custom commands or plugins.

### 7.5 SDK/API Surface

None identified beyond the CLI entry point.

---

## 8. Sandbox & Security Model

### 8.1 Built-in Sandboxing

Aider has **no built-in sandboxing mechanism**. All operations (file edits, shell commands, git operations) run with the full privileges of the user's process.

### 8.2 Permission System

None. All tool use is unrestricted at the process level.

### 8.3 Safety Mechanisms

- Shell commands (`/run`, `/test`) require explicit user invocation -- the LLM cannot execute them autonomously.
- `.aiderignore` file allows users to exclude files from being read/edited.
- Aider auto-adds `.aider*` and `.env` patterns to `.gitignore` to prevent accidental commits.

### 8.4 Known Vulnerabilities

None identified.

### 8.5 Enterprise/Managed Security Controls

None identified.

---

## 9. Key Dependencies

| Dependency | Impact |
|-----------|---------------|
| **tree-sitter** (0.23.2/0.25.2) | Compiles native C code for syntax parsing; includes pre-compiled language grammars via `tree-sitter-language-pack` |
| **tree-sitter-language-pack** (0.13.0) | Pre-compiled native parser libraries for ~50 programming languages |
| **litellm** (1.81.10) | Routes API calls to 100+ LLM providers; manages auth, retries, streaming |
| **pexpect** (4.9.0) | Spawns pseudo-terminals for interactive command execution |
| **psutil** (7.2.2) | Reads process information, used for parent process detection |
| **sounddevice** (0.5.5) | Binds to PortAudio C library for audio recording |
| **soundfile** (0.13.1) | Binds to libsndfile C library for audio file I/O |
| **cffi** (2.0.0) | C Foreign Function Interface, required by sounddevice/soundfile |
| **numpy** (1.26.4) | Compiled C extensions for numerical operations |
| **scipy** (1.15.3) | Compiled Fortran/C extensions for scientific computing |
| **tiktoken** (0.12.0) | Compiled Rust extension for fast token counting |
| **tokenizers** (0.22.2) | Compiled Rust extension from HuggingFace for tokenization |
| **hf-xet** (1.2.0) | Compiled native code for HuggingFace Hub transfers |
| **pyperclip** (1.11.0) | Clipboard access via platform-specific mechanisms (pbcopy/xclip/xsel) |
| **watchfiles** (1.1.1) | Compiled Rust extension using OS file-watching APIs (kqueue on macOS) |
| **pydub** (0.25.1) | Audio format conversion; requires ffmpeg/avconv as external tool |
| **pypandoc** (1.16.2) | Pandoc wrapper; may auto-download pandoc binary |
| **pillow** (12.1.1) | Image processing with native C extensions |
| **diskcache** (5.6.3) | SQLite-based disk cache (creates SQLite databases) |
| **gitpython** (3.1.46) | Git operations; shells out to git CLI |
| **posthog** (7.8.6) | Analytics client; makes HTTP requests to PostHog servers |
| **mixpanel** (5.0.0) | Analytics client (currently disabled but in dependencies) |
| **fastapi** (0.128.8) | In dependency tree via litellm; NOT used directly by aider for serving |
| **Playwright** (optional) | Downloads and manages Chromium browser binary |
| **Streamlit** (optional) | Full web framework; binds HTTP port, opens browser |
| **llama_index** (optional) | Vector search library; downloads HuggingFace embedding models |

### External CLI Tools Used

| Tool | Purpose | Required? |
|------|---------|-----------|
| `git` | Version control | Strongly recommended (can run with `--no-git`) |
| `ffmpeg` / `avconv` | Audio format conversion for voice | Only for non-WAV voice formats |
| `pandoc` | HTML to markdown conversion | Optional, auto-downloaded by pypandoc |
| `flake8` | Python linting | Bundled as dependency |
| `terminal-notifier` | macOS notifications | Optional |
| `osascript` | macOS notifications fallback | Built into macOS |
| `notify-send` | Linux notifications | Optional |
| `pbcopy` / `pbpaste` | macOS clipboard | Built into macOS |
| `xclip` / `xsel` | Linux clipboard | Optional |
| System editor (`vim`, `vi`, `notepad`) | `/editor` command | Optional |

---

## 10. Environment Variables

### Read by Aider

| Variable | Purpose |
|----------|---------|
| `AIDER_*` | Auto-mapped prefix for all CLI arguments |
| `OPENAI_API_KEY` | OpenAI API key |
| `ANTHROPIC_API_KEY` | Anthropic API key |
| `DEEPSEEK_API_KEY` | DeepSeek API key |
| `GEMINI_API_KEY` | Google Gemini API key |
| `VERTEXAI_PROJECT` | Google Vertex AI project |
| `OPENROUTER_API_KEY` | OpenRouter API key |
| `GITHUB_COPILOT_TOKEN` | GitHub Copilot token |
| `AWS_PROFILE` | AWS profile for Bedrock |
| `SHELL` | User's shell (for subprocess execution) |
| `VISUAL` / `EDITOR` | Editor for `/editor` command |
| `TMPDIR` / `TEMP` / `TMP` | Temp directory (via Python's tempfile) |
| `SSL_VERIFY` | SSL verification toggle |

### Set by Aider

| Variable | Purpose |
|----------|---------|
| `OR_SITE_URL` | Set to `https://aider.chat` (for OpenRouter) |
| `OR_APP_NAME` | Set to `Aider` (for OpenRouter) |
| `LITELLM_MODE` | Set to `PRODUCTION` |
| `SSL_VERIFY` | Set to `""` when `--no-verify-ssl` |
| `OPENAI_API_KEY` | Set from CLI args, .env, or Copilot token exchange |
| `ANTHROPIC_API_KEY` | Set from CLI args or .env |
| `OPENAI_API_BASE` | Set from CLI args |
| `OPENROUTER_API_KEY` | Set after OAuth flow |
| `TOKENIZERS_PARALLELISM` | Set to `true` in help module |

---

## 11. Summary Tables

### 11.1 All Filesystem Paths Accessed

| Path | Access | Purpose | Created by Agent? |
|------|--------|---------|-------------------|
| `~/.aider/` | R/W | Main data directory | Yes |
| `~/.aider/analytics.json` | R/W | Analytics UUID + preferences | Yes |
| `~/.aider/oauth-keys.env` | R/W | OAuth-obtained API keys | Yes |
| `~/.aider/installs.json` | R/W | Version tracking | Yes |
| `~/.aider/caches/` | R/W | Cache root | Yes |
| `~/.aider/caches/versioncheck` | R/W | Update check timestamp | Yes |
| `~/.aider/caches/model_prices_and_context_window.json` | R/W | LiteLLM model data cache | Yes |
| `~/.aider/caches/openrouter_models.json` | R/W | OpenRouter model list cache | Yes |
| `~/.aider/caches/help.<version>/` | R/W | LlamaIndex vector store | Yes |
| `~/.aider.conf.yml` | R | Global config | No (user-created) |
| `~/.aider.model.settings.yml` | R | Global model settings | No (user-created) |
| `~/.aider.model.metadata.json` | R | Global model metadata | No (user-created) |
| `~/.env` | R | Global env vars | No (user-created) |
| `<git_root>/.aider.conf.yml` | R | Project config | No (user-created) |
| `<git_root>/.aider.input.history` | R/W | Input history | Yes |
| `<git_root>/.aider.chat.history.md` | R/W | Chat history | Yes |
| `<git_root>/.aider.tags.cache.v4/` | R/W | Tags cache (SQLite) | Yes |
| `<git_root>/.aiderignore` | R | Aider ignore patterns | No (user-created) |
| `<git_root>/.aider.model.settings.yml` | R | Project model settings | No (user-created) |
| `<git_root>/.aider.model.metadata.json` | R | Project model metadata | No (user-created) |
| `<git_root>/.env` | R | Project env vars | No (user-created) |
| `<git_root>/.gitignore` | R/W | Git ignore patterns | Modified by agent |
| `<cwd>/.aider.conf.yml` | R | CWD config | No (user-created) |
| `<cwd>/.env` | R | CWD env vars | No (user-created) |
| `$TMPDIR/*` | R/W | Voice recordings, editor temp files, clipboard images | Yes (cleaned up) |
| User project files | R/W | Code files being edited | Modified by agent |
| Streamlit config dir | R/W | `credentials.toml` (in Streamlit's config path) | Yes (only in --gui mode) |

### 11.2 All Network Endpoints

| Endpoint | Purpose | When Triggered |
|----------|---------|----------------|
| LLM API endpoints (via litellm) | Chat completions, transcription | Every chat message |
| `pypi.org/pypi/aider-chat/json` | Version check | On launch (throttled to 1x/day) |
| `raw.githubusercontent.com` (BerriAI/litellm) | Model pricing data | On launch / model lookup |
| `openrouter.ai/api/v1/models` | OpenRouter model list | On launch if using OpenRouter |
| `openrouter.ai/api/v1/auth/key` | OpenRouter tier check | On launch if using OpenRouter |
| `openrouter.ai/api/v1/auth/keys` | OAuth code exchange | During OpenRouter OAuth |
| `openrouter.ai/auth` | OAuth browser redirect | During OpenRouter OAuth |
| `openrouter.ai/<model>` | Model page scraping | Model info lookup |
| `api.github.com/copilot_internal/v2/token` | GitHub Copilot token exchange | When using Copilot |
| `us.i.posthog.com` | Analytics (PostHog) | If analytics enabled |
| Arbitrary URLs | Web scraping via `/web` | User-triggered `/web` command |
| `download.pytorch.org/whl/cpu` | PyTorch CPU wheels | `/help` command (first use) |
| HuggingFace Hub | Embedding model download | `/help` command (first use) |
| `localhost:8484-8584` (inbound) | OAuth callback server | During OpenRouter OAuth flow |
| Streamlit port (default 8501, inbound) | Web GUI | When `--gui` flag is used |

### 11.3 All System Interactions

| Type | Mechanism | Details |
|------|-----------|---------|
| Subprocess: git | `gitpython` (shells to `git` CLI) | Version control, commits, diffs, config |
| Subprocess: shell | `subprocess.Popen(shell=True)` / `pexpect.spawn()` | `/run`, `/test` commands, lint |
| Subprocess: pip | `subprocess.Popen` | Runtime package installation |
| Subprocess: editor | `subprocess.Popen` | `/editor` command (vim/vi/notepad) |
| Subprocess: flake8 | `subprocess.Popen` | Python linting |
| Subprocess: notifications | `subprocess.Popen` | `terminal-notifier`, `osascript`, `notify-send`, `zenity` |
| Subprocess: playwright | Playwright API | Browser automation for web scraping (optional) |
| Network: LLM APIs | `litellm` / `requests` | Chat completions, transcription |
| Network: PyPI | `requests` | Version check (1x/day) |
| Network: OpenRouter | `requests` / `webbrowser` | OAuth, model list, tier check |
| Network: PostHog | `posthog` client | Analytics events |
| Network: Arbitrary URLs | `requests` / Playwright | `/web` command |
| Port binding | `socketserver.TCPServer` | OAuth callback (8484-8584) |
| Port binding | Streamlit | Web GUI (8501) |
| Clipboard read/write | `pyperclip` (`pbcopy`/`pbpaste`/`xclip`) | `/paste`, `/copy`, `--copy-paste` |
| Audio input | `sounddevice` (PortAudio) | `/voice` command |
| File watching | `watchfiles` (kqueue/inotify/FSEvents) | `--watch-files` flag |
| Browser launch | `webbrowser.open()` | OAuth, release notes, docs, bug reports |
| Terminal bell | `\a` character | `--notifications` without custom command |
| Env var mutation | `os.environ[...]` | Sets API keys, LiteLLM config, SSL verify |
| Git config write | `gitpython` | user.name, user.email defaults (new repo) |

---

## 12. Sandboxing Recommendations

1. **No built-in sandboxing**: Aider runs with full user privileges and has no sandboxing mechanism. All file edits, shell commands, and network requests run unrestricted.

2. **Shell command execution**: While `/run` and `/test` require user invocation, the commands themselves run unsandboxed with `shell=True`. Consider restricting with an external sandbox.

3. **Runtime pip installs**: Aider can install Python packages at runtime, including downloading and running arbitrary code. This is a significant attack surface.

4. **Clipboard polling**: When `--copy-paste` is enabled, aider polls the clipboard every 0.5 seconds in a daemon thread, which could capture sensitive data.

5. **Analytics**: PostHog analytics are enabled by default. Consider disabling with `--no-analytics`.

6. **File access**: Aider has unrestricted read/write access to the filesystem. The `.aiderignore` file provides some control but is advisory, not enforced by a sandbox.

7. **Network access**: Aider makes requests to numerous endpoints (LLM providers, PyPI, OpenRouter, PostHog, GitHub, arbitrary URLs via `/web`). Consider restricting network access to only necessary endpoints.

8. **Git operations**: Aider can create commits, modify `.gitignore`, and read/write git config. Consider protecting `.git/hooks/` from modification.

9. **Recommended isolation**: Run aider inside a container or VM, or use macOS seatbelt / Linux seccomp to restrict filesystem and network access to only what's needed.
