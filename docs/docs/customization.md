# Customization

## Common Extension Points

- Add credential denials in custom `.sb` overlays loaded with `--append-profile`.
- Adjust network behavior in `profiles/20-network.sb`.
- Modify shared cross-agent rules in `profiles/40-shared/`.
- Add agent profiles in `profiles/60-agents/`.
- Add desktop app profiles in `profiles/65-apps/`.
- Add toolchain profiles in `profiles/30-toolchains/`.

## Safety Guidelines

- Prefer least privilege and narrow path grants.
- Avoid broad `subpath` grants unless required.
- Keep hard deny rules in appended profiles when you need final precedence.
- If worktrees are created under a stable parent and you want future worktrees available without restarting Safehouse, grant that parent with `--add-dirs-ro` for the same cross-worktree read behavior as the default worktree snapshot, or `--add-dirs` when broader write access is intentional.
- Add or update tests for policy behavior changes.
- Regenerate dist artifacts after profile/runtime logic changes:

```bash
./scripts/generate-dist.sh
```
