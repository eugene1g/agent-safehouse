# Agent Safehouse

[![Tests (macOS)](https://github.com/eugene1g/agent-safehouse/actions/workflows/tests-macos.yml/badge.svg)](https://github.com/eugene1g/agent-safehouse/actions/workflows/tests-macos.yml)
[![E2E (TUI Agent via tmux)](https://github.com/eugene1g/agent-safehouse/actions/workflows/e2e-agent-tui-macos.yml/badge.svg)](https://github.com/eugene1g/agent-safehouse/actions/workflows/e2e-agent-tui-macos.yml)
[![License: Apache 2.0](https://img.shields.io/badge/License-Apache_2.0-blue.svg)](LICENSE)

Sandbox your LLM coding agents on macOS so they can only access the files and integrations they actually need.

Agent Safehouse uses `sandbox-exec` with composable policy profiles and a deny-first model. It supports major coding agents and app-hosted agent workflows while keeping normal development usage practical.

## Philosophy

Agent Safehouse is designed around practical least privilege:

- Start from deny-all.
- Allow only what the agent needs to do useful work.
- Keep developer workflows productive.
- Make risk reduction easy by default.

It is a hardening layer, not a perfect security boundary against a determined attacker.

## Documentation

- Website: [agent-safehouse.dev](https://agent-safehouse.dev)
- Docs: [agent-safehouse.dev/docs](https://agent-safehouse.dev/docs/)
- Policy Builder: [agent-safehouse.dev/policy-builder](https://agent-safehouse.dev/policy-builder)

All detailed documentation (setup, usage, options, architecture, testing, debugging, and investigations) lives in the VitePress docs site.
