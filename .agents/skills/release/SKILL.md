---
name: release
description: "Run the local Agent Safehouse release flow: inspect commits since the last published release, propose the next SemVer version and changelog, present a dry-run for confirmation, then update changelog, publish the GitHub release, and publish the stable Homebrew tap when confirmed."
---

# Release

Use this skill when the user wants changelog text, release notes, or a `CHANGELOG.md` update for Agent Safehouse.
This skill is also the canonical local release workflow for Agent Safehouse.

Historical changelog sections are append-only by default.
Do not rewrite, normalize, or reformat older release entries to match a newer structure unless the user explicitly asks for a changelog migration or cleanup pass.

This skill is responsible for proposing the next release version from the last published release.
The repo-root `VERSION` file is the canonical version source for Agent Safehouse.
Write the selected version into `VERSION` and into the new `CHANGELOG.md` heading unless the user explicitly gives a different target version.
Default to a stable release. Only choose a prerelease version such as `-rc.N` or `-beta.N` when the user explicitly asks for a prerelease.
If the user explicitly gives the target version, honor it even if the default SemVer analysis would have chosen a different bump. In that case, note briefly in the dry run that the version came from an explicit user override.

## Workflow

1. Resolve the baseline release.
   If the user gives a starting version, use it.
   Otherwise:
   - Prefer the latest published stable GitHub release tag from `gh release list --exclude-drafts --exclude-pre-releases`.
   - Ignore draft releases.
   - Ignore prereleases such as `-rc`, `-beta`, and other hyphenated SemVer suffixes unless the user explicitly asks to prepare a prerelease.
   - If GitHub release metadata is unavailable, fall back to the latest stable SemVer git tag.

2. Decide the next SemVer version from the release range.
   Start from the resolved baseline release and choose:
   - `major` for breaking changes, incompatible CLI behavior, removed capabilities, changed defaults that are likely to break existing setups, or sandbox/policy tightening that requires user action to restore a previously supported workflow.
   - `minor` for backward-compatible new features, new integrations, new profiles, new user-visible capabilities, or meaningful expansions of supported workflows.
   - `patch` for bug fixes, non-breaking sandbox/profile corrections, docs, tests, internal cleanup, and other maintenance-only changes.
   - If the range mixes features and fixes but nothing breaking, choose `minor`.
   - If the range is ambiguous and there is no clear breaking change or new feature, choose `patch`.
   - If you choose `major`, explicitly state why in the drafted release notes.
   - If the user explicitly asks for a prerelease, first choose the target stable version using the rules above, then append the requested prerelease suffix such as `-rc.1` or `-beta.1`.
   - If the user explicitly asks for another prerelease in the same series, increment that series from the latest matching non-draft prerelease tag or release, for example `1.4.0-rc.1` to `1.4.0-rc.2`.

3. Collect git context directly.
   Default the target ref to `HEAD` unless the user specifies another tag or commit.
   Treat `dist/` as generated output, not release-note source of truth.
   Do not load `dist/` diffs or `dist/` files into context while evaluating customer-visible changes, choosing the version bump, or drafting changelog bullets.
   Evaluate the original source changes in the rest of the repo instead, especially `bin/`, `bin/lib/`, `profiles/`, `scripts/`, `tests/`, and docs.
   Start with:
   - `git log --reverse --no-merges <from-ref>..<to-ref> --format='%h %s'`
   - `git log --reverse --merges <from-ref>..<to-ref> --format='%h %s'`
   - `git diff --stat <from-ref>..<to-ref> -- . ':(exclude)dist/**'`
   - `git diff --dirstat=files,0 <from-ref>..<to-ref> -- . ':(exclude)dist/**'`
   - `git diff --name-only <from-ref>..<to-ref> -- 'profiles/**/*.sb' 'profiles/*.sb'`
   - `git diff --name-only <from-ref>..<to-ref> -- . ':(exclude)dist/**'`
   Only look at `dist/` after confirmation, during the regeneration and verification stage.

4a. Review anything ambiguous before writing notes.
   Use `git show --stat <sha>` or `git diff <from-ref>..<to-ref> -- <path>` for commits that are not obvious from the subject line.
   When a commit touches both source files and `dist/`, review only the source files and do not open the generated `dist/` portion.
   For any changed sandbox profile, inspect the actual diff before summarizing it.
   Also collect contributor context for shipped work:
   - Extract merged PR numbers from commit subjects, merge commits, or `gh pr list --state merged ...` when needed.
   - Use `gh pr view <num> --json number,title,author,url,closingIssuesReferences`.
   - For any linked or clearly relevant issue, use `gh issue view <num> --json number,title,author,url`.
   - Prefer crediting external contributors and issue reporters whose merged PRs or closed issues directly map to shipped changes in this release.
   - Do not include open issues or unmerged PRs in `Thanks` unless the user explicitly asks.
   - If the user explicitly asks to include a specific PR or issue in `Thanks`, include it even when it is still open or unmerged.
   - Do not thank the release author for their own PRs or issues unless the user explicitly asks.

4b. Curate the release's GitHub milestone (for example `v0.13`) and derive the list of PRs/issues to notify after release. Step 13 posts to that list after release.
   - Untagged-items check (optional, thorough). Ask the user whether to run the check or not, because check is expensive and the user usually tags the milestone carefully as work lands. When check approved, map every commit in `<from-ref>..<to-ref>` to its merged PRs (`gh api repos/<owner>/<repo>/commits/<sha>/pulls`), to the issues those PRs close, and to the `#N` references in its commit message. Then report the shipped items that have no milestone or a different one, applying these tagging rules:
     - A PR with no corresponding issue gets the milestone, infra PRs included.
     - A PR whose issue already has the milestone gets it only when the PR has participants (author, commenters, reviewers) who are not on the issue.
     - An issue that lacks the milestone gets it.
     - Judge a PR by every commit it carries, not by its title. A PR titled `feat(ci): ...` can carry user-facing commits.
   - Leave open items already in the milestone alone. The user may still be working on them.
   - Derive the notification list. Start from the milestone's closed items, then subtract:
     - Items that did not ship: PRs closed without merging, and issues nothing in `<from-ref>..<to-ref>` resolves. Flag these so the user can move them out of the milestone.
     - PRs whose content was fully rewritten before it shipped.
     - Items with no change end users can observe, such as test-only, CI-only, infra, and docs-only items.
     - A PR whose participants are all on its corresponding issue. The issue gets the notification comment instead. Keep the PR when it has participants who are not on the issue, for example a different author or an extra commenter.
     - Items whose only participants are maintainers. A comment there notifies nobody.
     - Issues closed as duplicates. Comment on the canonical item instead, and add the duplicate's reporter as a trailing `@username` line, because they are not subscribed to the canonical item.
   Include the proposed milestone changes and the notification list, with selected and skipped items each carrying a one-line reason, in the dry run. Apply milestone changes only after confirmation.

5. Draft changelog bullets in this order:
   - `### Upgrade Notes`
   - `### Features`
   - `### Bug Fixes`
   - `### Chores`
   - `### Misc`
   - `### Thanks`
   - `### Changed Sandboxing Profiles`

6. Keep the changelog high signal.
   - Use `Upgrade Notes` only for changes that require user action, verification, migration, reinstall steps, or awareness of a compatibility/default change.
   - If a change is breaking or likely to surprise existing users, put the actionable guidance in `Upgrade Notes`.
   - Start an upgrade note with `Breaking:` when the change is intentionally incompatible.
   - Do not repeat the same customer-facing point across multiple sections unless the extra context is genuinely useful.
   - Prefer user-visible behavior, compatibility, and install/release changes.
   - Collapse related commits into one bullet when they are part of the same outcome.
   - Omit `dist/`-only changes and pure `chore: regenerate dist artifacts` commits from changelog analysis.
   - Do not treat generated `dist/` diffs as independent features, fixes, chores, or reasons to bump the version.
   - Put docs-only, tests-only, and internal cleanup into `Chores` only if they are worth calling out.
   - If new test coverage materially improves confidence or predictability for users, call that out in `Chores` instead of burying it.
   - Use `Misc` only for noteworthy items that do not fit `Features`, `Bug Fixes`, or `Chores`.
   - Use `Thanks` for contributor shout-outs tied to shipped work. Format each bullet with the contributor's GitHub username as an `@mention`, not their full name.
   - Do not start `Thanks` bullets with the word `Thanks`; the section heading already carries that meaning.
   - Link each `Thanks` bullet to the relevant merged PR or closed issue, and place that link at the end of the sentence after the blurb.
   - If any `.sb` files changed under `profiles/`, always include `### Changed Sandboxing Profiles`.

7. Dry run and confirmation gate.
   Before changing any files or publishing anything, prepare a release dry run for the user.
   The dry run must include:
   - the baseline release you resolved
   - the proposed next version
   - whether it is a stable release or a prerelease
   - the reason for the patch/minor/major bump
   - the full proposed new release section for `CHANGELOG.md`
   - whether the Homebrew tap will be updated
   - the exact next actions you intend to take after confirmation
   The exact next actions should be listed in order:
   - apply the confirmed milestone changes from step 4b
   - update `VERSION`
   - update `CHANGELOG.md`
   - regenerate `dist/`
   - run the verification gate
   - commit and push the release-ready state
   - tag and push the release tag
   - publish or update the GitHub release
   - publish the Homebrew tap for stable releases only
   - roll milestones forward
   - notify interested issues/PRs, for stable releases only
   Stop after presenting this overview and wait for explicit user confirmation.
   Do not update `CHANGELOG.md`, regenerate `dist/`, run the verification gate, create commits, create tags, push commits, push tags, create GitHub releases, edit GitHub releases, or publish the Homebrew tap until the user explicitly confirms.

8. After confirmation, update `VERSION` and `CHANGELOG.md`.
   Write the selected version string into the repo-root `VERSION` file with no extra prose.
   For a tagged release, create or update a heading shaped like `## [1.2.3] - YYYY-MM-DD`, using the version you selected in step 2, then move or rewrite the relevant unreleased bullets underneath it.
   Treat `## [Unreleased]` as the working buffer for the next release.
   Move only the notes that are shipping in the release you are drafting.
   Leave unrelated future work under `## [Unreleased]`.
   Insert the new release section immediately below `## [Unreleased]` so the newest release stays at the top of the file.
   Do not add explanatory prose ahead of `## [Unreleased]` or ahead of the latest release section.
   If format notes are needed, keep them at the end of the file.
   After moving shipped notes out of `## [Unreleased]`, keep that section sparse:
   - Always keep `### Upgrade Notes` with either real bullets or `- No special notes.`
   - Always keep `### Changed Sandboxing Profiles` with either real bullets or `- No profiles changed.`
   - Keep `### Features`, `### Bug Fixes`, `### Chores`, `### Misc`, and `### Thanks` only when they contain actual unreleased notes.
   - Remove empty `Features`, `Bug Fixes`, `Chores`, `Misc`, and `Thanks` subsections instead of leaving placeholder text.
   Apply the current structure only to the section you are drafting.
   Leave older release sections in their existing format unless the user explicitly asks to revise historical entries.

9. After confirmation, regenerate `dist/` and run the verification gate.
   Always regenerate `dist/` before publishing:
   - `./scripts/generate-dist.sh`
   Then run the verification gate from an unsandboxed macOS shell:
   - `./tests/run.sh`
   - `test -x dist/safehouse.sh`
   - `bash -n dist/safehouse.sh`
   - `./dist/safehouse.sh --explain --stdout >/dev/null`
   If the verification gate cannot run because the current shell is already sandboxed or the environment is otherwise unsuitable, stop before publishing and tell the user.

10. After confirmation, publish the GitHub release locally with `gh`.
   Derive the final tag as `v<version>` from the selected version written to `VERSION`.
   Commit and push the release-ready state.
   Create and push the tag.
   Extract the new release notes from the new `CHANGELOG.md` section and validate that the extracted notes are not empty.
   Attach only `dist/safehouse.sh` as the custom asset and use the drafted changelog text for the release body.
   Use `gh release create --verify-tag` so publishing fails if the remote tag is missing.
   If updating an existing draft release, publish it with `gh release edit --draft=false`.
   If the selected version contains a SemVer prerelease suffix, publish it with `gh release create --prerelease` or `gh release edit --prerelease` so GitHub marks it as a prerelease.

11. After confirmation, publish the Homebrew tap for stable releases.
   For every stable release, update the Homebrew tap repository at `https://github.com/eugene1g/homebrew-safehouse`.
   Use `./scripts/publish-homebrew-tap.sh "v<version>" --push`.
   Skip this step for prereleases such as `-rc.N` and `-beta.N`.

12. After publishing a stable release, roll the GitHub milestones forward.
   - Create the next milestone (for example `v0.14` after `v0.13`) if it does not exist.
   - Move the release milestone's remaining open issues and PRs to the next milestone.
   - Close the release milestone. Do this after step 13, which reads from it.

13. After publishing a stable release, notify the people who asked for or contributed what shipped.
   Post one comment on each item in the notification list confirmed in step 4b, so its subscribers learn the fix or feature is out.
   If step 4b's curation was skipped, do it now, and confirm the list before posting.
   Use this exact comment body:

   ```md
   This feature is now released in Agent Safehouse <short-version>.

   https://github.com/eugene1g/agent-safehouse/releases/tag/v<version>
   ```

   `<short-version>` is `v<major>.<minor>` when the patch number is 0 (`v0.13` for `v0.13.0`), and the full `v<major>.<minor>.<patch>` otherwise (`v0.13.1`). The link always uses the full tag. The same wording is used for bug fixes. Any trailing `@username` line for a duplicate's reporter goes after the link, separated by a blank line.
   Wait for confirmation before posting any comment.
   Post with `gh issue comment <num>` or `gh pr comment <num>`, then confirm that each comment exists.
   Skip this step for prereleases.

## Changed Sandboxing Profiles

When any sandbox profiles changed in the release range, add a separate section:

```md
### Changed Sandboxing Profiles

- [`keychain.sb`](https://github.com/eugene1g/agent-safehouse/compare/<from-ref>...<to-ref>#diff-<sha256(path)>): Tightened keychain access so agents only get the lookups required for login flows.
```

Rules:

- Include every changed `.sb` file under `profiles/`.
- For each bullet, say what changed and why in one short sentence.
- Use the profile basename as the markdown label, not the full repo-relative path.
- Link each bullet to the GitHub compare diff for that exact file between the baseline release and the selected release, not to a blob permalink.
- Build the URL as `https://github.com/eugene1g/agent-safehouse/compare/<from-ref>...<to-ref>#diff-<sha256(path)>`.
- Compute `<sha256(path)>` from the literal repo-relative file path, for example `printf '%s' 'profiles/.../.sb' | shasum -a 256 | awk '{print $1}'`.
- Use the resolved baseline release tag as `<from-ref>` and the selected release tag as `<to-ref>`, for example `v1.2.2...v1.2.3` or `v1.2.3...v1.3.0-rc.1`.
- When drafting the new release section before the tag exists remotely, still write the final compare link using the final selected release tag as `<to-ref>`.

## Output Shape

Use plain markdown bullets under these headings when they have content:

```md
### Upgrade Notes

- ...

### Features

- ...

### Bug Fixes

- ...

### Chores

- ...

### Misc

- ...

### Thanks

- @username adding or surfacing shipped behavior in [#123](https://github.com/eugene1g/agent-safehouse/pull/123).

### Changed Sandboxing Profiles

- [`profile.sb`](https://github.com/eugene1g/agent-safehouse/compare/<from-ref>...<to-ref>#diff-<sha256(path)>): What changed and why.
```

If a section has nothing worth shipping, omit filler bullets in the final release notes.
Inside `## [Unreleased]`, only use placeholder text for `Upgrade Notes` and `Changed Sandboxing Profiles`.

Do not retrofit old releases to add `Upgrade Notes`, `Chores`, or `Changed Sandboxing Profiles` just because the current release uses those headings.
