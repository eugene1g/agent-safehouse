# Generate a Custom `sandbox-exec` Profile with an LLM

If you want an LLM to build a machine-specific profile for your own setup, copy the prompt below into Claude, Codex, Gemini, or another model. It tells the model to inspect Agent Safehouse's real profile sources first, then ask for only the minimum information needed to generate a least-privilege `.sb` file.

Direct plain-text version: [llm-instructions.txt](/llm-instructions.txt)

## Inspect These References First

Point the LLM at the real source files, not `dist/`:

- [`profiles/00-base.sb`](https://github.com/eugene1g/agent-safehouse/blob/main/profiles/00-base.sb)
- [`profiles/10-system-runtime.sb`](https://github.com/eugene1g/agent-safehouse/blob/main/profiles/10-system-runtime.sb)
- [`profiles/20-network.sb`](https://github.com/eugene1g/agent-safehouse/blob/main/profiles/20-network.sb)
- [`profiles/30-toolchains/`](https://github.com/eugene1g/agent-safehouse/tree/main/profiles/30-toolchains)
- [`profiles/40-shared/`](https://github.com/eugene1g/agent-safehouse/tree/main/profiles/40-shared)
- [`profiles/50-integrations-core/`](https://github.com/eugene1g/agent-safehouse/tree/main/profiles/50-integrations-core)
- [`profiles/55-integrations-optional/`](https://github.com/eugene1g/agent-safehouse/tree/main/profiles/55-integrations-optional)
- [`profiles/60-agents/`](https://github.com/eugene1g/agent-safehouse/tree/main/profiles/60-agents)
- [`profiles/65-apps/`](https://github.com/eugene1g/agent-safehouse/tree/main/profiles/65-apps)
- [`bin/lib/bootstrap/source-manifest.sh`](https://github.com/eugene1g/agent-safehouse/blob/main/bin/lib/bootstrap/source-manifest.sh)
- [`bin/lib/policy/request.sh`](https://github.com/eugene1g/agent-safehouse/blob/main/bin/lib/policy/request.sh)
- [`bin/lib/policy/plan.sh`](https://github.com/eugene1g/agent-safehouse/blob/main/bin/lib/policy/plan.sh)
- [`bin/lib/policy/render.sh`](https://github.com/eugene1g/agent-safehouse/blob/main/bin/lib/policy/render.sh)
- [`bin/safehouse.sh`](https://github.com/eugene1g/agent-safehouse/blob/main/bin/safehouse.sh)

Helpful docs:

- [Policy Architecture](/docs/policy-architecture)
- [Customization](/docs/customization)
- [Usage](/docs/usage)
- [Options](/docs/options)

The source of truth lives in `profiles/` and `bin/`. `dist/` is generated output.

## Copy/Paste Prompt

```md
I want you to generate a custom macOS `sandbox-exec` profile for my setup.

Before you generate anything, inspect these references to learn the deny-first structure and real profile patterns used by Agent Safehouse:
- https://github.com/eugene1g/agent-safehouse/blob/main/profiles/00-base.sb
- https://github.com/eugene1g/agent-safehouse/blob/main/profiles/10-system-runtime.sb
- https://github.com/eugene1g/agent-safehouse/blob/main/profiles/20-network.sb
- https://github.com/eugene1g/agent-safehouse/tree/main/profiles/30-toolchains
- https://github.com/eugene1g/agent-safehouse/tree/main/profiles/40-shared
- https://github.com/eugene1g/agent-safehouse/tree/main/profiles/50-integrations-core
- https://github.com/eugene1g/agent-safehouse/tree/main/profiles/55-integrations-optional
- https://github.com/eugene1g/agent-safehouse/tree/main/profiles/60-agents
- https://github.com/eugene1g/agent-safehouse/tree/main/profiles/65-apps
- https://github.com/eugene1g/agent-safehouse/blob/main/bin/lib/bootstrap/source-manifest.sh
- https://github.com/eugene1g/agent-safehouse/blob/main/bin/lib/policy/request.sh
- https://github.com/eugene1g/agent-safehouse/blob/main/bin/lib/policy/plan.sh
- https://github.com/eugene1g/agent-safehouse/blob/main/bin/lib/policy/render.sh
- https://github.com/eugene1g/agent-safehouse/blob/main/bin/safehouse.sh

Use those references as style and capability guides. Prefer the narrowest possible rules and explain which repo profiles influenced your decisions.

Auto-detect as much as you can first:
- absolute HOME path
- current shell and shell config path
- installed toolchains and agent CLIs
- common global dotfiles such as `~/.gitconfig`, `~/.gitignore_global`, `~/.npmrc`, `~/.yarnrc.yml`

Ask me only one combined follow-up question after detection:
- which project directories should be read/write
- which extra paths, if any, should be read-only or denied
- anything you detected that I want removed or added

After you have enough information, produce:
- A complete `.sb` profile file.
- A short explanation of each access grant.
- A wrapper script, if helpful, that resolves the current working directory and launches `sandbox-exec` with the generated profile.
- A clearly labeled shell config snippet for my shell (for example `~/.zshrc`, `~/.bashrc`, or `~/.config/fish/config.fish`) that adds shortcuts for my preferred agents.
- A short install and verification checklist.

Requirements:
- Start from deny-by-default.
- Do not grant my entire home directory unless I explicitly ask for it.
- Prefer `literal` or narrow `subpath` rules instead of broad recursive access.
- Keep global dotfile access minimal and explicit.
- Separate read-only grants from read/write grants.
- If my stack implies toolchain access, mirror the least-privilege patterns from Agent Safehouse rather than inventing broad permissions.
- If you are unsure whether something is required, ask me before adding it.
- Keep the final profile commented and easy to audit.
- Mirror the Safehouse assembly order: `00-base`, `10-system-runtime`, `20-network`, relevant `30-toolchains`, `40-shared`, core `50-integrations-core`, then only the needed `55`/`60`/`65` modules and explicit path grants.
- Use ancestor `literal` read grants for every explicit directory you allow, following Safehouse's `emit_path_ancestor_literals()` behavior.
- Do not invent placeholder tokens such as `__SAFEHOUSE_WORKDIR__` or marker-based post-processing blocks.

If a wrapper script is generated, prefer behavior like this:
- Detect the current working directory with `pwd -P`.
- Optionally prefer `git rev-parse --show-toplevel` when inside a git repo.
- Generate the workdir ancestor literals and workdir read/write rules directly at launch time, then append them to a temporary policy file.
- Keep the script portable and easy to edit.

If shell shortcuts are generated, make them convenient but explicit, for example:
- `safe-claude`
- `safe-codex`
- `safe-cursor`

Use the repo references above to justify the structure of the profile, but output a self-contained result I can save directly to disk.
```

## Suggested Outcome

The best result is usually:

- one machine-local profile file at `~/.config/sandbox-exec/agent.sb`
- one small wrapper script that grants the current project directory
- one clearly labeled shell snippet that adds agent-specific shortcuts in `~/.zshrc`, `~/.bashrc`, `~/.config/fish/config.fish`, or the user's active shell config

That keeps the durable policy in one place while still making everyday agent launches convenient.
