#!/usr/bin/env python3
"""Assert the manifest agrees with the repo, and optionally with this machine.

Without --deployed: every tracked file is deployed by some profile, and every
source a profile names exists. Repo-internal, so it runs in a fresh clone.

With --deployed: every target the manifest names is still a symlink into this
repo. A tool that replaces a managed file rather than writing through it breaks
the link silently, and the repo stops receiving changes while still looking
healthy.
"""

import os
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent

# Repo infrastructure: present in the tree, deliberately never deployed.
EXEMPT_FILES = {".gitignore", ".gitmodules", "install", "README.md"}
EXEMPT_DIRS = {"dotbot", "dotbot-plugins", "local", "profiles", "tools"}


def profiles():
    for profile in sorted((ROOT / "profiles").glob("*.conf.yaml")):
        for block in yaml.safe_load(profile.read_text()) or []:
            yield block


def manifest_links():
    """Every target -> source pair named by any profile."""
    links = {}
    for block in profiles():
        for target, spec in (block.get("link") or {}).items():
            if spec is None:
                # Dotbot infers the source from the target's basename.
                links[target] = Path(target).name.lstrip(".")
            elif isinstance(spec, dict):
                if "path" in spec:
                    links[target] = spec["path"]
            else:
                links[target] = spec
    return links


def shell_commands():
    return [
        entry["command"] if isinstance(entry, dict) else entry
        for block in profiles()
        for entry in (block.get("shell") or [])
    ]


def tracked_files():
    out = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files"],
        capture_output=True, text=True, check=True,
    ).stdout.split()
    return [
        Path(p) for p in out
        if p not in EXEMPT_FILES and p.split("/")[0] not in EXEMPT_DIRS
    ]


def check_repo():
    """Tracked tree and manifest cover each other."""
    sources = {Path(s) for s in manifest_links().values()}
    commands = shell_commands()

    def deployed(path):
        if any(path == s or s in path.parents for s in sources):
            return True
        return any(str(path) in command for command in commands)

    problems = [f"tracked but never deployed: {f}" for f in sorted(tracked_files())
                if not deployed(f)]
    problems += [f"manifest names a missing source: {s}" for s in sorted(sources)
                 if not (ROOT / s).exists()]
    return problems, len(sources)


def check_deployment():
    """Every manifest target is still a live symlink into this repo."""
    problems = []
    for target, source in sorted(manifest_links().items()):
        path = Path(os.path.expanduser(target))
        expected = (ROOT / source).resolve()

        if not path.is_symlink():
            if path.exists():
                problems.append(
                    f"replaced by a real file — edits are NOT reaching the repo: {target}"
                )
            else:
                problems.append(f"not deployed: {target}")
            continue

        actual = Path(os.path.realpath(path))
        if actual != expected:
            problems.append(f"points at {actual}, expected {expected}: {target}")
    return problems


def main():
    problems, source_count = check_repo()
    checked_deployment = "--deployed" in sys.argv
    if checked_deployment:
        problems += check_deployment()

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1

    scope = "tracked tree" + (" and this machine" if checked_deployment else "")
    print(f"manifest ok — {source_count} sources cover the {scope}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
