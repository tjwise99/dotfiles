#!/usr/bin/env python3
"""Assert the manifest agrees with the repo, and optionally with this machine.

Without --deployed: every tracked file is deployed by some profile, and every
source a profile names exists. Every profile is read, host-independently, so
this runs in a fresh clone.

With --deployed: every target the manifest names is still a symlink into this
repo. A tool that replaces a managed file rather than writing through it breaks
the link silently, and the repo stops receiving changes while still looking
healthy. Scoped to the profiles install applies here — another host's profile
names targets this one is deliberately without.
"""

import os
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent

# Fall back to the PyYAML the dotbot submodule vendors, which install already uses.
sys.path.append(str(ROOT / "dotbot/lib/pyyaml/lib"))

try:
    import yaml
except ModuleNotFoundError:
    sys.exit("PyYAML unavailable — run: git submodule update --init --recursive")

# Repo infrastructure: present in the tree, deliberately never deployed.
EXEMPT_FILES = {".gitignore", ".gitmodules", "install", "README.md"}
EXEMPT_DIRS = {"dotbot", "dotbot-plugins", "local", "profiles", "tools"}

ALL_PROFILES = sorted((ROOT / "profiles").glob("*.conf.yaml"))


def host():
    if os.environ.get("DOTFILES_HOST"):
        return os.environ["DOTFILES_HOST"]
    try:
        if "microsoft" in Path("/proc/version").read_text().lower():
            return "wsl"
    except OSError:
        pass
    try:
        for line in Path("/etc/os-release").read_text().splitlines():
            key, _, value = line.partition("=")
            if key == "ID" and value.strip().strip("\"'") in {"manjaro", "arch"}:
                return "manjaro"
    except OSError:
        pass
    return "unknown"


def host_profiles():
    """The profiles install applies on this machine, in the same order."""
    paths = [ROOT / "profiles/base.conf.yaml"]
    candidate = ROOT / f"profiles/{host()}.conf.yaml"
    if candidate.exists():
        paths.append(candidate)
    return paths


def blocks(paths):
    for profile in paths:
        for block in yaml.safe_load(profile.read_text()) or []:
            yield block


def manifest_links(paths):
    """Every target -> source pair named by the given profiles."""
    links = {}
    for block in blocks(paths):
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


def shell_commands(paths):
    return [
        entry["command"] if isinstance(entry, dict) else entry
        for block in blocks(paths)
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
    sources = {Path(s) for s in manifest_links(ALL_PROFILES).values()}
    commands = shell_commands(ALL_PROFILES)
    tracked = tracked_files()

    def linked(path):
        if any(path == s or s in path.parents for s in sources):
            return True
        return any(str(path) in command for command in commands)

    deployed = {f for f in tracked if linked(f)}

    # A file also reaches $HOME by being read from one that is deployed —
    # shell/common.sh is sourced by both rc files rather than linked. Only a
    # file already known to be deployed may vouch for another, and the loop
    # runs to a fixed point so a fragment read by a fragment still counts.
    text = "\n".join(read(f) for f in deployed)
    while True:
        found = {f for f in tracked if f not in deployed and str(f) in text}
        if not found:
            break
        deployed |= found
        text = "\n".join(read(f) for f in found)

    problems = [f"tracked but never deployed: {f}" for f in sorted(tracked)
                if f not in deployed]
    problems += [f"manifest names a missing source: {s}" for s in sorted(sources)
                 if not (ROOT / s).exists()]
    return problems, len(sources)


def read(path):
    try:
        return (ROOT / path).read_text(errors="ignore")
    except OSError:
        return ""


def check_deployment():
    """Every manifest target for this host is still a live symlink into the repo."""
    problems = []
    for target, source in sorted(manifest_links(host_profiles()).items()):
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

    scope = "tracked tree" + (f" and this machine ({host()})" if checked_deployment else "")
    print(f"manifest ok — {source_count} sources cover the {scope}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
