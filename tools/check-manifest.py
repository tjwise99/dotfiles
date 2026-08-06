#!/usr/bin/env python3
"""Assert the manifest and the tracked tree agree, in both directions.

Every tracked file must be deployed by some profile, and every source a
profile names must exist. Either gap means a file is in the repo that no
machine would ever receive, or a link that will fail at apply time.
"""

import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent.parent

# Repo infrastructure: present in the tree, deliberately never deployed.
EXEMPT_FILES = {".gitignore", ".gitmodules", "install", "README.md"}
EXEMPT_DIRS = {"dotbot", "dotbot-plugins", "local", "profiles", "tools"}


def tracked_files():
    out = subprocess.run(
        ["git", "-C", str(ROOT), "ls-files"],
        capture_output=True, text=True, check=True,
    ).stdout.split()
    return [
        Path(p) for p in out
        if p not in EXEMPT_FILES and p.split("/")[0] not in EXEMPT_DIRS
    ]


def manifest_sources():
    """Every link source, and every shell command, named by any profile.

    A file is deployed either by being linked into place or by being run, so
    both count as coverage.
    """
    sources, commands = set(), []
    for profile in sorted((ROOT / "profiles").glob("*.conf.yaml")):
        for block in yaml.safe_load(profile.read_text()) or []:
            for target, spec in (block.get("link") or {}).items():
                if spec is None:
                    # Dotbot infers the source from the target's basename.
                    sources.add(Path(target).name.lstrip("."))
                elif isinstance(spec, dict):
                    if "path" in spec:
                        sources.add(spec["path"])
                else:
                    sources.add(spec)
            for entry in block.get("shell") or []:
                commands.append(
                    entry["command"] if isinstance(entry, dict) else entry
                )
    return {Path(s) for s in sources}, commands


def main():
    sources, commands = manifest_sources()

    def deployed(path):
        if any(path == s or s in path.parents for s in sources):
            return True
        return any(str(path) in command for command in commands)

    unwired = [f for f in tracked_files() if not deployed(f)]
    dangling = [s for s in sources if not (ROOT / s).exists()]

    for f in sorted(unwired):
        print(f"tracked but never deployed: {f}", file=sys.stderr)
    for s in sorted(dangling):
        print(f"manifest names a missing source: {s}", file=sys.stderr)

    if unwired or dangling:
        return 1
    print(f"manifest ok — {len(sources)} sources cover the tracked tree")
    return 0


if __name__ == "__main__":
    sys.exit(main())
