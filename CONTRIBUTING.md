# Contributing to Agent Safehouse

## Scope

Agent Safehouse is a macOS sandbox toolkit for LLM coding agents built with Bash and Sandbox Profile Language (`.sb`) policy modules.

## Project Layout (What to Edit)

- `bin/` and `bin/lib/`: runtime CLI and policy assembly logic.
- `profiles/`: authored policy modules (`.sb`), organized by numeric stage.
- `tests/`: policy behavior tests and helpers.
- `scripts/generate-dist.sh`: deterministic packaging pipeline.
- `dist/`: generated distribution artifacts for consumers (not source of truth).

## Use Local Binary During Development

To ensure you test your local changes (not an installed `safehouse` on PATH), add a shell override in `~/.zshrc`:

```bash
# Agent Safehouse local dev override
export AGENT_SAFEHOUSE_REPO="$HOME/server/agent-safehouse"
safehouse() { "$AGENT_SAFEHOUSE_REPO/bin/safehouse.sh" "$@"; }
```

Then reload your shell:

```bash
source ~/.zshrc
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
# Run policy tests (macOS only; must be outside an existing sandbox)
./tests/run.sh

# Regenerate deterministic dist artifacts (required after profile/runtime changes)
./scripts/generate-dist.sh
```

If tests cannot run because your session is already sandboxed, call that out in your PR and include static validation details instead.

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
  - Run `./tests/run.sh`.
- If you changed docs only:
  - No dist regeneration needed.

## Adding Tests

- Add behavior tests under `tests/sections/*.sh`.
- Use existing helpers in `tests/lib/common.sh` (`assert_allowed`, `assert_denied`, `assert_policy_contains`, `assert_policy_order_literal`, etc.).
- Register the section function with `register_section`.
- Prefer precise tests for ordering and policy-shape regressions when changing assembly logic or module dependencies.

## Pull Request Checklist

- Explain what changed and why.
- Describe security/least-privilege impact (especially for new allow rules).
- Include test evidence (`./tests/run.sh`) or clearly state why tests were not runnable.
- Confirm whether `dist/` was regenerated and committed (when required).

## Design Guidance for Reviews

- Prefer narrow path matchers (`literal` > `subpath` when possible).
- Avoid introducing new sensitive-path exposure unless justified.
- Keep optional integrations opt-in unless required by selected profiles.
- Treat policy assembly order as a first-class behavior constraint.
