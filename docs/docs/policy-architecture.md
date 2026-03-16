# Policy Architecture

`safehouse` composes a final sandbox policy from modular profiles, then runs your command under `sandbox-exec`.

Policy assembly order:

| Layer | Coverage |
|-------|----------|
| `00-base.sb` | Default deny, helper functions, HOME replacement token |
| `10-system-runtime.sb` | macOS runtime binaries, temp dirs, IPC |
| `20-network.sb` | Network policy |
| `30-toolchains/*.sb` | Apple Toolchain Core, Node, Python, Go, Rust, Bun, Java, PHP, Perl, Ruby |
| `40-shared/*.sb` | Shared cross-agent modules |
| `50-integrations-core/*.sb` | Core integrations (`container-runtime-default-deny`, `git`, `launch-services`, `scm-clis`, `ssh-agent-default-deny`, `worktree-common-dir`, `worktrees`) |
| `55-integrations-optional/*.sb` | Opt-in integrations (`--enable=...`) |
| `60-agents/*.sb` | Per-agent profile selection by command basename |
| `65-apps/*.sb` | Per-app bundle selection (`Claude.app`, `Visual Studio Code.app`) |
| Config/env/CLI grants | Trusted `.safehouse` config, env grants, CLI grants, auto-detected app bundle read grant, selected workdir, launch-time active-worktree common-dir grant, and launch-time sibling worktree read grants |
| Appended profiles | User profile overlays via `--append-profile` (loaded last) |

## Ordering Rules Matter

Later rules win. If behavior is unexpected, check ordering first.

Important implications:

- Broad late grants (for example `--add-dirs` or `--enable=wide-read`) can reopen earlier read denies.
- Appended profiles (`--append-profile`) are the correct final override layer for must-not-read path denials.
- Active linked-worktree common-dir detection happens at launch.
- Sibling worktree read grants are a launch-time snapshot. New worktrees created after the process starts are not added to the active policy.

## Path Matchers

Safehouse uses standard sandbox matchers:

- `literal`: exact path
- `subpath`: recursive path
- `prefix`: starts-with path
- `regex`: regex matcher

Ancestor `literal` read grants are intentionally emitted for traversal compatibility.

## Home Placeholder Replacement

`profiles/00-base.sb` uses `HOME_DIR` placeholder token:

- `__SAFEHOUSE_REPLACE_ME_WITH_ABSOLUTE_HOME_DIR__`

Assembly logic in `/Users/eugene/server/agent-safehouse/bin/lib/policy/render.sh` replaces this with the actual absolute home path.

`HOME_DIR` exists so profiles can express narrow home-relative rules through the shared helpers:

- `home-literal`
- `home-subpath`
- `home-prefix`

It is not a blanket grant for `$HOME`.

Safehouse also generates a `file-read-metadata` block for `/`, the path to `$HOME`, and `$HOME` itself. That metadata-only traversal lets runtimes `stat` or walk toward explicitly allowed home-scoped paths without granting recursive reads of the whole home directory.

In practice, that means `stat "$HOME"` can succeed while `ls "$HOME"` and `cat ~/secret.txt` still fail unless a more specific rule grants them.

See also: [Bin Architecture](/docs/bin-architecture)
