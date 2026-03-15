# Distribution Artifacts

## Single-File Distribution

`./scripts/generate-dist.sh` generates one committed consumer artifact:

- `dist/safehouse.sh`

`dist/safehouse.sh` is self-contained and embeds the runtime plus policy modules as plain text. It has CLI parity with `bin/safehouse.sh`:

```bash
./dist/safehouse.sh claude --dangerously-skip-permissions
./dist/safehouse.sh --stdout
```

Static `dist/profiles/*` files and app-specific launcher scripts are no longer generated.

## Desktop Apps

Known `.app` bundles are selected automatically when you launch their inner
binary through Safehouse. Today that includes `Claude.app` and `Visual Studio Code.app`.
Claude Desktop also auto-includes the shared `claude-code` profile and its
transitive integrations.

Examples:

```bash
./dist/safehouse.sh -- /Applications/Claude.app/Contents/MacOS/Claude --no-sandbox
./dist/safehouse.sh -- "/Applications/Visual Studio Code.app/Contents/MacOS/Electron" --no-sandbox
```

For Electron apps, keep `--no-sandbox` so the app does not attempt to initialize a nested sandbox inside Safehouse.

## GitHub Releases

See `RELEASE.md` for the canonical local release and tagged-asset workflow.

Stable releases are also published to Homebrew:

```bash
brew install eugene1g/safehouse/agent-safehouse
```
