# Distribution Artifacts

## Static Baseline Policy Files

Use committed static policies when you need policy files without wrapper runtime:

- `dist/profiles/safehouse.generated.sb` (default baseline)
- `dist/profiles/safehouse-for-apps.generated.sb` (includes app integrations)

Committed generation modes:

- `safehouse.generated.sb`: `--enable=all-agents`
- `safehouse-for-apps.generated.sb`: `--enable=macos-gui,electron,all-agents,all-apps`

Regenerate after profile/runtime changes:

```bash
./scripts/generate-dist.sh
```

Generated static artifacts use template placeholders:

- `HOME`: `/__SAFEHOUSE_TEMPLATE_HOME__`
- Workdir: `/__SAFEHOUSE_TEMPLATE_WORKDIR__`

Before direct policy use, replace `HOME_DIR` and final workdir grant block for your environment.

## Single-File Distribution

`./scripts/generate-dist.sh` also builds the standalone executable and launcher commands:

- `dist/safehouse.sh`
- `dist/Claude.app.sandboxed.command`
- `dist/Claude.app.sandboxed-offline.command`
- `dist/profiles/safehouse.generated.sb`
- `dist/profiles/safehouse-for-apps.generated.sb`

`dist/safehouse.sh` has CLI parity with `bin/safehouse.sh`:

```bash
./dist/safehouse.sh claude --dangerously-skip-permissions
./dist/safehouse.sh --stdout
```

The dist binary is self-contained and embeds policy modules as plain text.
