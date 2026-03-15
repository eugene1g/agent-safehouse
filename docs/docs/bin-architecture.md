# Bin Architecture

`bin/` now follows a directional pipeline instead of sharing one mutable global state bag across loosely related files.

Runtime flow:

1. `bin/safehouse.sh` bootstraps the environment and sources modules from `bin/lib/bootstrap/source-manifest.sh`.
2. `bin/lib/cli/parse.sh` parses argv once into the `cli_*` namespace.
3. Command handlers in `bin/lib/commands/` decide whether the request is policy output, execution, or self-update.
4. `bin/lib/policy/request.sh` normalizes cwd, environment inputs, trusted workdir config, app-bundle context, launch-time Git worktree auto-grants, and raw policy inputs into `policy_req_*`.
5. `bin/lib/policy/plan.sh` derives selected profiles, optional integration inclusion, normalized path grants, and profile runtime env defaults into `policy_plan_*`.
6. `bin/lib/policy/render.sh` renders the final SBPL policy directly to disk from the completed request + plan.
7. `bin/lib/runtime/` builds the wrapped execution environment and launches `sandbox-exec` when a command should run.

Module boundaries:

- `bootstrap/`: project constants and the ordered source manifest.
- `support/`: pure helper functions only.
- `cli/`: argv parsing and user-facing CLI text.
- `commands/`: top-level command handlers and process exit boundaries.
- `policy/`: request building, scoped profile selection, plan derivation, policy rendering, and explain output.
- `runtime/`: app bundle detection, execution-environment assembly, and process launch.

Namespace contract:

- `cli_*` is written only by CLI parsing.
- `policy_req_*` is written only by request building.
- `policy_plan_*` is written only by plan building.
- `runtime_*` is written only by runtime helpers.
- Only `safehouse_main` and `cmd_*` handlers should terminate the process.

Packaging rule:

`scripts/generate-dist.sh` sources the same `bin/lib/bootstrap/source-manifest.sh` file and inlines modules in that order, so source and `dist` builds share one authoritative module list.
