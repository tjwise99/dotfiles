# C4 modelling

## 2026-08-04 — first System Context (WiseKiosk #96, LikeC4)

**Four levels of zoom over one model, not four diagrams.** Context → Container → Component → Code.
Each level is an **audience**, not a detail budget, and the test of a level is whether that audience
can read it without the level below: someone who does not know what the system is (L1), someone
deploying it (L2), someone changing one runnable thing (L3), nobody (L4 — generated if ever).

**"Container" does not mean Docker container.** It is a separately runnable thing with its own
runtime — a process, a browser app, a database. WiseKiosk ships one image holding two containers: the
Go process and the SPA running in the display's browser. The word misleads every time.

### What L1 asserts, and nothing else

One opaque box for the system, the **actors** who interact with it *by role*, and the **external
systems** it exchanges data with. Plus relationships labelled with **intent** ("proxies read-only,
TTL-cached"), with mechanism in a separate `technology` field.

It is not deployment topology, not data flow, not a sequence. If the L1 diagram tells you there is a
Go backend inside, it has leaked.

### The three things that were actually hard

**The boundary is a decision, not an observation.** There is no fact about whether the desk-side
config validator "is part of" the system. It depends entirely on what you decide the boundary
*means*, and several meanings are defensible: what ships together, what you author and version
together, what fails together, who owns it. Pick one, write it down, apply it consistently. A
diagram whose criterion shifts box to box is worse than none, because it renders and reads as
settled. Choosing "what deploys" then answered the desk-tooling question with no further argument —
which is what a good criterion buys.

**Draw the boundary first.** Both "actor" and "external system" are defined *relative to* it, so
nothing else is answerable until it is fixed. Taking the trades in the order the ticket listed them
would have been backwards.

**"Outside the boundary" and "on the diagram" are different questions.** An external system earns a
box only if the system *exchanges something with it*. The desk validator reads a file on a laptop
and the system never knows it ran — so it is not drawn at all, not even as a muted box. Scope of
project and context of system are different sets, and L1 draws the second. This is not a gap in the
diagram; it is the diagram declining to assert something.

### Two errors worth remembering

**A passive actor is still an actor** — the most-missed L1 element, dropped because "they don't do
anything." The Viewer receives the display and provides no input, and two of seven system-tier
requirements were obligations to that person. Before the model had a Viewer, those requirements had
nobody to be *about*. The arrow direction is the signal: an actor the system points *at* is real.

**Do not split an actor further than the specification does.** Installing, configuring and viewing
looked like three roles. The requirement covering deployment made no distinction between installing
and configuring — both are "parameters supplied from outside" — so splitting them would have put a
boundary in the diagram that the specification refuses to put in the requirement. The model may not
be more opinionated than what it traces to.

### The one that generalises furthest

**The model is downstream of the requirements, and every question had an answer already sitting in
them.** The trades that felt like architecture judgement were all decided by reading the tree: which
actors exist, whether upstreams are one box or many, which tier a traceability tag names. Twice a
position reached by general architecture instinct was wrong, and the specification said so both
times. Notation is a week's reading. Knowing the model is downstream is the part that transfers.

### Mechanics worth carrying to any C4-as-code tool

- **Validation is the real gate, not generation.** The generator emitted output for a broken model
  without complaining, and so did the JSON exporter — with the tags silently missing. Anything
  reading a model's export must validate first, or it reads a broken model as an empty one.
- **A generator that writes but never prunes defeats a staleness check.** Delete a view and its
  artifact stays behind, byte-identical to what is committed, so a diff-based check sees nothing.
  Clear the output directory before generating.
- **A diagram that renders is not a diagram that is correct.** A build can pass with a diagram block
  full of unparseable text; the failure surfaces in the reader's browser. Worth knowing what your
  docs pipeline actually checks.
