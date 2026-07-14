---
name: wintarch-release
description: Prepare a Wintarch semantic-version release branch for a pull request. Use when asked to prepare, validate, or finalize a Wintarch release (for example v0.10.0), update CHANGELOG.md, choose the correct version bump, run release preflight checks, or hand off a release PR. Do not use to execute the GitHub /release action itself.
---

# Wintarch Release

Prepare the repository for the existing GitHub release workflow. Keep the skill generic: derive the target version from the current `vMAJOR.MINOR.PATCH` branch, never from a hard-coded example.

## Boundaries

- Work only on a branch named exactly `vX.Y.Z`. If the current branch differs, stop and explain the required branch name.
- Leave the root `version` file unchanged. The GitHub Action owns that update, its release commit, and the tag.
- Do not merge, tag, create a GitHub Release, or post `/release`.
- The user opens the PR and posts the exact `/release` comment after the normal review process.
- Preserve unrelated user changes. Do not reset, clean, or overwrite them.

## Workflow

1. Inspect repository instructions, `.github/workflows/release.yml`, `CONTRIBUTING.md`, `CHANGELOG.md`, the current branch, status, and the diff from `origin/master` (or `master` if the remote ref is unavailable).
2. Run `scripts/preflight.py` before making changes. Resolve failures rather than bypassing them.
3. Determine the SemVer bump from the changes. Use patch for fixes, minor for backward-compatible features, and major for incompatible public behavior. Before 1.0, still make the choice explicit and document breaking changes in the changelog.
4. Edit `CHANGELOG.md`:
   - move applicable entries from `## [Unreleased]` into `## [X.Y.Z] - YYYY-MM-DD` using today's date;
   - retain an `Unreleased` heading for follow-up work;
   - use Keep a Changelog categories and describe user-facing effects;
   - include a `### ⚠️ BREAKING CHANGES` section and migration/manual-install guidance when relevant;
   - make the release section non-empty. It is copied verbatim into the GitHub Release body.
5. Add or review migrations for changes needed by already-installed systems. Migrations must be timestamp-named, executable, idempotent, and tested. Pre-v1.0, use one for security, system-breaking, or data-loss fixes; otherwise clearly document intentional divergence.
6. Run validation in proportion to the changes. For installer or migration changes, use the documented VM tests when the environment supports them:

   ```bash
   ./test/test.sh
   ./test/test.sh --boot-disk
   ```

   Report commands that were not run and why. Do not claim a VM test passed without running it.
7. Run `scripts/preflight.py` again. Review `git diff` and `git status --short`; ensure no unintended changes are staged or committed.
8. Present a concise PR handoff: proposed title, a summary, tests run/not run, migration or breaking-change impact, and the exact manual finish: open PR to `master`, obtain review, then comment `/release`.

## Release-workflow contract

The GitHub Action requires all of the following:

- a PR whose head branch is `vX.Y.Z`;
- a maintainer-authorized comment whose entire body is `/release`;
- no existing remote/local tag or GitHub Release for the version;
- a changelog heading exactly `## [X.Y.Z] - ...` with content beneath it;
- a clean rebase of the release branch onto `origin/master` and a fast-forward of `master`.

The action extracts release notes before it rebases. Ensure the branch is current with `origin/master` before requesting release, and resolve any conflicts locally where possible.

## Commit and PR handling

When the user asks for commits, make purposeful commits for the product changes and the changelog. Do not add a version-only commit. Push/open a PR only when the user explicitly asks or the current task authorizes it.

Use this PR body checklist:

```markdown
## Release vX.Y.Z

- User-facing changes: ...
- Migration / breaking-change impact: ...
- Validation: ...

Release after review by commenting exactly `/release`.
```

## Preflight helper

Run:

```bash
python3 .codex/skills/wintarch-release/scripts/preflight.py
```

It is read-only. It validates the branch format, `version` file, release changelog heading/content, repository cleanliness, and basic tag collisions. It does not replace reviewing the workflow or checking GitHub Release existence.
