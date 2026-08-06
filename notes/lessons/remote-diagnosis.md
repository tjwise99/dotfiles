# Remote diagnosis

Debugging something you cannot look at: a headless display, a device across a network, anything whose
failure and success look the same from outside. Two habits, both learned by not having them.

## 2026-08-05 — buy an observation channel before forming theories (MagicMirror kiosk)

A wall-mounted Pi kiosk showed a black screen after its backend moved to a new host. **The screen is
supposed to be black** — it's a mirror. So "working", "browser crashed", "JavaScript threw", and "X
never started" were one observation.

Hours went into inference from indirect signals: TCP connection states, process counts, ping jitter,
memory readings. That work produced one genuinely useful discriminator — one connection meant scripts
never ran, three meant they were fetched but not executed, sustained `ESTABLISHED` meant success —
and otherwise produced elaborate, confident, wrong theories.

Adding **one flag** to the browser's launch command ended it:

```
chromium-browser --kiosk --remote-debugging-port=9222 --app=http://host:8080
```

The first read of the console over the DevTools Protocol printed the cause verbatim: `Refused to
execute inline script … Content Security Policy`. That fault was structurally invisible to every
signal being measured, and no amount of further inference would have reached it.

**The lesson isn't "use CDP".** It's that when the thing under test can't be observed, the first move
is to *make it observable*, not to get cleverer about inference. Inference from indirect signals
feels like progress because each round produces a new hypothesis, and the cost of the direct channel
looks like a detour. It is almost always cheaper than the third theory.

Corollary worth building in: the kiosk had **no retry loop** — a single failed load left the screen
black permanently. A thing you can't see should self-heal *and* report. Neither costs much at build
time; both are expensive to retrofit at 11pm.

## 2026-08-05 — verify the target's version, don't infer it from a release date

The same kiosk ran a 2018 OS image. I reasoned: that release shipped Chromium ~65, therefore compile
the frontend for Chromium 65. I built a fix on that number, shipped it, and it changed nothing.

It was **Chromium 60**.

Wrong by five, and precisely load-bearing: ES module support landed in Chrome **61**. So the real
fault — the browser ignoring `<script type="module">` outright — sat inside the gap between the
inferred version and the actual one. A syntax fix targeting 65 was irrelevant to a browser that was
never going to execute the file.

One command would have settled it before any of the work:

```
chromium-browser --version
```

Or remotely, once a debug port exists: `curl -s http://127.0.0.1:9222/json/version`.

**Release dates give you a plausible version, and plausible is where this bites** — an implausible
guess gets checked, a plausible one gets built on. The rule generalises past browsers: kernel,
Python, Node, OpenSSL, firmware. If a version number is going to determine what you build, read it
off the machine.

A second-order version of the same error, same evening: I recommended reimaging the device to get a
newer browser. Checking first would have shown that **Chromium is no longer built for that CPU
architecture at all**, so a current OS ships no browser for it — the reimage would have replaced a
working-but-old browser with none. The recommendation was confident, reasonable, and would have
destroyed the only thing still functioning.

## Both habits in one line

Substitute evidence for inference at the two points where inference is cheapest and most tempting:
**what the system is doing** (get a channel) and **what the system is** (read the version).
