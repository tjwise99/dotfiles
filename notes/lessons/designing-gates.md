# Designing gates and guards

A gate is a piece of code whose whole job is to be right about something else. When one is wrong it
is wrong quietly, and it takes the thing it was guarding down with it. Notes on the failure modes,
all from gates that were already in place and already believed.

## 2026-08-06 — a guard that cannot run must not answer anyway

A repository test asserted that every top-level directory is named in the documentation. It filtered
out ignored directories:

```ts
const result = spawnSync("git", ["check-ignore", "-q", "--", name], { cwd: ROOT });
return result.status === 0;          // 0 = ignored
```

`git check-ignore` exits **0** for ignored, **1** for not ignored, and **anything else** for *git
itself failed*. That third case arrived when the test began running inside a container: the checkout
is owned by uid 1000, the container runs as root, and git refuses a repository it considers
suspiciously owned — exit **128**, every call, no output the test looked at.

So `isGitIgnored()` returned `false` for everything. The guard's verdict became *"no directory in
this repository is ignored, and therefore several are undocumented"* — a confident, specific,
entirely fabricated finding. The real content of that run was "git did not work here", which the
guard had no way to express.

**Two-valued returns from three-valued calls are the bug.** The shape to look for: any predicate
built on an external command where "no" and "I could not tell" collapse into the same value. Decide
which way it should fail, and make the third case *loud* — this one now throws with the status and
stderr, and the container invocation was fixed separately so git works at all.

Worth noticing: **the guard failed toward accusing its subject.** It did not report itself broken; it
reported the repository broken. A guard that blames outward when it malfunctions costs far more than
one that refuses to answer.

## 2026-08-06 — a gate that is always red gets ignored, so keep it green *honestly*

A scanner checked built assets for features the deployment target's browser lacked. Two things kept
it permanently failing on correct builds:

- It matched the CSS property `gap` against one version number. But `gap` is two features sharing a
  name — supported in grid layout years before flex layout. Correct grid code failed the gate.
- It flagged a runtime method that the bundle *shipped a polyfill for*. A static scan cannot see a
  runtime shim, so the finding was real and the conclusion wasn't.

A gate that cannot go green teaches everyone to skip it, which is strictly worse than not having it —
you keep the cost and lose the signal, and you acquire the false belief that the thing is checked.

**Both were fixed by making it know more, not by letting it check less.** The `gap` check now reads
the enclosing rule's `display` to decide which feature it is looking at. The polyfill check looks for
the shim *in the same bundle* and only then treats the call as safe.

That second choice mattered. The obvious fix was a suppression flag — `--allow replaceAll` — and it
would have been wrong: a flag suppresses the genuinely unpolyfilled use too, forever, silently, and
it never expires. Detecting the shim is self-verifying: delete the polyfill and the gate goes red
again, which is exactly what should happen.

**Where it cannot tell, it fails closed.** A CSS block whose `display` is indeterminate counts as the
strict case. A false failure costs someone five minutes; a false pass ships a blank screen to a
device on a wall.

**Seed both directions, always.** Every gate needs the defect it must catch *and* the
spelled-differently-but-valid input it must not reject. Here: grid gap passes, flex gap fails,
indeterminate fails; polyfill present passes, polyfill stripped fails. Only checking that a gate
fires on the bad input tells you nothing about whether it fires on everything.

## 2026-08-06 — a safety mechanism is a mechanism, and mechanisms fail

Before changing a device that is expensive to reach physically, I built an auto-revert harness:
snapshot the config, arm a deadline, and if I could not confirm success in time, restore and reboot
unattended.

It caused the worst outage of the session. The restore logic was correct — files and service states
both came back exactly as snapshotted. The *control* logic was not:

- It cleared the deadline **after** doing its slow work instead of before, so it still looked armed
  the whole time it was running.
- It took no lock.

The scheduler re-fired it every minute. Concurrent copies stacked, each issuing dozens of service
operations on a single-core machine, until the init system wedged partway through a reboot and the
display went dark for eight minutes.

**Disarm before acting, never after** — the window between "started work" and "recorded that I
started" is where re-entrancy lives. **Take a lock even when you are sure it cannot run twice.** And
**prove a safety mechanism in both directions before it guards anything real**: I had tested that
confirming prevented a revert, and that not confirming triggered one. I had not tested what happens
when the revert takes longer than the interval that triggers it — the case that actually occurred.

The uncomfortable general form: **the machinery you add to make a risky change safe is itself an
untested change**, written under time pressure, usually with less care than the thing it protects.
Its blast radius is the whole system, by design. Weigh it against the actual exposure — the change I
was protecting turned out to be a one-line revert I could perform over a shell I never lost.
