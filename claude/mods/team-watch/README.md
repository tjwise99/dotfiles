# team-watch

A Claude Code mod (hooks module) for agent-team sessions with in-process teammates. It works around
harness behaviour that makes a lead either deaf to its team or flooded by it.

| Harness behaviour | What the mod does |
|---|---|
| A lead's SendMessage to a busy teammate is held until the teammate's turn ends (anthropics/claude-code issue #99111 mid-turn delivery) | Adds the message to the teammate's next tool result as context; drops the harness's later duplicate |
| Every teammate turn end sends the lead an idle notification, which wakes it and stays in its context | Swallows idle notifications before they are queued |
| A background command finishing while its teammate is idle never starts the teammate's turn | Nudges the teammate 30 s after the completion notice if it has not run |
| A teammate that stops, fails or is killed without reporting is never surfaced | When nothing in the team is moving, sends the lead one line naming every teammate that stopped without telling anyone |
| A long wait gives the lead no signal | After 10 min with no team activity, sends the lead one line naming what is outstanding |

"Moving" means a teammate mid-turn, a teammate waiting on its own background command, a completion
notice not yet picked up, or a message sent to a teammate that has not started its turn. A teammate
waiting on a peer therefore never reads as quiet. A turn that ended with a message to anyone (lead or
peer) is not silent.

Swallowing idle notifications also drops a teammate's final reply text, which reached the lead only
inside them. The mod adds one line to every teammate's system prompt saying that anything the lead
must see goes through SendMessage.

## Where it loads

`CLAUDE_CODE_PLUGIN_DIRS` in `claude/settings.json` names this folder. Remove the entry to disable
it; sessions already running keep their copy until restarted.

## Logs

One file per session at `~/.claude/team-watch/<session start>.log`, outside the repo. The log holds
message excerpts, so it must never move under `~/dotfiles`.

## Testing

`TEAM_WATCH_WAKE_MS` and `TEAM_WATCH_STALL_MS` override the 30 s nudge and the 10 min stall
threshold, so a live test of every path takes minutes. Load a copy for one session only with
`claude --plugin-dir <folder>`.

## Known gaps

- A clean shutdown (`shutdown_request` approved mid-turn) is expected not to be named as a silent
  stop; that path is reasoned, not yet seen live.
- State is in memory: if the hooks module reloads mid-session, held messages and tracked background
  commands are forgotten.
- If the harness ever delivers a held message mid-turn on its own, the teammate sees it twice.
- Timing windows of one `$.agent.list()` call can misread a just-spawned teammate.
