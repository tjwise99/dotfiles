# Claude Code configuration

`CLAUDE.md` in this directory loads into **every context of every project**, so it is kept to rules
that change behaviour. Reference material — anything consulted once a year rather than applied every
session — lives here instead, where it costs nothing until someone opens it.

## What deploys where

`CLAUDE.md`, `settings.json`, `agents/`, `skills/` and `commands/` are symlinked into `~/.claude/`.
The scripts below are invoked by absolute path from `settings.json` and are not linked anywhere.

## Hooks

| Script | Event | Does |
|---|---|---|
| `host-facts.sh` | SessionStart | Emits this machine's resolved state as context |
| `guard-bash.sh` | PreToolUse / Bash | Gates an actual `gh pr merge` or gh `--admin` — `allow` under an unexpired `merge-authorize.sh` grant, else `ask`; matched per simple-command so mentions don't trip it |
| `guard-publish.sh` | PreToolUse / Edit\|Write\|NotebookEdit | Asks before writing network-identifying detail into the published tree |
| `guard-read.sh` | PreToolUse / Read | Denies oversized image reads, with the downscale command to use instead |
| `orchestrator-gate.sh` | PreToolUse / Grep\|Glob, and sourced by the three guards | In orchestrator mode, denies main-thread content-dumping tools so the driver must delegate; exempts subagents (`agent_id`) and the scratch tree |
| `orchestrator-toggle.sh` | UserPromptExpansion | Sets/clears the session's orchestrator-mode marker (human-typed `/orchestrate`, `/work-ticket`, `/discover`, `/plan`, `/implement`) |
| `orchestrator-cleanup.sh` | SessionEnd | Removes this session's orchestrator-mode marker |
| `deliverable-assign.sh` | SubagentStart | In orchestrator mode, tells each subagent the deliverable file it must write |
| `deliverable-verify.sh` | SubagentStop | In orchestrator mode, blocks a subagent's stop until its deliverable file is non-empty (one bounded retry) |

**`guard-read.sh` exists because of a measurement, not a hunch.** Across 107 sessions of
transcripts, 26 image reads accounted for **54% of all tool-result context ever consumed** —
~2.18M tokens, against ~1.83M for the other 6,673 calls combined. One `Read` of a wallpaper cost
166k tokens. The average image read cost ~84k tokens; the average of everything else, 273.

It decides on canvas size where `magick` can measure it, and only falls back to bytes where it
cannot. Checking both would have made the guard reject the very file its own remedy produces — a
downscaled PNG of a dense image stays large on disk — leaving it denying its own fix forever.

**`host-facts.sh` is why `CLAUDE.md` carries no per-host claims.** Which tools exist, where they
resolve, how the GitHub token is stored, whether Docker is installed, whether the sync timer is
running and whether the gitleaks hook is armed all differ between the machines the repo syncs to.
Stating them in prose meant they were wrong on one host and silently rotted on both; resolving them
at session start means they cannot.

Each guard exits silently to allow, or prints a `permissionDecision` JSON envelope. `deny` is used
where the remedy is automatic and lossless — `guard-read.sh` denies an oversized image because the
model downscales and re-reads with no one involved, and the orchestrator gate denies a main-thread
read because the fix is to delegate it. Where the remedy is a human judgement the guard `ask`s
instead — `guard-publish.sh` on network-shaped detail, `guard-bash.sh` on a PR merge. `guard-bash.sh`
gates PR merges — `ask` by default, so approving the harness
prompt is your per-PR authorization, and `allow` when an unexpired grant for that merge sits in
`~/.claude/merge-auth`. That grant is the ahead-of-time path: authorize when you step away, and an
unattended merge lands without a live prompt to block it.

**`merge-authorize.sh` writes that grant** — `--pr N`, optional `--admin`, `--hours H` (default: any
PR, 12h) — to `~/.claude/merge-auth`, which sits outside `~/dotfiles` so it is never published and
carries an expiry so a forgotten grant lapses on its own. `--revoke` deletes it, `--show` prints it.
Run it yourself with `! claude/merge-authorize.sh …`, or tell a session to. `--admin` (branch-
protection bypass) is authorized only when the grant carries `admin=1`; a plain grant will not.

They parse hook input with `jq`, fall back to `python3`, and fall back again to scanning the raw
envelope — a gate that cannot read its input must not silently pass the thing it exists to catch.

## Orchestrator mode

A session-scoped mode that keeps the main thread a lean orchestrator: while it is on, the
content-dumping tools (`Read`, `Edit`/`Write`/`NotebookEdit`, `Grep`/`Glob`, and `Bash` forms that
dump file/diff/tree content — `git show`/`diff`/`log -p`, `rg`, file readers, `gh pr diff`) are
**denied on the main thread**, so the only way to look at or change a file is to send a subagent.
`deny`, not `ask`: the human is never prompted; the model gets a reason and delegates.

- **Marker.** `~/.claude/orchestrator-mode/<session_id>`, contents an epoch expiry (8h). Set/cleared
  by `orchestrator-toggle.sh` on the human-typed commands; removed at `SessionEnd`; a stale or
  corrupt marker is pruned on sight, so it can never gate a later session or wedge this one. Never
  published (`~/.claude` markers are not symlinked into the tree).
- **Subagents are never gated** — the gate exits early on `agent_id`, which is present only inside a
  subagent — so the very agents doing the delegated work are unaffected. Nor is the deliverables
  scratch tree (`/tmp/claude-1000/…`), so the orchestrator can read back what agents write there.
- **Deliverable enforcement.** In orchestrator mode, `deliverable-assign.sh` (SubagentStart) hands
  each subagent a deliverable path — a pure function of `session_id` + `agent_id`, under the scratch
  tree — and `deliverable-verify.sh` (SubagentStop) refuses the subagent's stop until that file is
  non-empty. This makes CLAUDE.md's "a subagent's deliverable is a file it wrote, never its prose"
  structural. Bounded: one enforced retry (`stop_hook_active`) then the harness cap.
- **Enforcement covers in-process subagents, not teammates.** The `/discover`/`/plan`/`/implement`
  flow uses one-shot Task/Agent subagents — they share the session id, carry `agent_id`, and stop
  once, so assign-and-verify fits them exactly. Agent-team *teammates* are different: pane teammates
  (`teammateMode: tmux`/`iterm2`) are separate `claude` processes with their own session id and no
  marker, so they escape enforcement silently; in-process teammates fire `SubagentStop` once per turn,
  so they get nudged rather than cleanly enforced. Teammates coordinate by `SendMessage`, not the
  deliverable file. `teammateMode: auto` resolves to in-process only when the shell is not inside
  tmux/iTerm2 — pin `"teammateMode": "in-process"` for coverage that does not depend on the launching
  terminal (cost: no side-by-side teammate panes).
- **Off by default.** With no marker the gate is inert — a normal session is byte-for-byte unaffected.
  `/orchestrate on|off` toggles it; `/work-ticket`, `/discover`, `/plan`, `/implement` turn it on.

## Restoring an MCP server

None are configured; `host-facts.sh` reports what is live. Both were removed at the user's request —
GitHub work goes through `gh`, browser automation through the Playwright CLI.

- **github** (removed 2026-07-18) needs a PAT minted for it; the keyring token belongs to `gh` and no
  environment variable carries one for this.

      claude mcp add --transport http github https://api.githubcopilot.com/mcp \
        --header "Authorization: Bearer <PAT>"

- **playwright** (removed 2026-07-15). MCP spawns without a shell, so `command` must be an absolute
  npx path — there is no system node.

      claude mcp add-json playwright \
        '{"type":"stdio","command":"'"$(asdf which npx)"'","args":["-y","@playwright/mcp@latest"],"env":{}}'

## Agents and skills

`agents/README.md` holds the agent inventory, which `tools/check-manifest.py` enforces against the
files on disk in both directions — a row naming an agent that is not in the repo, or an agent with no
row, fails the gate.
