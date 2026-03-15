# Safehouse Test Suite

This directory contains the [bats-core](https://github.com/bats-core/bats-core) suites for the packaged Safehouse entrypoint, [dist/safehouse.sh](/dist/safehouse.sh).

## Requirements

- [`bats`](https://github.com/bats-core/bats-core) must be installed on the host.
- Parallel execution via `./tests/run.sh` also requires a Bats-supported backend such as GNU `parallel` or `rush`.
- On macOS, the official bats-core installation docs recommend:

```bash
brew install bats-core
```

For parallel execution on macOS:

```bash
brew install parallel
```

- These tests also require `sandbox-exec` and must be run outside any existing sandbox.

Official references:
- [bats-core project](https://github.com/bats-core/bats-core)
- [bats-core installation docs](https://bats-core.readthedocs.io/en/stable/installation.html)
- [bats-core usage docs](https://bats-core.readthedocs.io/en/stable/usage.html)

## Run

```bash
./tests/run.sh
```

This runs the default non-E2E suites:

```bash
./tests/run.sh policy
./tests/run.sh surface
```

Run the tmux-driven E2E suite separately:

```bash
./tests/run.sh e2e
```

Run every suite, including E2E:

```bash
./tests/run.sh all
```

`./tests/run.sh` uses the available CPU count as the default `--jobs` value when a supported Bats parallel backend is installed. If no backend is available, it falls back to serial execution.
It also enables `--timing` and `--print-output-on-failure` by default, prints whether the suite is running in parallel or serial mode, and in the no-backend case prints an install hint for `parallel` or `rush`.

You can override the default job count:

```bash
SAFEHOUSE_BATS_JOBS=1 ./tests/run.sh
./tests/run.sh --jobs 4
```

Run tests matching a regex inside the default `policy + surface` batch:

```bash
./tests/run.sh --filter 'container sockets'
```

Run a regex inside a specific suite:

```bash
./tests/run.sh policy --filter 'docker socket'
```

Run a single test file directly with Bats:

```bash
bats tests/policy/integrations/docker.bats
bats tests/e2e/codex.bats
```

Other useful ad hoc flags during development:
- `--abort` to stop on the first failure
- `-x` to trace shell execution
- `--verbose-run` to print `run` output by default
- `--show-output-of-passing-tests` when you want to inspect passing test output too

## Strategy

Tests are organized into three suites under `tests/`:

- `policy/`: rule enforcement, profile composition, runtime behavior, and workdir/integration contracts
- `surface/`: CLI and packaged-artifact public contract
- `e2e/`: tmux-driven startup/readiness and prompt-roundtrip checks for agent TUIs

Suite infrastructure stays at the `tests/` root:

- `run.sh`
- `setup_suite.bash`
- `test_helper.bash`

The helpers in [setup_suite.bash](setup_suite.bash) and [test_helper.bash](test_helper.bash) are designed to test the distributed artifact as a standalone file, not as a repo-relative wrapper.

- The suite copies `dist/safehouse.sh` into a managed temp root once per `bats` run.
- That staged copy is the file under test, which helps catch hidden assumptions about the repository layout.
- The per-test helper changes into `SAFEHOUSE_WORKSPACE` by default, so tests model real CLI usage instead of invoking the wrapper from the repo root.
- Paths outside the workspace that should be denied or require explicit grants are created under a separate home-scoped external root.
- Each test also runs with a deterministic fake `HOME` by default. Tests that truly need the real user home for host-installed integrations should opt in explicitly via `SAFEHOUSE_HOST_HOME`.

## Writing Tests

### Pick the smallest useful contract

- Keep tests in the most specific topic file that matches the behavior under test.
- Prefer one file per feature or integration, with multiple tests inside that file.
- Split a file only when it becomes too large, too broad, or starts covering multiple distinct contracts.
- Prefer one behavior contract per `@test`. If a test is asserting multiple unrelated axes, split it.
- Avoid tests that only restate behavior already covered elsewhere. If a new integration test only proves that "a path becomes readable", it is usually too weak unless that exact path is the contract.

### Prefer the default fake HOME

- Each test already runs with a deterministic fake `HOME`.
- For most home-scoped tests, just use `$HOME` and create fixtures under it.
- Use `sft_fake_home` only when one test needs a second independent home tree or needs to compare two different homes explicitly.
- Use `SAFEHOUSE_HOST_HOME` only for explicit host-integration tests that truly need the real user home, such as installed launcher state or real user-scoped sockets/config.
- When a host-home integration test does an outside-sandbox precheck, use the same `HOME` value for the in-sandbox execution path too.

### Prefer source-marker assertions for profile composition

- When the question is "was the right profile included?", assert on profile source markers with `sft_assert_includes_source` and `sft_assert_omits_source`.
- Use `#safehouse-test-id:` markers for synthetic chunks that are assembled in shell rather than sourced from a profile file.
- Do not assert individual rules from an included profile unless the exact rule shape is itself the contract or a security boundary.

Good:

```bash
@test "enable=docker includes the docker allow profile after the core deny profile" {
  local profile
  profile="$(safehouse_profile --enable=docker)"

  sft_assert_includes_source "$profile" "50-integrations-core/container-runtime-default-deny.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/docker.sb"
}
```

Usually avoid:

```bash
sft_assert_contains "$profile" '(remote unix-socket (path-literal "/var/run/docker.sock"))'
```

### Prefer real runtime smoke tests for integrations

- If an integration exists to make a real tool usable, test the tool when practical.
- Skip cleanly when the host dependency is unavailable.
- Precheck outside the sandbox first when host state may be missing or broken, then run the same flow inside Safehouse.
- Keep the outside-sandbox precheck and the in-sandbox command as close as possible: same binary, same meaningful args, same HOME/cwd assumptions.
- Prefer a stable public target such as `https://example.com` for networked smoke tests.
- If no meaningful real-binary smoke exists yet, use a weaker path-level test only when that path access is itself the contract or the best available proxy.

Good integration pattern:

```bash
@test "enable=agent-browser can open example.com and read the page title" {
  local session_name

  sft_require_cmd_or_skip agent-browser
  session_name="safehouse-agent-browser-${BATS_TEST_NUMBER}-$$"

  run safehouse_ok --enable=agent-browser -- /bin/sh -c '
    session_name="$1"
    cleanup() {
      agent-browser --session "$session_name" close >/dev/null 2>&1 || true
    }
    trap cleanup EXIT

    agent-browser --session "$session_name" open https://example.com >/dev/null &&
      agent-browser --session "$session_name" wait --load networkidle >/dev/null &&
      agent-browser --session "$session_name" get title
  ' _ "$session_name"
  [ "$status" -eq 0 ]
  sft_assert_contains "$output" "Example Domain"
}
```

### Use the helpers first

- Prefer `safehouse_ok` for successful executions.
- Prefer `safehouse_denied` for expected denials.
- Prefer `safehouse_profile` for generated-profile assertions.
- Prefer `safehouse_run` when a test needs raw stdout or an exact exit code from the staged wrapper.
- Prefer `safehouse_ok_env`, `safehouse_denied_env`, and `safehouse_profile_env` when a test needs real `env` semantics such as `-u HOME` or multiple `env`-style overrides around the staged wrapper.
- When using `run`, prefer `safehouse_run` for raw wrapper behavior and `run safehouse_ok -- ...` only when you need stdout from a successful execution path.
- For temporary environment overrides on helper calls, use shell assignment syntax: `HOME="$fake_home" safehouse_ok -- ...`.
- Avoid writing ad hoc setup or cleanup under the real host home. Prefer `SAFEHOUSE_WORKSPACE`, `SAFEHOUSE_EXTERNAL_ROOT`, the default fake `HOME`, and `sft_fake_home`.
- Invoke `"$DIST_SAFEHOUSE"` directly only when the test is explicitly about the staged file as a file or artifact, not its CLI behavior.

### Prefix policy-only and execution tests

- Prefix a test title with `[POLICY-ONLY]` when it only validates generated policy/profile content and does not execute a wrapped command.
- Prefix a test title with `[EXECUTION]` when it exercises the actual binary or app under test through Safehouse and asserts runtime behavior.
- In integration files, `[EXECUTION]` means using the real tool itself, not a generic `cat`, `ls`, or `stat` probe over the paths its profile grants.
- If a test only validates path-level access with generic file utilities, leave it unprefixed even if it runs through Safehouse.
- If the real integration binary is unavailable or unusable on the host, prefer a host-side precheck followed by `skip` instead of falling back to a fake execution test.
- Leave mixed tests or pure CLI/packaging checks unprefixed when neither label is a clean fit.

### Keep file flow consistent

- In files that mix structure and runtime checks, put `[POLICY-ONLY]` tests first, then path-level/runtime boundary checks, then `[EXECUTION]` smokes.
- Put small local helper functions at the end of the file after the `@test` blocks.
- Prefer the same fixture shape across related tests in one file unless the contract requires a different setup.

## Managed Roots

The suite setup manages one suite-scoped root and the test helper manages two per-test roots. Teardown only removes those exact roots.

- `SAFEHOUSE_SUITE_ROOT`
  Holds the staged `safehouse.sh` copy for the full bats run.

- `SAFEHOUSE_WORKSPACE_ROOT`
  Holds the per-test workspace tree. This lives under `BATS_TEST_TMPDIR` because it is just scratch state for the current test run.

- `SAFEHOUSE_WORKSPACE`
  The default current working directory for tests that validate normal workdir behavior.

- `SAFEHOUSE_DEFAULT_FAKE_HOME`
  The per-test fake home used as the default `HOME`.

- `SAFEHOUSE_HOST_HOME`
  The original user home from the unsandboxed host shell. Use this only for explicit host-integration tests that need real installed state.

- `SAFEHOUSE_FAKE_HOME_ROOT`
  The parent root that owns any extra fake homes created by `sft_fake_home`.

- `SAFEHOUSE_EXTERNAL_ROOT`
  Holds directories outside the workspace whose access should depend on Safehouse profile rather than the broad default allow rules for `/tmp`.

The split is intentional: the default Safehouse profile already allows broad access to `/tmp`, `/private/tmp`, and `/var/folders`, so temp-only paths are not reliable deny targets.

## Helper API

### Lifecycle

- `setup_suite.bash` — owns host checks and one-time dist staging for the full bats run.
- `test_helper.bash` — loaded by nested policy/surface tests via `load ../../test_helper.bash`, and directly by E2E tests before `load tmux_utils.bash` and `load agent_tui_harness.bash`. Owns per-test setup/teardown, changes into the default workspace, and provides the helpers below.

### Running safehouse

- **`safehouse_ok <args...>`** — runs the staged dist artifact; the test fails if it exits non-zero.
- **`safehouse_run <args...>`** — runs the staged dist artifact under Bats `run` and captures `$status` / `$output` for raw CLI assertions.
- **`safehouse_ok_env <env...> -- <args...>`** — runs the staged dist artifact with explicit `env`-style overrides or unsets before the Safehouse args.
- **`safehouse_ok_in_dir <dir> <args...>`** — runs the staged dist artifact from a specific working directory when cwd selection is part of the contract.
- **`safehouse_denied <args...>`** — runs the staged dist artifact and asserts non-zero exit.
- **`safehouse_denied_env <env...> -- <args...>`** — env-aware variant of `safehouse_denied`.
- **`safehouse_denied_in_dir <dir> <args...>`** — working-directory variant of `safehouse_denied`.
- **`safehouse_profile <args...>`** — runs the staged dist artifact with `--stdout` and prints the generated profile to stdout. Capture the output in a variable and prefer asserting on `;; Source:` markers or `#safehouse-test-id:` markers.
- **`safehouse_profile_env <env...> -- <args...>`** — env-aware variant of `safehouse_profile`.
- **`safehouse_profile_in_dir <dir> <args...>`** — working-directory variant of `safehouse_profile` for tests that depend on cwd-based detection such as git-root or trusted workdir config loading.
- Use `run safehouse_ok -- ...` only when you need to assert on `$output` from a successful helper-wrapped execution.
- Do not use `run safehouse_ok` or `run safehouse_denied` just to check success or failure; `safehouse_ok` and `safehouse_denied` already validate that.
- Use `HOME=... safehouse_ok -- ...` for simple temporary overrides, and `HOME=... run safehouse_ok -- ...` when you also need captured output.
- Use `safehouse_*_env` only when you need `env`-style behavior such as `-u HOME`.

### Assertions

- **`sft_assert_contains <haystack> <needle>`** — asserts the string contains the needle.
- **`sft_assert_not_contains <haystack> <needle>`** — asserts the string does not contain the needle.
- **`sft_assert_includes_source <haystack> <profile-path>`** — asserts the generated profile includes `;; Source: <profile-path>`.
- **`sft_assert_omits_source <haystack> <profile-path>`** — asserts the generated profile omits `;; Source: <profile-path>`.
- **`sft_assert_file_exists <path>`** — asserts that a regular file exists.
- **`sft_assert_file_content <path> <expected>`** — asserts that a file exists and has the expected full content.
- **`sft_assert_file_includes_source <path> <profile-path>`** — file-backed variant of `sft_assert_includes_source`.
- **`sft_assert_file_omits_source <path> <profile-path>`** — file-backed variant of `sft_assert_omits_source`.
- **`sft_assert_path_absent <path>`** — asserts that a path does not exist.
- **`sft_require_cmd_or_skip <cmd>`** — skips the test if the host dependency is not installed.
- **`sft_require_env_or_skip <VAR>`** — skips the test if the named environment variable is unset or empty.
- **`sft_command_path_or_skip <cmd>`** — prints the resolved command path or skips if the command is unavailable.

### Path helpers

- **`sft_workspace_path <name>`** — returns a path under `SAFEHOUSE_WORKSPACE` (inside the sandbox workdir).
- **`sft_external_dir <label>`** — creates and returns a directory under `SAFEHOUSE_EXTERNAL_ROOT` (outside the sandbox workdir — access depends on profile grants).
- **`sft_external_path <label> <name>`** — creates an external directory and returns a path inside it.
- **`sft_fake_home`** — creates and returns a second fake home under `SAFEHOUSE_FAKE_HOME_ROOT` when one test needs more than the default fake `HOME`.

## Examples

### Runtime behavior test

Test that commands are allowed or denied inside the sandbox:

```bash
@test "default profile keeps a command inside its workspace" {
  local allowed_file blocked_file

  allowed_file="$(sft_workspace_path "notes.txt")" || return 1
  blocked_file="$(sft_external_path "denied" "blocked.txt")" || return 1

  safehouse_ok -- /bin/sh -c "printf '%s' sandboxed > '$allowed_file'"
  sft_assert_file_content "$allowed_file" "sandboxed"

  safehouse_denied -- /bin/sh -c "touch '$blocked_file'"
  sft_assert_path_absent "$blocked_file"
}
```

### Profile content test

Test that the generated sandbox profile includes the expected profile layers:

```bash
@test "enable=docker includes the docker allow profile after the core deny profile" {
  local profile
  profile="$(safehouse_profile --enable=docker)"

  sft_assert_includes_source "$profile" "50-integrations-core/container-runtime-default-deny.sb"
  sft_assert_includes_source "$profile" "55-integrations-optional/docker.sb"
}
```

### Skippable runtime test

When a test depends on optional host software, use `skip`:

```bash
@test "java compiles and runs a class inside the sandbox" {
  command -v javac >/dev/null 2>&1 || skip "javac is not installed"

  printf 'public class Hi { public static void main(String[] a) { System.out.println("ok"); } }\n' \
    > "$(sft_workspace_path "Hi.java")"

  safehouse_ok -- /bin/sh -c "cd '$SAFEHOUSE_WORKSPACE' && javac Hi.java && java Hi"
}
```

### Host-home integration test

When a test truly depends on real user-scoped host state, opt in explicitly:

```bash
@test "docker cli can reach the configured daemon only when enable=docker is set" {
  local docker_bin

  docker_bin="$(sft_command_path_or_skip docker)" || return 1

  HOME="$SAFEHOUSE_HOST_HOME" "$docker_bin" version >/dev/null 2>&1 || skip "docker daemon precheck failed outside sandbox"

  HOME="$SAFEHOUSE_HOST_HOME" safehouse_denied -- "$docker_bin" version
  HOME="$SAFEHOUSE_HOST_HOME" safehouse_ok --enable=docker -- "$docker_bin" version >/dev/null
}
```

### Linking to issues

When a test guards against a known regression, put the issue URL as an inline comment on the `@test` line:

```bash
@test "copilot command auto-injects keychain profile" { # https://github.com/eugene1g/agent-safehouse/issues/5
  local profile
  profile="$(safehouse_profile -- copilot)"

  sft_assert_includes_source "$profile" "55-integrations-optional/keychain.sb"
}
```

## Conventions

Keep `local` declarations separate from command substitutions:

```bash
local blocked_file
blocked_file="$(sft_external_path "denied" "blocked.txt")" || return 1
```

Avoid this pattern:

```bash
local blocked_file="$(sft_external_path "denied" "blocked.txt")"
```

Reason: `local var="$(cmd)"` can mask failures from `cmd`, because `local` itself may still return success. Declaring the variable first and assigning on the next line keeps helper failures visible and makes the test stop reliably.

Prefer local helper functions at the end of the file, after the `@test` blocks, unless a different layout is clearly easier to read.

Why the roots are split:

- `SAFEHOUSE_WORKSPACE_ROOT` is just per-test scratch space for the process cwd and related working files. It can safely live under `BATS_TEST_TMPDIR`.
- `SAFEHOUSE_EXTERNAL_ROOT` holds the paths outside the workspace whose access semantics are actually under test. It must live outside the broadly allowed temp directories, otherwise deny and read-only assertions become meaningless.
- `sft_external_dir` exists to make that distinction explicit in the tests: when a path comes from `sft_external_dir`, readers should assume it is outside the workspace and profile-sensitive, not just arbitrary scratch storage.
