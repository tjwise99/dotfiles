#!/usr/bin/env python3
"""Expand packages/manifest.yaml into a package list for one host.

--native   names for this host's own package manager, space separated
--aur      names pacman cannot build, for the AUR helper (Manjaro only)
--verify   both directions: every name the manifest gives this host is
           installed, and every explicitly-installed package is either named
           here or recorded in the host's baseline
--write-baseline
           record this host's untriaged explicit installs, once, so --verify's
           undeclared direction has something to measure against. Refuses to
           overwrite an existing file.
--host     print the detected host and exit

An entry that omits this host's column is an error, not a shorter list. A
resolver that drops what it does not recognise reports success over whatever
survived, which is the whole reason `unavailable` has to be written out.
"""

import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.append(str(ROOT / "dotbot/lib/pyyaml/lib"))

try:
    import yaml
except ModuleNotFoundError:
    sys.exit("PyYAML unavailable — run: git submodule update --init --recursive")

MANIFEST = ROOT / "packages/manifest.yaml"

# Which manifest column each host reads, and the two different questions the
# two directions have to ask it.
#
# `present` is every installed package; `explicit` is only what was asked for by
# name. They are not interchangeable: curl, git, zsh and xclip are all installed
# on the laptop and none of them appear in `pacman -Qqe`, because each arrived
# as some other package's dependency. Verifying presence against the explicit
# set reports four packages missing from a machine that has them.
HOSTS = {
    "manjaro": {
        "column": "pacman",
        "present": ["pacman", "-Qq"],
        "explicit": ["pacman", "-Qqe"],
    },
    "wsl": {
        "column": "apt",
        "present": ["dpkg-query", "-W", "-f=${binary:Package} ${db:Status-Status}\n"],
        "explicit": ["apt-mark", "showmanual"],
    },
}


def detect_host():
    if "microsoft" in Path("/proc/version").read_text(errors="ignore").lower():
        return "wsl"
    for line in Path("/etc/os-release").read_text().splitlines():
        key, _, value = line.partition("=")
        if key == "ID" and value.strip().strip("\"'") in {"manjaro", "arch"}:
            return "manjaro"
    return "unknown"


def manifest():
    return yaml.safe_load(MANIFEST.read_text()) or {}


def names_for(host):
    """Every native package name the manifest gives this host."""
    data = manifest()
    column = HOSTS[host]["column"]
    names, missing = [], []

    for entry in data.get("shared") or []:
        value = entry.get(column, "MISSING")
        if value == "MISSING":
            missing.append(f"{entry['name']}: no '{column}' name and no `unavailable`")
        elif value == "unavailable":
            continue
        else:
            names.append(value)

    # A host-specific section carries one column, so its `name` is the package.
    for entry in data.get(host) or []:
        names.append(entry["name"])

    if missing:
        raise SystemExit("manifest incomplete for host '%s':\n  %s"
                         % (host, "\n  ".join(missing)))
    return names


def aur_names():
    return [e["name"] for e in manifest().get("manjaro-aur") or []]


def _run(command):
    proc = subprocess.run(command, capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit("could not list packages: %s" % proc.stderr.strip())
    return proc.stdout


def present(host):
    """Every installed package, however it got there."""
    out = _run(HOSTS[host]["present"])
    if host == "wsl":
        # dpkg keeps a record of removed-but-not-purged packages; only the ones
        # whose status is `installed` are actually on the machine. The name
        # carries an architecture suffix that the manifest does not.
        return {line.split()[0].split(":")[0]
                for line in out.splitlines()
                if line.strip().endswith(" installed")}
    return {name.strip() for name in out.split() if name.strip()}


def explicit(host):
    """Only what was installed by name — the population drift is measured over."""
    return {name.strip() for name in _run(HOSTS[host]["explicit"]).split() if name.strip()}


def group_members(name):
    """Members of a pacman group, or None if the name is not a group."""
    proc = subprocess.run(["pacman", "-Sgq", name], capture_output=True, text=True)
    members = {m.strip() for m in proc.stdout.split() if m.strip()}
    return members or None


def write_baseline(host):
    """Record this machine's untriaged explicit installs, once, for a new host.

    Refuses to overwrite. Regenerating on a machine that has drifted would fold
    the drift into the baseline and call it history, which is the one way this
    file can quietly stop being a record of anything.
    """
    path = ROOT / f"packages/baseline-{host}.txt"
    if path.exists():
        raise SystemExit(f"{path.name} already exists — delete it deliberately to redo it")
    declared = set(names_for(host)) | set(aur_names() if host == "manjaro" else [])
    untriaged = sorted(explicit(host) - declared)
    path.write_text(
        "# Explicitly-installed packages that predate packages/manifest.yaml on\n"
        f"# this host. Untriaged, not endorsed: recorded so resolve.py --verify\n"
        "# reports what was installed since, not everything the image shipped.\n"
        + "\n".join(untriaged) + "\n")
    print(f"wrote {path.name} — {len(untriaged)} untriaged packages ({host})")
    return 0


def baseline(host):
    """Explicitly-installed packages that predate this manifest.

    Untriaged, not endorsed. It exists so the undeclared direction reports the
    handful of things installed since, instead of the several hundred that came
    with the ISO — a check whose output nobody reads is not a check.
    """
    path = ROOT / f"packages/baseline-{host}.txt"
    if not path.exists():
        return None
    return {l.strip() for l in path.read_text().splitlines()
            if l.strip() and not l.startswith("#")}


def verify(host):
    problems = []
    declared = set(names_for(host)) | set(aur_names() if host == "manjaro" else [])
    have = present(host)

    for name in sorted(declared):
        if name in have:
            continue
        # A group is never installed under its own name. Asserting that some
        # member is present would pass on one member out of twenty-odd, so the
        # whole membership is compared.
        members = group_members(name) if host == "manjaro" else None
        if members is None:
            problems.append(f"declared but not installed: {name}")
        elif members - have:
            problems.append("declared group %s incomplete — missing: %s"
                            % (name, ", ".join(sorted(members - have))))

    base = baseline(host)
    if base is None:
        problems.append(
            f"no packages/baseline-{host}.txt — the undeclared direction cannot "
            f"run, so this reports only half of what it claims to check"
        )
    else:
        for name in sorted(explicit(host) - declared - base):
            problems.append(f"installed but undeclared: {name}")

    for problem in problems:
        print(problem, file=sys.stderr)
    if problems:
        return 1
    print(f"packages ok — {len(declared)} declared, {len(have)} present ({host})")
    return 0


def main():
    argv = sys.argv[1:]
    if "--host" in argv and len(argv) == 1:
        print(detect_host())
        return 0

    host = argv[argv.index("--host") + 1] if "--host" in argv else detect_host()
    if host not in HOSTS:
        raise SystemExit(f"no package manifest for host '{host}'")

    if "--write-baseline" in argv:
        return write_baseline(host)
    if "--verify" in argv:
        return verify(host)
    if "--aur" in argv:
        print(" ".join(aur_names() if host == "manjaro" else []))
        return 0
    if "--native" in argv:
        print(" ".join(names_for(host)))
        return 0
    raise SystemExit(__doc__)


if __name__ == "__main__":
    sys.exit(main())
