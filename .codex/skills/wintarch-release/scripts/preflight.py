#!/usr/bin/env python3
"""Read-only local checks for the Wintarch GitHub release workflow."""

from __future__ import annotations

import re
import subprocess
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[4]
VERSION_RE = re.compile(r"^v(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)$")


def git(*args: str) -> tuple[int, str]:
    result = subprocess.run(
        ["git", *args], cwd=ROOT, text=True, capture_output=True, check=False
    )
    return result.returncode, result.stdout.strip()


def fail(message: str) -> None:
    print(f"FAIL: {message}")


def warn(message: str) -> None:
    print(f"WARN: {message}")


def main() -> int:
    failures = 0
    code, branch = git("branch", "--show-current")
    if code or not VERSION_RE.fullmatch(branch):
        fail(f"current branch must be vX.Y.Z; found {branch or 'detached HEAD'}")
        return 1

    release = branch[1:]
    print(f"Release branch: {branch}")
    version_file = ROOT / "version"
    if not version_file.is_file():
        fail("root version file is missing")
        failures += 1
    elif version_file.read_text(encoding="utf-8").strip() == branch:
        warn("version already equals release branch; do not change it for release")
    else:
        print(f"OK: version file remains {version_file.read_text(encoding='utf-8').strip()!r}")

    changelog = ROOT / "CHANGELOG.md"
    if not changelog.is_file():
        fail("CHANGELOG.md is missing")
        failures += 1
    else:
        lines = changelog.read_text(encoding="utf-8").splitlines()
        start = next(
            (i for i, line in enumerate(lines) if re.match(rf"^## \[{re.escape(release)}\] - .+", line)),
            None,
        )
        if start is None:
            fail(f"missing heading: ## [{release}] - YYYY-MM-DD")
            failures += 1
        else:
            end = next((i for i in range(start + 1, len(lines)) if re.match(r"^## \[[0-9]+\.[0-9]+\.[0-9]+\] - .+", lines[i])), len(lines))
            if not "\n".join(lines[start + 1 : end]).strip():
                fail(f"changelog section for {release} has no notes")
                failures += 1
            else:
                print(f"OK: non-empty changelog section for {release}")

    _, status = git("status", "--porcelain")
    if status:
        warn("working tree is not clean; review changes before the release action")
    else:
        print("OK: working tree is clean")

    ref = f"refs/tags/{branch}"
    code, _ = git("rev-parse", "-q", "--verify", ref)
    if code == 0:
        fail(f"local tag already exists: {branch}")
        failures += 1
    else:
        print(f"OK: no local tag named {branch}")

    code, output = git("ls-remote", "--exit-code", "--tags", "origin", ref)
    if code == 0:
        fail(f"remote tag already exists: {branch}")
        failures += 1
    elif code == 2:
        print(f"OK: no remote tag named {branch}")
    else:
        warn(f"could not verify remote tag: {output or 'git ls-remote failed'}")

    if failures:
        print(f"Preflight failed: {failures} issue(s).")
        return 1
    print("Preflight passed (GitHub Release existence still requires GitHub Action/API check).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
