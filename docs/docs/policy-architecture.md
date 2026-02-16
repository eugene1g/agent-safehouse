# Policy Architecture

`safehouse` composes a final sandbox policy from modular profiles, then runs your command under `sandbox-exec`.

Policy assembly order:

| Layer | Coverage |
|-------|----------|
| `00-base.sb` | Default deny, helper functions, HOME replacement token |
| `10-system-runtime.sb` | macOS runtime binaries, temp dirs, IPC |
| `20-network.sb` | Network policy |
| `30-toolchains/*.sb` | Node, Python, Go, Rust, Bun, Java, PHP, Perl, Ruby |
| `40-shared/*.sb` | Shared cross-agent modules |
| `50-integrations-core/*.sb` | Core integrations (`container-runtime-default-deny`, `git`, `scm-clis`) |
| `55-integrations-optional/*.sb` | Opt-in integrations (`--enable=...`) |
| `60-agents/*.sb` | Per-agent profile selection by command basename |
| `65-apps/*.sb` | Per-app bundle selection (`Claude.app`, `Visual Studio Code.app`) |
| Config/env/CLI grants | Trusted `.safehouse` config, env grants, CLI grants, selected workdir |
| Appended profiles | User profile overlays via `--append-profile` (loaded last) |

## Ordering Rules Matter

Later rules win. If behavior is unexpected, check ordering first.

Important implications:

- Broad late grants (for example `--add-dirs` or `--enable=wide-read`) can reopen earlier read denies.
- Appended profiles (`--append-profile`) are the correct final override layer for must-not-read path denials.

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

Assembly logic in `/Users/eugene/server/agent-safehouse/bin/lib/policy.sh` replaces this with the actual absolute home path.
