# Remote diagnosis

Debugging something you cannot look at: a headless display, a device across a network, anything whose
failure and success look the same from outside. Two habits, both learned by not having them.

## 2026-08-06 — a slow start at low CPU load is blocked, not busy (MagicMirror kiosk)

The same kiosk took several minutes from power-on to a rendered page. Two sessions had written this
off the same way: *it's a 1GHz single core starting X, a window manager and a browser — of course
it's slow.* Entirely plausible, and wrong.

The tell was one number. The browser sat at **28MB resident for eight minutes** while system load
was **0.38**. A process that is slow because the CPU is oversubscribed shows load near or above 1.0.
A process that is slow at *idle* is not computing — it is waiting on something, and the interesting
question is what.

It was blocked in `getrandom()`. The board has a hardware RNG, but nothing was crediting it to the
kernel entropy pool: the kernel treats hwrng as untrusted by default, and the two daemons that
normally do the crediting were unavailable because that distribution's package archive had been
taken offline. A headless appliance has no keyboard, no mouse, and almost no other entropy source,
so the pool filled at a crawl and every consumer of secure randomness queued behind it.

```
entropy_avail: 29        (pool size 4096)
```

Feeding the pool by hand moved it to 3083 and the browser completed startup within seconds — 28MB
resident to 123MB, debug port bound, page loading. Boot-to-rendered went from ~347s to ~120s.

**Two things worth keeping.** First, *load average is a diagnostic, not just a health metric*: paired
with "this is taking too long", it splits the space cleanly into oversubscribed versus blocked, and
those have disjoint fixes. Second, **entropy starvation is a standing hazard for any headless box**
— appliances, containers, CI runners, freshly-imaged VMs, anything that boots with no human
attached. It presents as unexplained multi-minute stalls in unrelated software, which is why it gets
misattributed to whatever happens to be starting at the time.

The correlate: I had *already seen* the kernel's warning in a log tail hours earlier —
`the entropy pool has not been initialized … this process will block` — and read past it, because I
was looking for browser errors and it did not look like one. The evidence was in hand before the
theory that would have used it.

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
newer browser. That would have replaced a working-but-old browser with none — current releases ship
no browser for that CPU architecture — so the recommendation was withdrawn.

**Corrected 2026-08-06: the withdrawal was itself an unverified inference, and its stated reason was
false.** What got written down was "Chromium is no longer built for that CPU architecture at all."
Checked a day later against the actual device: it is. One release further on than the installed
version, the last one built for that architecture — and its `.deb` had been sitting in the machine's
own package cache for six years, pulled down by an automatic update job and never installed. Reading
the binary's ELF architecture attributes took a minute; running it took another.

The conclusion survived. The reason did not, and the reason was what got reused: as written it said
*there is no newer browser*, which closed off a real upgrade for a year and propagated into three
other documents as settled fact.

**A right answer held for a wrong reason is not safe.** It forecloses whatever its reasoning
excludes, and it fails silently — nothing goes wrong until someone acts on the *reason* instead of
the conclusion. When you catch yourself correcting a bad inference, check that the correction isn't
one too; the relief of having caught an error is exactly when the replacement goes unverified.

## The habits in one line

Substitute evidence for inference at the points where inference is cheapest and most tempting:
**what the system is doing** (get a channel), **what the system is** (read the version), and **why
it is slow** (read the load — busy and blocked look identical from outside and have nothing in
common).

And once more for the correction above: that includes the inferences you make while fixing an
inference.
