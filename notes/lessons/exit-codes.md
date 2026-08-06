# Exit codes that lie

Shell constructs that report success for a failed thing, or failure for a successful one. Both
entries below cost real time in a single session, and both are silent by construction — the failure
mode of a wrong exit code is that everything looks fine.

## 2026-08-06 — a pipeline reports the *last* command's status, not the one you care about

I ran a repository's full verification gate and read the result off the end of a pipe:

```bash
just verify 2>&1 | tail -50
```

The harness reported **exit code 0**. That is `tail`'s exit code. `just` had failed. I came within
one sentence of telling the user their gate was green while a lint error sat in the output I had
just printed.

The same mistake, twice more that hour, in a shape that looked more careful rather than less. Seeding
a build gate with three test inputs to prove it caught the bad ones:

```bash
python3 scan-bundle.py --target 72 gap-flex.css | tail -5; echo "exit=$?"
```

Printed `exit=0` for all three cases. The real codes were 0, 1, 1 — the tool was working perfectly
and the check of it was not. Had the tool been broken, this test would have reported exactly the same
thing.

**Fixes, in order of preference.** Redirect to a file and test `$?` directly; that also keeps the
output for later. Otherwise `${PIPESTATUS[0]}` in bash, or `set -o pipefail`. Do not decorate a
pipeline with `echo "exit=$?"` and believe it.

**The generalisation is worse than the bug.** A verification step that is itself unverified reports
the same thing whether or not the subject works. Any time the output is *"it passed"*, ask what that
sentence would look like if the thing had failed — and if the answer is "the same", you have measured
nothing. This applies well beyond shell: a test with no assertion, a mock that returns success
unconditionally, a health check that greps for a string absent from both the healthy and unhealthy
output.

## 2026-08-06 — `set -o pipefail` plus `grep -q` inverts a successful match

A script to disable unneeded boot services reported every single unit as absent, and disabled
nothing. The units plainly existed. The guilty line:

```bash
set -uo pipefail
...
if systemctl list-unit-files | grep -q "^${unit}\.service"; then
```

`grep -q` exits as soon as it matches — that is the whole point of `-q`. Its producer, still
writing, gets **SIGPIPE** and dies with 141. `pipefail` makes the pipeline's status the rightmost
non-zero one. So the pipeline returns 141 **precisely when the pattern matches**, and 0 when it does
not. The condition is inverted, silently, only under `pipefail`.

Verified both ways afterwards: the pattern matched (`grep -c` returned 1) while the `if` took the
false branch.

**What makes it nasty** is that `pipefail` is the responsible thing to set, `grep -q` is the
efficient way to test for a match, and each is fine alone. Nothing warns you. And the failure is
silent-and-benign-looking: a script that "ran successfully" and did nothing.

**Avoid it** by not putting `grep -q` at the end of a pipeline under `pipefail`. Ask the tool
directly where you can (`systemctl is-enabled "$unit"` here, returning a value you can compare),
capture to a variable and match with bash's `[[ $var == *pattern* ]]`, or use `grep -c` and test the
count. If you must keep the pipeline, `|| true` on the producer, or drop `pipefail` for that line.

The tell for the whole class: **a loop that reports "nothing to do" for every item.** Occasionally
true; usually the condition is broken.
