# Lessons

Lecture notes to myself. Tools, ideas, concepts — whatever is worth rereading when something
familiar comes up.

One file per topic, newest entry at the top, each dated and naming where it came from so the
reasoning can be checked later rather than taken on trust. Write freely; a note that turns out to be
obvious later cost nothing.

Lives beside the projects rather than inside one, so it survives any of them.

## Notes

| Topic | |
|---|---|
| [C4 modelling](c4-modelling.md) | Levels, what the Context level asserts, the boundary as a decision |
| [Designing gates](designing-gates.md) | Guards that answer when they can't run; always-red gates; safety machinery that fails |
| [Exit codes that lie](exit-codes.md) | Pipelines reporting the wrong status; `pipefail` + `grep -q` inverting a match |
| [Remote diagnosis](remote-diagnosis.md) | Make it observable before theorising; read the version; busy vs blocked |
| [Supervising agents](supervising-agents.md) | Questions that catch real errors, and the failure modes to expect |
