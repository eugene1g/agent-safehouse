# Changelog

## [Unreleased]

### Upgrade Notes

- No special notes.

### Changed Sandboxing Profiles

- No profiles changed.

## [0.8.0] - 2026-03-27

### Features

- Added explicit `--enable=keychain` support so plugin-backed helper flows, including `opencode-claude-auth`, can opt into macOS Keychain access even when no built-in Safehouse profile auto-detects the requirement.

### Chores

- Added regression coverage and `--explain`/packaging assertions for explicit keychain enablement, and documented when to use `--enable=keychain` for plugin-driven credential flows.

### Thanks

- @ChristianKniep surfacing the plugin-backed OpenCode keychain access gap fixed in this release in [#71](https://github.com/eugene1g/agent-safehouse/issues/71).

### Changed Sandboxing Profiles

- [`keychain.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.7.0...v0.8.0#diff-a2a140b0b9d2a0c8819f343d379ecafb454d0f47b8b565b18a93a0b7d7bddaae): Made the Keychain integration explicitly user-enableable while keeping auto-injection for profiles that declare it as a dependency.

## [0.7.0] - 2026-03-27

### Upgrade Notes

- No special notes.

### Features

- `chromium-headless` now supports branded Google Chrome on macOS by allowing the `com.google.Chrome.*` Mach services and scoped Crashpad state needed for headless launches.

### Bug Fixes

- `shell-init` can now follow Homebrew-installed completion symlinks that resolve into GUI app bundle `Contents/Resources` paths, eliminating noisy `operation not permitted` output from zsh `compinit` without granting full app-bundle reads.

### Chores

- Added regression coverage for Homebrew GUI-app completion symlinks and refreshed the Claude Code end-to-end startup matcher so the macOS TUI suite stays aligned with the current Claude welcome screen.

### Thanks

- @thegalexc adding branded Google Chrome headless support in [#70](https://github.com/eugene1g/agent-safehouse/pull/70).
- @pingvinen surfacing the Homebrew GUI completion noise fixed in this release in [#67](https://github.com/eugene1g/agent-safehouse/issues/67).

### Changed Sandboxing Profiles

- [`chromium-headless.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.6.0...v0.7.0#diff-9f6dc8d781704105880e2f6841f5783b98bf8e483bc6454f3ca1b9560c3fcdc8): Added branded Google Chrome Mach port and Crashpad access so headless Chrome can launch under `chromium-headless` instead of crashing during rendezvous or crashpad initialization.
- [`shell-init.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.6.0...v0.7.0#diff-b4e8dd0043aab271dfa6bf04dec2110baca715ff9a4d6032d22f32ea88a3dd08): Allowed shell startup flows to follow Homebrew GUI-app completion symlinks into `Contents/Resources` while keeping access scoped to completion-like files.

## [0.6.0] - 2026-03-23

### Upgrade Notes

- Claude's VS Code external-editor handoff now defaults to reuse-only mode. If you rely on `Ctrl+G` to cold-start VS Code from a plain `safehouse -- claude ...` session, add `--enable=vscode`. Existing `EDITOR` or `VISUAL` values still take precedence.

### Features

- Added automatic profile selection for the OpenAI Codex Desktop app, including its app bundle, app state paths, Electron runtime dependencies, preference domain, and Keychain-backed sign-in surface.
- `safehouse --explain` now reports the invoked command, profile target command, host and execution `PATH` matches, and a ready-to-run sandbox denial log hint to make command-resolution debugging much easier.

### Bug Fixes

- Restored Node/npm workflows under `fnm` by allowing the metadata traversal and install roots used by `fnm_multishells` shims and the macOS `~/Library/Application Support/fnm` layout.
- Safehouse now skips stale linked-worktree admin entries during startup and `--explain`, avoiding `realpath` failures when old worktree metadata is left behind.
- Home-scoped path grants now resolve symlink targets for profile-owned paths, which fixes Opencode bootstrap when `~/.config/opencode` points at a dotfiles-managed directory.
- Refined Claude's VS Code editor handoff so the default path reuses an already-running VS Code instance, while the explicit `--enable=vscode` cold-start path launches detached with an isolated Safehouse-managed profile.

### Chores

- Added regression coverage for Codex Desktop bundle detection, `fnm` multishell and App Support Node workflows, Opencode symlinked XDG paths, stale worktree handling, `--explain` command-resolution output, and the new Claude/VS Code editor-shim modes.
- Updated the docs around `--enable=vscode`, Claude external-editor handoff, and the default preservation of `EDITOR` and `VISUAL` in sanitized mode.

### Thanks

- @Kola50011 adding the OpenAI Codex Desktop app profile in [#62](https://github.com/eugene1g/agent-safehouse/pull/62).
- @wkirby surfacing the `fnm`-backed Node/npm resolution failures fixed in this release in [#13](https://github.com/eugene1g/agent-safehouse/issues/13).
- @benjivm surfacing the Opencode symlinked XDG-path bootstrap failure fixed in this release in [#61](https://github.com/eugene1g/agent-safehouse/issues/61).
- @rublev surfacing the Claude-to-VS Code handoff behavior tightened in this release in [#46](https://github.com/eugene1g/agent-safehouse/issues/46).

### Changed Sandboxing Profiles

- [`node.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.5.2...v0.6.0#diff-94a5c97eafdc81daa5ae1e467d55943959ac559f14c59d8c3af198e716ad311f): Added `fnm` install-root and multishell metadata access so Node child-process `PATH` resolution and npm shims work for both XDG and macOS App Support layouts.
- [`vscode.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.5.2...v0.6.0#diff-471f0b2ad5b04157955a47cc887440730950d6b71a0e9ff5181d66a9f95bb515): Made the full VS Code desktop/editor integration explicitly opt-in so cold-start editor handoff only happens behind `--enable=vscode`.
- [`claude-code.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.5.2...v0.6.0#diff-caf651f708e889ca1935c3c382d551ccbed8eb81f611fab631829993fca117b7): Split core Claude CLI access from a narrow metadata-only VS Code reuse surface so `Ctrl+G` can still hand off to an already-running VS Code without granting full app startup by default.
- [`opencode.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.5.2...v0.6.0#diff-cd89eca750d855f552c01fc868cdf1400d4c482fbf93e47c50425e84f470fa5a): Added the parent XDG directory allowances Opencode needs to bootstrap its default state roots, which now also works when the config path is symlinked into a dotfiles tree.
- [`codex-app.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.5.2...v0.6.0#diff-dfd037f71c747a82d9532750cd5ccfd3e79ffbcb83881c0acc599d6ef2072697): Added a dedicated OpenAI Codex Desktop app profile covering the app bundle, Codex state directories, preference domain, app-specific Mach services, and its Electron/keychain dependencies.
- [`vscode-app.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.5.2...v0.6.0#diff-e36692fe5535f876b390e4776cf042e90b6c47a6fe5370200f4013d0ead65cfb): Added isolated Safehouse-managed Claude editor cache roots and `/Applications` traversal so the explicit VS Code cold-start path can launch cleanly without reusing the user's normal VS Code profile.

## [0.5.2] - 2026-03-18

### Upgrade Notes

- No special notes.

### Bug Fixes

- The default Apple Command Line Tools profile now includes `ranlib` plus common compiler aliases and low-risk archive and inspection helpers, restoring `cargo build` and other static-archive workflows that implicitly invoke `ranlib` inside the sandbox.

### Chores

- Added execution coverage for `ar` archive creation and Rust `cargo build` of a `staticlib`, and installed a stable Rust toolchain in the macOS test workflow so this regression is exercised in CI.

### Thanks

- @Sixeight surfacing the missing `ranlib` allowance behind the Rust staticlib failure fixed in this release in [#57](https://github.com/eugene1g/agent-safehouse/issues/57).

### Changed Sandboxing Profiles

- [`apple-toolchain-core.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.5.1...v0.5.2#diff-2e94e17a0cc2897fd42614396f336402efeab2c61bf5164883c16af81389fb2b): Added `ranlib`, common compiler aliases, and related low-risk inspection helpers to the curated CLT allowlist so static archive builds work by default without broadening access to debugger tooling.

## [0.5.1] - 2026-03-17

### Upgrade Notes

- No special notes.

### Bug Fixes

- Built-in absolute `file-read*` paths now resolve macOS compatibility symlinks such as `/private/etc/resolv.conf` and `/private/etc/localtime`, while keeping `xcode-select` pointer symlinks explicit so the default sandbox does not silently inherit a host-specific full Xcode bundle.
- `--enable=lldb` now covers versioned/full Xcode app bundles and Apple private developer frameworks needed on hosts where LLDB loads Xcode-backed developer resources instead of only Command Line Tools.
- Bundler can now read the macOS system default gemspec catalog under `/Library/Ruby/Gems`, restoring read-only Bundler commands such as `bundle --version` inside the sandbox.

### Chores

- Added regression coverage for built-in symlink-target rendering, `xcode-select` pointer exceptions, LLDB on Xcode-backed hosts, Bundler system gem reads, and file-symlink CLI grants.
- Clarified the README and policy/distribution docs around built-in path resolution and its current scope.

### Thanks

- @technicalpickles surfacing the built-in symlink-resolution gap fixed in this release in [#54](https://github.com/eugene1g/agent-safehouse/issues/54).

### Changed Sandboxing Profiles

- [`ruby.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.5.0...v0.5.1#diff-e6c5527826f7eeab06d5ebadd9b3a6be91aa1b5c88874d651f9a60f758a1554e): Added read-only `/Library/Ruby/Gems` access so Bundler can enumerate macOS default gems without needing write access to system Ruby state.
- [`lldb.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.5.0...v0.5.1#diff-9b1a1aee4fcd6c90b56db204faf4c05fcb1bec258503143aeb2c87d53b6dfdbd): Broadened LLDB's read-only Xcode coverage to include versioned app bundles and private developer frameworks needed when hosts select a full Xcode install.

## [0.5.0] - 2026-03-17

### Upgrade Notes

- Safehouse now keeps the default workdir at the exact invocation directory instead of walking up to an enclosing Git root. This avoids accidentally widening access when you launch from a deeply nested folder inside a larger repo or beneath a home-directory Git tree. If you intentionally want broader repo access from a nested launch, grant it explicitly with `--add-dirs=/path/to/repo` or `--add-dirs-ro=/path/to/repo`.

### Features

- Added a reusable `microphone` optional integration for microphone capture via TCC, CoreAudio, CMIO, and the Apple HDA input path.
- Claude Code now pulls that shared microphone integration automatically for voice mode instead of embedding microphone allowances directly in the agent profile.

### Bug Fixes

- Ancestor `.git` directories without real repository metadata no longer widen the default workdir.

### Chores

- Added regression coverage for invocation-scoped workdir behavior, nested linked-worktree launches, trusted `.safehouse` discovery, microphone integration, and PATH probing.
- Clarified the docs and machine-readable wrapper guidance so the default workdir contract matches the runtime behavior.

### Thanks

- @schmijos surfacing the default workdir auto-walk problem fixed in this release in [#52](https://github.com/eugene1g/agent-safehouse/issues/52).

### Changed Sandboxing Profiles

- [`10-system-runtime.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.4.0...v0.5.0#diff-c27b7abd9dcf3cd976d593264e5d14dcfc2e10422b3dcdebb8bb9dbee4d611c8): Added narrow `~/.local/bin` traversal and listing access so PATH probing can find user-installed helpers without reading their contents.
- [`microphone.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.4.0...v0.5.0#diff-dbfccfaa1929f95619d832f800692ab0400315aa6e601f0f2f2f1a6bd37fbda9): Added a reusable microphone integration covering TCC, CoreAudio, CMIO, and Apple HDA input access for voice-enabled agent workflows.
- [`claude-code.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.4.0...v0.5.0#diff-caf651f708e889ca1935c3c382d551ccbed8eb81f611fab631829993fca117b7): Switched Claude Code voice mode to depend on the shared `microphone` integration instead of carrying microphone access inline.

## [0.4.0] - 2026-03-16

### Upgrade Notes

- SSH agent authentication is now opt-in. If you previously relied on `SSH_AUTH_SOCK` inside Safehouse without extra flags, add `--enable=ssh`.
- Packaged releases now ship only `dist/safehouse.sh`. If you consumed `dist/profiles/*` or the generated Claude launcher commands, switch to `dist/safehouse.sh` or generate what you need from source.
- Linked Git worktrees are now auto-detected at launch and sibling worktrees become readable by default. If you want stricter single-worktree visibility, narrow that with `--append-profile` deny rules or disable automatic workdir grants and use explicit path flags.

### Features

- Added linked-worktree support by default: when the effective workdir is a Git worktree root, Safehouse now grants shared Git metadata access for that worktree and read-only visibility into the other existing worktrees for the same repo.
- Expanded Chrome-family browser support on macOS: `chromium-full` now covers system Google Chrome launches, `playwright-chrome` injects `PLAYWRIGHT_MCP_SANDBOX=false`, and `agent-browser` now depends on the full Chrome allowances used by Chrome for Testing.
- Sandboxed commands now get `APP_SANDBOX_CONTAINER_ID=agent-safehouse` by default unless the caller or environment already set a value.

### Bug Fixes

- GitHub Copilot CLI can now bootstrap its startup cache under `~/Library/Caches/copilot`, allowing the packaged launcher to start cleanly on first run.
- SSH agent sockets are denied by default unless `--enable=ssh` is set, closing a gap where agent-backed SSH auth could still work through `network-outbound`.

### Chores

- Reworked the shell/runtime internals into staged CLI, policy, and execution modules, and rebuilt the release packaging around a single embedded `dist/safehouse.sh`.
- Added much broader policy, surface, packaging, and tmux-driven end-to-end coverage to validate behavior and improve release predictability.
- Clarified the default HOME sandbox behavior in the docs, including what `HOME_DIR` does and what the base policy still does not grant.

### Thanks

- @clkao adding default `APP_SANDBOX_CONTAINER_ID` injection in [#43](https://github.com/eugene1g/agent-safehouse/pull/43).
- @prabirshrestha driving the linked Git worktree support in [#37](https://github.com/eugene1g/agent-safehouse/issues/37).
- @eikes surfacing the Copilot startup failure fixed in this release in [#47](https://github.com/eugene1g/agent-safehouse/issues/47).
- @Bouke prompting the clearer HOME behavior docs in [#11](https://github.com/eugene1g/agent-safehouse/issues/11).
- @mtford90 surfacing the Agent Browser and Playwright support gap addressed in this release in [#25](https://github.com/eugene1g/agent-safehouse/issues/25).

### Changed Sandboxing Profiles

- [`00-base.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-02c38ee50d8f4793102a508750ddd9d62254a5bef2a70f857fdfdb4f9677acb9): Clarified the `HOME_DIR` base-profile comments so the generated policy docs match the current render pipeline.
- [`ssh-agent-default-deny.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-d5ee2399dc6de3abc866607371d90c0e6a0748d68ab1f31f1b327dc32dd6ea72): Added default-deny rules for launchd and `~/.ssh/agent/*` sockets so SSH agent credential use stays opt-in until `--enable=ssh`.
- [`worktree-common-dir.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-1e29ea236a9b67bfd5f5ab1c7049e9737e9d978f64d4d4c89be7b6974268b8c1): Added runtime-generated grants for a linked worktree's shared Git common dir so refs and index metadata outside the selected workdir keep working.
- [`worktrees.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-17e3dbc495bdbdf1e1e848162114ff08e5a8d92aa06de242f72cde411f3d108a): Added runtime-generated read-only grants for sibling linked worktrees so cross-worktree inspection works by default.
- [`agent-browser.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-51e021c04a1aa945867c71f383a570f1212b5011f7c23a4166781df6b58a0fe3): Switched the dependency to `chromium-full` so the default macOS Agent Browser path works with Chrome for Testing.
- [`chromium-full.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-d542719401c3da098b9f40fa32c7f156af327e4ac8e980ef85b48d73fe7c2e82): Expanded Chrome allowances to cover the system Google Chrome app bundle, prefs, Crashpad state, and Mach rendezvous used during full-browser launches.
- [`keychain.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-a2a140b0b9d2a0c8819f343d379ecafb454d0f47b8b565b18a93a0b7d7bddaae): Clarified that Keychain access is auto-injected transitively from dependent profiles.
- [`macos-gui.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-3ddea98ee8aa3646b2cb0d688dac05b16fdc45a52697fcf2e38bd0ab26c3600c): Added an explicit clipboard dependency so GUI apps automatically pick up pasteboard IPC.
- [`playwright-chrome.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-71143f8c791e41abf6b58108b3be4fac283ce630871a13708abeee848126e57b): Added a Playwright Chrome-channel profile that pulls `chromium-full` and injects `PLAYWRIGHT_MCP_SANDBOX=false`.
- [`ssh.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-27e3f65a24bff6925a3e1e6fca94111fa57ca9cd73e662b4a78b1480804f097d): Extended SSH access to newer `~/.ssh/agent/*` socket layouts and unix-socket connections used by modern macOS ssh-agent setups.
- [`amp.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-7aad0697a20f2d7bbd6001edf23e5259590ca1e4088d5f6f98f4d4ee5ca622ac): Added `/home` compatibility-root reads so Amp startup probes do not fail on macOS path-resolution quirks.
- [`claude-code.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-caf651f708e889ca1935c3c382d551ccbed8eb81f611fab631829993fca117b7): Added the `claude` launcher alias and browser-native-messaging dependency so Claude Code auto-selects correctly and `claude --chrome` works.
- [`copilot-cli.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-4c4b4a874f02531e9888d2fd68d6a7134dd67d9f41db0a08535679e7bd6f8de6): Added the `copilot` launcher alias and writable Copilot cache access so the packaged CLI can bootstrap cleanly.
- [`cursor-agent.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-8709a949dfd9b6444711734ba983308c5ba7728d6b102a82831b023275454d6a): Added the `agent` launcher alias used by some Cursor Agent installs so Cursor profile selection auto-matches more reliably.
- [`kilo-code.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-5624593fba664d15e46adfb4928f77bc0c91963eebdd8b0a2d2aeb6e80e33faa): Added the `kilo` launcher alias so Kilo Code profile selection works across more install names.
- [`claude-app.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-e3ba6b6dab397c0aa1f952d3488cffaa0119bb213d3e73fc3ca2ec39ec5f1ea7): Made Claude Desktop depend on the shared `claude-code` profile so it inherits Claude Code state, keychain access, and the Chrome bridge through one contract.
- [`vscode-app.sb`](https://github.com/eugene1g/agent-safehouse/compare/v0.3.1...v0.4.0#diff-e36692fe5535f876b390e4776cf042e90b6c47a6fe5370200f4013d0ead65cfb): Simplified VS Code's dependency chain so Electron now pulls macOS GUI access transitively while keychain access stays explicit.

## [0.3.1] - 2026-03-12

### Bug Fixes

- Default sanitized execution now preserves common non-secret proxy, TLS, and browser-control environment variables, including `HTTP_PROXY`, `HTTPS_PROXY`, `NO_PROXY`, lowercase proxy variants, `NODE_EXTRA_CA_CERTS`, and `NO_BROWSER`.
- Tightened Java toolchain sandboxing so system `/Library/Java` runtimes stay read-only while per-user `~/Library/Java` installs remain writable, preventing accidental writes to globally installed JDKs.

### Changed Sandboxing Profiles

- [`profiles/30-toolchains/java.sb`](https://github.com/eugene1g/agent-safehouse/blob/v0.3.1/profiles/30-toolchains/java.sb): Split system and user Java grants so globally installed runtimes are read-only while per-user Java state stays writable.

## [0.3.0] - 2026-03-12

### Features

- New `--enable=xcode` integration: read-only access to Xcode developer roots, app bundles, and Command Line Tools; read/write access to per-user DerivedData, CoreSimulator, XCTestDevices, and CoreDevice state; CoreSimulator and CoreDevice mach service lookups. Enables `xcodebuild`, `simctl`, and `devicectl` under the sandbox.
- `SDKROOT` is now preserved in the default sanitized environment, so Xcode SDK-backed compilation works without `--env`.
- Added `safehouse update [--head]` subcommand for standalone installs to self-update from GitHub release assets or the latest `main` build.

### Bug Fixes

- Node toolchain profile now includes `~/.cache/puppeteer` alongside Playwright and Cypress cache paths.

### Chores

- Bumped NPM docs-site dependencies.
- Refactored live-test denial patterns into shared infrastructure.

### Changed Sandboxing Profiles

- [`profiles/55-integrations-optional/xcode.sb`](https://github.com/eugene1g/agent-safehouse/blob/v0.3.0/profiles/55-integrations-optional/xcode.sb): New profile granting Xcode developer roots plus scoped per-user build and simulator state.
- [`profiles/30-toolchains/node.sb`](https://github.com/eugene1g/agent-safehouse/blob/v0.3.0/profiles/30-toolchains/node.sb): Added Puppeteer cache path (`~/.cache/puppeteer`).

## [0.1.0] - 2026-03-11

### Upgrade Notes

- First tagged release.
