---
name: distill-need
description: >-
  Turn a proposed check, requirement or ticket bullet into the one need it serves, or strike it.
  Two tests in order: whose need is it (the unit under verification, the application it hosts,
  or the verification tier itself); and is the text a want or a list of mechanisms in different
  clothes. Invoke before writing a requirement, before briefing an implementer, when a tree item
  "feels like a listicle", or when a ticket names a mechanism ("run tool X") instead of a need.
---

# Distill the need

A check, a requirement or a ticket bullet earns its place only by the need it serves. Most bad
items fail one of two tests, in this order. Apply them in writing, before anything is built.

## 1. Whose need is it? (the subject test)

Name the subject of every item and every check. There are exactly three answers:

- **The unit under verification.** Its needs are about the unit itself: it boots, it shows its
  display, it is provisioned, it updates, it recovers, its image carries what it ships. State
  these as what a person at the device needs, never as what a module, selector, flag or file does.
- **The application it hosts.** Its page states, selectors, error classes, layout rules, source
  constants, bundle attributes. These are the application's own tier. Never write them into the
  unit's tree, even reworded as a need ("the display says it is degraded" is the application's).
- **The verification tier itself.** Proving a check can fail, tying a tested artefact to a shipped
  one, refusing the wrong board, ensuring the suite runs what it should. This is the pipeline doing
  its job: it lives as a gate, a guard or a self-test and never as a requirement item.

Strike anything that is not the unit's. A check with the wrong subject can still be useful as
instrumentation (recorded, never asserted) or as a gate, but it is not a need.

## 2. Is it a want, or a list in different clothes?

Read the text and ask what the person at the device would say they need. If the sentence names
three things joined by "and" — flags, files, services, attributes — it is a list of mechanisms,
not a need. Rewrite it as the one outcome those mechanisms exist for, in one sentence:

- *list:* "the display service shall start with blanking off and no cursor, and every shipped
  service shall be loadable with its dependencies met"
- *need:* "after an update, the kiosk shall come back showing its display without anyone
  attending it"

Then let the test items carry the specifics as a **decomposition** of that one need: each test
verifies one way the need can fail, and the need's justification names which failure each test
settles and what stays unproven. A test that does not decompose the need (it verifies the tier's
own integrity) is a gate, not a test item — back to test 1.

Mechanisms named by a ticket ("run `tool-x verify`") are proposals, not needs. Find the need they
serve, then ask whether the unit's own facilities already answer it before adding a dependency.

## Output

A table: item or check → subject → disposition (built as a need / built as a gate / recorded only /
struck), and the one-sentence need with its decomposition. Nothing is briefed to an implementer
until this table exists.
