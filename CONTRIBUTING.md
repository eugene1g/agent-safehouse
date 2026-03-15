# Contributing to Agent Safehouse

## Scope

Agent Safehouse is a macOS sandbox toolkit for LLM coding agents built with Bash and Sandbox Profile Language (`.sb`) policy modules.

## Project Layout (What to Edit)

- `bin/` and `bin/lib/`: runtime CLI and policy assembly logic.
- `profiles/`: authored policy modules (`.sb`), organized by numeric stage.
- `tests/policy/`: primary policy and runtime contract suite.
- `tests/surface/`: CLI and packaged-artifact contract suite.
- `tests/e2e/`: tmux-driven startup/readiness and prompt-roundtrip checks for agent TUIs.
- `scripts/generate-dist.sh`: deterministic packaging pipeline.
- `dist/`: generated distribution artifacts for consumers (not source of truth).

## Use Local Binary During Development

To ensure you test your local changes (not an installed `safehouse` on PATH), add a shell override in your shell config:

POSIX shells (`zsh` / `bash`):

```bash
# ~/.zshrc or ~/.bashrc
# Agent Safehouse local dev override
export AGENT_SAFEHOUSE_REPO="$HOME/server/agent-safehouse"
safehouse() { "$AGENT_SAFEHOUSE_REPO/bin/safehouse.sh" "$@"; }
```

`fish`:

```fish
# ~/.config/fish/config.fish
set -gx AGENT_SAFEHOUSE_REPO "$HOME/server/agent-safehouse"

function safehouse
    "$AGENT_SAFEHOUSE_REPO/bin/safehouse.sh" $argv
end
```

Then reload your shell:

POSIX shells (`zsh` / `bash`):

```bash
source ~/.zshrc   # or ~/.bashrc
type -a safehouse
```

`fish`:

```fish
source ~/.config/fish/config.fish
type -a safehouse
```

`type -a safehouse` should show your function first.

## Contribution Rules

- Do not hand-edit `dist/*`.
- Make functional changes in `bin/` and `profiles/`, then regenerate `dist/` when required.
- Keep policy changes least-privilege; avoid broad grants unless needed.
- Preserve stage ordering semantics. Later rules win.
- Keep each `.sb` module standalone for its capability.

## Contribution Philosophy (Security + DX)

- Follow the project philosophy: agent productivity and developer experience matter, but keep strong least-privilege boundaries.
- Prefer the narrowest rule that unblocks real workflows.
- If adding access to sensitive paths/integrations, document why it is needed and why narrower alternatives were not sufficient.
- Avoid policy churn that improves theoretical security but breaks common agent/toolchain behavior without clear benefit.

## `.sb` Authoring Expectations

- Keep the standard header (category/integration/app, description, `Source:` path).
- Use stage prefixes correctly (`00`, `10`, `20`, `30`, `40`, `50`, `55`, `60`, `65`).
- Dependency metadata is declared with `$$require=path/to/profile.sb[,path/to/other.sb]$$` when implicit optional integration injection is needed.
- `;; Requires:` comments are documentation only; `$$require=...$$` is machine-read metadata.
- Add `#safehouse-test-id:*#` markers when tests rely on structure/order checks.

Reference material for sandbox profile language (example-heavy):
- This repo’s authored modules under `profiles/` (primary style/source-of-truth for this project).
- Assembled policy examples: `dist/profiles/safehouse.generated.sb` and `dist/profiles/safehouse-for-apps.generated.sb`.
- macOS built-in profile examples: `/System/Library/Sandbox/Profiles/` and `/usr/share/sandbox/`.
- External prior art with real policy examples is listed in `README.md` under `Reference & Prior Art`.

Starter snippets (copy/paste and adapt paths/names):

```scheme
;; Exact single-path allow (narrowest option)
(allow file-read*
    (literal "/Users/alice/.gitconfig")
)
```

```scheme
;; Recursive directory allow (broader; use only when required)
(allow file-read*
    (subpath "/Users/alice/projects/reference-repo")
)
```

```scheme
;; Mach service allow (common for macOS framework IPC)
(allow mach-lookup
    (global-name "com.apple.cfprefsd.daemon")
)
```

## Local Validation

```bash
# Run the default non-E2E suites (macOS only; must be outside an existing sandbox)
./tests/run.sh

# Run only the tmux-driven E2E suite
./tests/run.sh e2e

# Regenerate deterministic dist artifacts (required after profile/runtime changes)
./scripts/generate-dist.sh
```

If tests cannot run because your session is already sandboxed, call that out in your PR and include static validation details instead.

## Releasing

Releases are done through the repo-local `release` skill at
[`./.agents/skills/release/SKILL.md`](./.agents/skills/release/SKILL.md).

Use a local agent with that skill to:

- inspect commits and diffs since the last published stable release
- choose the next SemVer version
- draft the new `CHANGELOG.md` release section
- present a dry-run overview and wait for explicit confirmation
- after confirmation, update `CHANGELOG.md`, regenerate `dist/`, run verification, publish the GitHub release, and publish the stable Homebrew tap

`RELEASE.md` is only a short pointer/summary for that workflow.

## Debugging Sandbox Rejections

Use `/usr/bin/log` to watch denial events:

```bash
# Live denial stream
/usr/bin/log stream --style compact --predicate 'eventMessage CONTAINS "Sandbox:" AND eventMessage CONTAINS "deny("'

# Kernel-level stream (captures additional events)
/usr/bin/log stream --style compact --info --debug --predicate '(processID == 0) AND (senderImagePath CONTAINS "/Sandbox")'

# Recent sandboxd history
/usr/bin/log show --last 2m --style compact --predicate 'process == "sandboxd"'
```

## Required Steps by Change Type

- If you changed `profiles/*.sb` or policy assembly/runtime (`bin/safehouse.sh`, `bin/lib/*.sh`):
  - Update/add tests.
  - Run `./scripts/generate-dist.sh`.
  - Include regenerated `dist/` files in the same PR.
- If you changed tests only:
  - Run `./tests/run.sh` and/or `./tests/run.sh e2e`, depending on the suite you touched.
- If you changed docs only:
  - No dist regeneration needed.

## Adding Tests

- Add tests under `tests/policy/<topic>/*.bats`, `tests/surface/<topic>/*.bats`, or `tests/e2e/*.bats`.
- Load the shared helper from nested policy/surface folders with `load ../../test_helper.bash`.
- E2E files should `load ../test_helper.bash`, then `load tmux_utils.bash`, then `load agent_tui_harness.bash`.
- Prefer Bats built-ins (`run`, `skip`) plus the small helper layer in `tests/test_helper.bash`.
- Keep tests dist-first: validate the packaged entrypoint and generated policy/runtime contracts rather than sourced shell internals.
- Prefer precise tests for security boundaries, dependency injection, and the few order-sensitive invariants that affect semantics.

## Pull Request Checklist

- Explain what changed and why.
- Describe security/least-privilege impact (especially for new allow rules).
- Include test evidence (`./tests/run.sh` and/or `./tests/run.sh e2e`) or clearly state why tests were not runnable.
- Confirm whether `dist/` was regenerated and committed (when required).
- If preparing a release, confirm `CHANGELOG.md` has a matching SemVer section for the tag.

## Design Guidance for Reviews

- Prefer narrow path matchers (`literal` > `subpath` when possible).
- Avoid introducing new sensitive-path exposure unless justified.
- Keep optional integrations opt-in unless required by selected profiles.
- Treat policy assembly order as a first-class behavior constraint.
