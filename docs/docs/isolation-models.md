# Isolation Models: VMs vs Containers vs Safehouse

Safehouse is not a VM replacement. It is a low-friction host-level containment layer for local agent workflows on macOS.

## Quick Comparison

| Model | Isolation Boundary | Kernel Separation | Default Filesystem Exposure | Typical Overhead | Compatibility With Local Agent Workflows | Best For |
|------|---------------------|-------------------|-----------------------------|------------------|------------------------------------------|----------|
| VM | Guest OS boundary | Yes (separate kernel) | Guest filesystem only, host mounts explicit | Highest | Lower (requires guest setup, syncing, tool duplication) | Strong adversarial isolation |
| Container | Process namespace/cgroup boundary | No (shared host kernel, unless inside VM runtime) | Container filesystem; host binds explicit | Low to medium | Medium (good for app workloads, weaker fit for desktop-hosted agents) | Reproducible app/runtime packaging |
| Safehouse (`sandbox-exec`) | macOS Seatbelt policy on host processes | No (shared host kernel) | Deny-first host paths, explicit allow grants | Very low | High (native host tooling and agent CLIs/apps) | Practical blast-radius reduction for local coding agents |

## Security Properties

- **VMs** provide the strongest boundary and are the preferred choice when defending against determined host-level compromise.
- **Containers** are strong for packaging and controlled runtime environments, but are not equivalent to full VM isolation.
- **Safehouse** focuses on least-privilege path and service access control for native macOS workflows with minimal friction.

## Practical Tradeoffs

- Safehouse keeps your existing shell/toolchain workflows mostly unchanged.
- VMs usually require separate tool installs, workspace sync strategy, and credential setup.
- Containers can work well for non-GUI agents, but many desktop-hosted and mixed local workflows are less natural.

## Recommended Positioning

Use Safehouse when you want strong day-to-day risk reduction with minimal workflow disruption.

If you need stronger adversarial isolation, layer models:

1. Run your agent workflow inside a VM.
2. Run Safehouse inside that VM for least-privilege path policy inside the guest.

This gives stronger boundary isolation plus granular in-guest policy control.
