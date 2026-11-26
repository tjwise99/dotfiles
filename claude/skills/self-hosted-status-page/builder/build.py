#!/usr/bin/env python3
"""Build one self-contained status page from a directory of input files.

usage: build.py --data DIR --out FILE [--identity FILE] [--title T] [--subtitle S]
Refuses (exit 1, writes nothing) on an identifying string or a failed headless render.
Input formats: INPUTS.md.
"""
import argparse, glob, json, os, re, shutil, subprocess, sys, tempfile, time

HERE = os.path.dirname(os.path.abspath(__file__))
ap = argparse.ArgumentParser()
ap.add_argument("--data", required=True)
ap.add_argument("--out", required=True)
ap.add_argument("--identity", help="file of regexes, one per line, that must not appear in the page")
ap.add_argument("--title", default="Status")
ap.add_argument("--subtitle", default="")
ap.add_argument("--no-render-check", action="store_true")
a = ap.parse_args()


def load(name):
    p = os.path.join(a.data, name)
    return json.load(open(p)) if os.path.exists(p) else None


def md_tables(path):
    """Every GFM table in a file, as a list of row-lists (header first, rule row dropped)."""
    out, cur = [], None
    for l in open(path).read().splitlines():
        if l.startswith("|"):
            r = [c.strip() for c in l.strip().strip("|").split("|")]
            if not set("".join(r)) <= set("-: "):
                cur = (cur or []) + [r]
        elif cur:
            out.append(cur)
            cur = None
    if cur:
        out.append(cur)
    return out


data = {"cards": load("results.json") or [], "built_at": time.strftime("%H:%M")}
sched = load("schedule.json")
if sched:
    data["gantt"] = sched
    data["gantt_updated"] = time.strftime("%H:%M", time.localtime(os.path.getmtime(os.path.join(a.data, "schedule.json"))))
data["needs_owner"] = load("needs-owner.json")
data["plan"] = load("plan.json")
data["issue_tracking"] = load("issue-tracking.json")
rp = os.path.join(a.data, "roster.md")
if os.path.exists(rp):
    t = md_tables(rp)
    data["roster"] = t[0] if t else []
cfg = load("page.json") or {}
title, subtitle = cfg.get("title", a.title), cfg.get("subtitle", a.subtitle)

page = open(f"{HERE}/template.html").read()
for k, v in (("%%GANTTJS%%", open(f"{HERE}/gantt.js").read()), ("%%GANTTCSS%%", open(f"{HERE}/gantt.css").read())):
    page = page.replace(k, v)
page = page.replace("%%TITLE%%", title.replace("<", "&lt;")).replace("%%SUBTITLE%%", subtitle.replace("<", "&lt;"))
page = page.replace("%%DATA%%", json.dumps(data).replace("</", "<\\/"))
left = re.findall(r"%%[A-Z]+%%", page)
pats = [l.strip() for l in open(a.identity).read().splitlines() if l.strip() and not l.startswith("#")] if a.identity else []
leaks = [p for p in pats if re.search(p, page)]
if left or leaks:
    sys.exit(f"REFUSING: unfilled {left}; identifying patterns matched: {leaks}")


def chrome():
    for c in [os.environ.get("CHROME")] + sorted(glob.glob(os.path.expanduser("~/.cache/ms-playwright/chromium_headless_shell-*/*/chrome-headless-shell"))) + [shutil.which(n) for n in ("chromium", "chromium-browser", "google-chrome", "chrome")]:
        if c and os.path.exists(c):
            return c
    sys.exit("REFUSING: no headless Chrome for the render check (set CHROME or use --no-render-check)")


def render_check(theme):
    pre = f'<script>document.documentElement.setAttribute("data-theme","{theme}")</script>'
    post = '<script>setTimeout(()=>console.log("THEMEBG "+getComputedStyle(document.body).backgroundColor),2500)</script>'
    fd, tmp = tempfile.mkstemp(suffix=".html")
    os.close(fd)
    open(tmp, "w", encoding="utf-8").write("<!doctype html><html><head>" + pre + "</head><body>" + page + post)
    env = {k: v for k, v in os.environ.items() if k != "LD_LIBRARY_PATH"}
    try:
        for n in (1, 2):
            try:
                r = subprocess.run([chrome(), "--no-sandbox", "--enable-logging=stderr", "--v=0", "--dump-dom", "--virtual-time-budget=5000", "file://" + tmp + "#schedule"], capture_output=True, text=True, env=env, timeout=60)
                break
            except subprocess.TimeoutExpired:
                if n == 2:
                    sys.exit("REFUSING: headless render timed out twice")
    finally:
        os.remove(tmp)
    errs = [l for l in r.stderr.splitlines() if ":CONSOLE" in l and ("Uncaught" in l or "Error" in l)]
    dom, bad = r.stdout, []
    for m in re.finditer(r'<main id="([^"]+)" class="tab" data-name="([^"]*)"[^>]*>(.*?)</main>', dom, re.S):
        text = re.sub(r"\s+", " ", re.sub(r"<[^>]+>", " ", m.group(3))).strip()
        if len(text) < 40:
            bad.append(f"tab {m.group(2)!r} renders {len(text)} characters")
    if len(re.findall(r'<main id="[^"]+" class="tab"', dom)) != len(re.findall(r'<main id="[^"]+" class="tab"', page)):
        bad.append("tab count differs after render")
    if data.get("gantt"):
        g = re.search(r'<div id="gantt"[^>]*>(.*?)</div>\s*<div id="holds-wrap"', dom, re.S)
        if not g or len(re.sub(r"<[^>]+>", "", g.group(1)).strip()) < 50:
            bad.append("schedule chart is empty")
    mbg = re.search(r"THEMEBG rgb\((\d+), (\d+), (\d+)\)", r.stderr)
    lum = sum(int(x) for x in mbg.groups()) / 765 if mbg else None
    if lum is None or (theme == "dark" and lum > 0.25) or (theme == "light" and lum < 0.75):
        bad.append(f"{theme} theme not applied (luminance {lum})")
    if errs or bad:
        sys.exit(f"REFUSING: render failed in the {theme} theme: " + "; ".join(bad) + " | console: " + " / ".join(e[-160:] for e in errs[:3]))


if not a.no_render_check:
    render_check("light")
    render_check("dark")
open(a.out, "w", encoding="utf-8").write(page)
print("written", len(page), "bytes;", len(pats), "identity patterns checked")
