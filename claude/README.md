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
| `guard-bash.sh` | PreToolUse / Bash | Denies PR merges and `--admin`; asks on unconfirmed-HEAD commits |
| `guard-publish.sh` | PreToolUse / Edit\|Write | Asks before writing network-identifying detail into the published tree |
| `guard-read.sh` | PreToolUse / Read | Denies oversized image reads, with the downscale command to use instead |

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
only where the rule is categorical (a PR merge); heuristics use `ask`, because a gate that hard-
refuses legal input with no override is a worse failure than one that surfaces a question.

They parse hook input with `jq`, fall back to `python3`, and fall back again to scanning the raw
envelope — a gate that cannot read its input must not silently pass the thing it exists to catch.

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
