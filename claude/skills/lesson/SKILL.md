---
name: lesson
description: >-
  Suggest journal entries for ~/lessons/ from the current session — useful tools, ideas, concepts,
  gotchas worth rereading later. Invoke when the user asks "any lessons", "capture that", "write
  that down for next time", or wants a session mined for notes. Proposes; the user approves before
  anything is written. Repo-agnostic.
---

# Suggest a journal entry

`~/lessons/` is the user's lecture notes to themselves — one file per topic, newest entry at the
top. Read its README for the current topic list, and read any file an entry would join before
appending to it.

## Find what was worth learning

Look back over the session for things a reader would want on hand later:

- **A tool or concept** that had to be understood before the work could proceed.
- **A gotcha** — something that behaved differently than expected, or cost more than one attempt.
- **A distinction** that mattered: two things being treated as one that turned out to differ.
- **A position that changed**, and what changed it.

Prefer what generalises past the project it came from. Something that only makes sense with one
repository's structure in mind is better off in that repository; something true of this machine
belongs in the project's `CLAUDE.local.md`. Say so rather than forcing it into a note.

## Propose

Two or three at most, a few lines each: what the note would say, which file it joins, and the case
it came from — project, ticket, what was actually observed. A note with a real case attached
survives being reread; a bare principle does not.

Then stop and let the user pick and edit. If nothing this session is worth writing down, say that —
it is a normal answer and a frequent one.

## Write what is approved

- Append under `## YYYY-MM-DD — <short title> (<project> <ticket>)`, newest first. Take the date
  from the environment.
- A new topic file gets a row in the README's table.
- Where a note contradicts an older one, say so in the new entry and leave the old one — the change
  of mind is the interesting part.
- Never write an entry the user has not approved, and never edit a project repository from here.
