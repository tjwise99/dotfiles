import type { Register, EngineInterface, AgentInfo } from 'claude-code'

const TICK_MS = 5_000
const BUSY = new Set(['pending', 'running', 'waiting'])
const IDLE_PREFIX = '{"type":"idle_notification"'
const LEAD = new Set(['team-lead', 'main'])

type Bg = { agentId: string; command: string; startedAt: number }
type Parked = { since: number; task: string; outputFile: string }
type Notice = { kind: 'quiet' | 'stall'; text: string; silent: string[]; at: number }
type Timer = ReturnType<EngineInterface['clock']['every']>

let wakeAfterMs = 30_000
let stallAfterMs = 10 * 60_000

const heldForMidTurn = new Map<string, string[]>()
const injected = new Map<string, string[]>()
const inTransit = new Set<string>()
const bgRunning = new Map<string, Bg>()
const parked = new Map<string, Parked>()
// True only while session.receive swallows idle notices, which carry a teammate's final reply.
const TEAMMATE_RULE = 'Your final reply text at the end of a turn is not delivered to anyone. Anything the team lead must see (a question, a request for a ruling, a result, a blocker) must be sent with SendMessage to team-lead.'

const spokeThisTurn = new Set<string>()
const silentStoppers = new Map<string, { name: string; at: number }>()
let ticker: Timer | undefined
let lastActivity = Date.now()
let quietSent = true
let stallSent = false
let mainRunning = false
let deferred: Notice | undefined

const lines: string[] = []
let logPath: string | undefined
let flushing = Promise.resolve()
function log($: EngineInterface, ...parts: unknown[]) {
  const text = parts.map(p => (typeof p === 'string' ? p : JSON.stringify(p))).join(' ')
  lines.push(`${new Date().toISOString()} ${text.replace(/\s+/g, ' ').slice(0, 300)}`)
  if (lines.length > 2000) lines.splice(0, lines.length - 2000)
  const path = logPath
  if (path) flushing = flushing.then(() => $.fs.write(path, lines.join('\n') + '\n')).catch(() => {})
}

async function teammates($: EngineInterface): Promise<AgentInfo[] | undefined> {
  try {
    return (await $.agent.list()).filter(a => a.teammateId !== undefined)
  } catch {
    return undefined
  }
}

async function isTeammate($: EngineInterface, id: string | undefined) {
  return id !== undefined && (await teammates($) ?? []).some(a => a.id === id)
}

function markBusy() {
  lastActivity = Date.now()
  quietSent = false
  stallSent = false
}

function stillTrue(n: Notice) {
  return n.kind === 'quiet' ? quietSent : stallSent
}

async function notifyLead($: EngineInterface, n: Notice) {
  if (mainRunning) {
    deferred = n
    log($, 'DEFER', n.kind)
    return
  }
  log($, 'NOTIFY', n.text)
  const r = await $.prompt.submit({ text: n.text })
  if (r.drop !== undefined) return log($, 'NOTIFY-DROPPED', r.drop)
  for (const id of n.silent) {
    if ((silentStoppers.get(id)?.at ?? Infinity) <= n.at) silentStoppers.delete(id)
  }
}

function taskDone($: EngineInterface, text: string) {
  for (const [, task = ''] of text.matchAll(/<task-id>(\w+)<\/task-id>/g)) {
    const bg = bgRunning.get(task)
    if (bg === undefined) continue
    bgRunning.delete(task)
    lastActivity = Date.now()
    const outputFile = /<output-file>([^<]+)<\/output-file>/.exec(text)?.[1] ?? 'its output file'
    parked.set(bg.agentId, { since: Date.now(), task, outputFile })
    log($, 'BG-DONE', bg.agentId, task)
  }
}

function prune(team: AgentInfo[]) {
  const live = new Set(team.filter(a => a.status !== 'completed' && a.status !== 'failed' && a.status !== 'killed').map(a => a.id))
  for (const id of [...parked.keys(), ...inTransit]) {
    if (live.has(id)) continue
    parked.delete(id)
    inTransit.delete(id)
  }
  for (const [task, bg] of bgRunning) if (!live.has(bg.agentId)) bgRunning.delete(task)
}

const inTurn = new Map<string, string>()
function noteDeaths($: EngineInterface, team: AgentInfo[], now: number) {
  for (const [id, name] of inTurn) {
    const status = team.find(a => a.id === id)?.status
    if (status !== undefined && status !== 'failed' && status !== 'killed') continue
    inTurn.delete(id)
    if (spokeThisTurn.delete(id)) continue
    silentStoppers.set(id, { name, at: now })
    log($, 'DIED-MIDTURN', name, status ?? 'gone')
  }
}

let ticks = 0
async function tick($: EngineInterface) {
  const now = Date.now()
  const team = await teammates($)
  if (team === undefined) return
  noteDeaths($, team, now)
  prune(team)
  const name = (id: string) => team.find(a => a.id === id)?.name ?? id
  if (++ticks % 6 === 0) log($, 'TICK', { team: team.map(a => `${a.name}:${a.status}`), bg: [...bgRunning.keys()], parked: [...parked.keys()], inTransit: [...inTransit], silent: [...silentStoppers.values()].map(s => s.name) })

  let woke = false
  for (const [agentId, p] of parked) {
    const status = team.find(a => a.id === agentId)?.status
    if (status !== 'idle' && status !== 'waiting') continue
    if (now - p.since < wakeAfterMs) continue
    parked.delete(agentId)
    inTransit.add(agentId)
    woke = true
    const sent = await $.session.send({ to: { agentId }, text: `team-watch: your background command ${p.task} finished; its output is in ${p.outputFile}. Continue your work.` })
    if (!sent.isDelivered) inTransit.delete(agentId)
    log($, 'WAKE', agentId, p.task, status, sent)
  }
  if (woke || (team.length === 0 && silentStoppers.size === 0)) return

  const busy = team.filter(a => BUSY.has(a.status))
  const quiet = busy.length === 0 && parked.size === 0 && inTransit.size === 0

  if (quiet && !quietSent) {
    quietSent = true
    const silent = [...silentStoppers.keys()]
    const label = (id: string) => {
      const status = team.find(a => a.id === id)?.status ?? 'ended'
      const n = silentStoppers.get(id)?.name ?? id
      return status === 'idle' ? n : `${n} (${status})`
    }
    log($, 'QUIET', { silent: silent.map(label) })
    if (silent.length) await notifyLead($, { kind: 'quiet', silent, at: now, text: `team-watch: team quiet (no teammate working, no background command running, no message in flight). Stopped without telling anyone: ${silent.map(label).join(', ')}` })
    return
  }

  if (!quiet && !stallSent && now - lastActivity > stallAfterMs) {
    stallSent = true
    const bgOwners = new Set([...bgRunning.values()].map(b => b.agentId))
    const waits = [
      ...[...bgRunning.entries()].map(([id, b]) => `${name(b.agentId)} on \`${b.command.slice(0, 60)}\` (${id}, ${Math.round((now - b.startedAt) / 60_000)}m)`),
      ...busy.filter(a => !bgOwners.has(a.id)).map(a => `${a.name} (${a.status})`),
      ...[...parked.keys()].map(id => `${name(id)} has an unread completion notice`),
      ...[...inTransit].map(id => `undelivered message to ${name(id)}`),
    ]
    log($, 'STALL', waits)
    await notifyLead($, { kind: 'stall', silent: [], at: now, text: `team-watch: no team activity for ${Math.round(stallAfterMs / 60_000)}m. Waiting: ${waits.join('; ') || 'nothing tracked'}` })
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    wakeAfterMs = Number(await $.env.get('TEAM_WATCH_WAKE_MS')) || wakeAfterMs
    stallAfterMs = Number(await $.env.get('TEAM_WATCH_STALL_MS')) || stallAfterMs
    logPath ??= `${(await $.env.get('HOME')) ?? '/tmp'}/.claude/team-watch/${new Date().toISOString().replace(/[:.]/g, '-')}.log`
    ticker?.cancel()
    ticker = $.clock.every(TICK_MS, () => void tick($).catch(err => log($, 'TICK-ERR', String(err))))
    log($, 'START', { wakeAfterMs, stallAfterMs })
    return next(e)
  })

  on('turn.start', async ($, e, next) => {
    const id = e.agentId
    if (id === undefined) mainRunning = true
    const me = (await teammates($))?.find(a => a.id === id)
    if (me) {
      const agentId = me.id
      inTurn.set(agentId, me.name ?? agentId)
      log($, 'TURN-START', agentId)
      inTransit.delete(agentId)
      parked.delete(agentId)
      injected.delete(agentId)
      spokeThisTurn.delete(agentId)
      const held = (heldForMidTurn.get(agentId) ?? []).filter(t => !e.text.includes(t))
      if (held.length) heldForMidTurn.set(agentId, held)
      else heldForMidTurn.delete(agentId)
      markBusy()
    }
    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    const id = e.agentId
    if (id === undefined) {
      mainRunning = false
      const n = deferred
      deferred = undefined
      if (n && stillTrue(n)) void notifyLead($, n)
      else if (n) log($, 'DROP-STALE', n.kind)
    } else {
      const me = (await teammates($))?.find(a => a.id === id)
      if (me) {
        inTurn.delete(id)
        if (!spokeThisTurn.delete(id)) silentStoppers.set(id, { name: me.name ?? id, at: Date.now() })
        lastActivity = Date.now()
      }
    }
    return next(e)
  })

  on('prompt.compose', async ($, e, next) => {
    const r = await next(e)
    if (!e.traits.includes('teammate')) return r
    log($, 'COMPOSE-TEAMMATE', r.sections.length)
    return { sections: [...r.sections, { id: 'team-watch:reporting', text: TEAMMATE_RULE, scope: 'session' as const }] }
  })

  on('session.send', async ($, e, next) => {
    const target = (await teammates($))?.find(a => a.name === e.to || a.id === e.to)
    if (target) inTransit.add(target.id)
    const sent = await next(e)
    log($, 'SEND', { from: e.agentId ?? 'main', to: e.to, delivered: sent.isDelivered, text: e.text.slice(0, 60) })
    if (!sent.isDelivered) {
      if (target) inTransit.delete(target.id)
      return sent
    }
    if (e.agentId !== undefined && (target !== undefined || LEAD.has(e.to))) {
      spokeThisTurn.add(e.agentId)
      silentStoppers.delete(e.agentId)
    }
    if (target === undefined) return sent
    markBusy()
    if (e.agentId === undefined && (target.status === 'running' || target.status === 'pending')) {
      heldForMidTurn.set(target.id, [...(heldForMidTurn.get(target.id) ?? []), e.text])
      log($, 'HELD-FOR-MIDTURN', target.id)
    }
    return sent
  })

  on('tool.call', async ($, e, next) => {
    const r = await next(e)
    if (r.deny !== undefined || !(await isTeammate($, e.agentId))) return r
    const agentId = e.agentId as string
    lastActivity = Date.now()
    parked.delete(agentId)
    const res: { backgroundTaskId?: unknown } = r.result ?? {}
    if (e.tool === 'Bash' && typeof res.backgroundTaskId === 'string') {
      bgRunning.set(res.backgroundTaskId, { agentId, command: e.command, startedAt: Date.now() })
      log($, 'BG-START', agentId, res.backgroundTaskId)
    }
    const held = heldForMidTurn.get(agentId)
    if (!held?.length) return r
    heldForMidTurn.delete(agentId)
    injected.set(agentId, [...(injected.get(agentId) ?? []), ...held])
    log($, 'INJECT', agentId, e.tool)
    const note = held.map(t => `Message from team-lead, delivered mid-turn (if it arrives again after your turn, it is a duplicate):\n${t}`)
    return { ...r, context: [...(r.context ?? []), ...note] }
  })

  on('session.receive', async ($, e, next) => {
    log($, 'RECV', { to: e.agentId ?? 'main', origin: e.origin.kind, text: e.text.slice(0, 100) })

    if (e.agentId === undefined) {
      if (e.text.trimStart().startsWith(IDLE_PREFIX)) return { consumed: 'team-watch: idle notice suppressed' }
      return next(e)
    }

    const sent = injected.get(e.agentId) ?? []
    const dup = e.origin.kind === 'coordinator' ? sent.find(t => e.text.trim() === t.trim()) : undefined
    if (dup !== undefined) {
      injected.set(e.agentId, sent.filter(t => t !== dup))
      inTransit.delete(e.agentId)
      log($, 'CONSUME-DUP', e.agentId)
      return { consumed: 'team-watch: already delivered mid-turn' }
    }

    taskDone($, e.text)
    return next(e)
  })

  on('session.append', { door: 'queue' }, async ($, e, next) => {
    const text = e.message.content.map(b => ('text' in b && typeof b.text === 'string' ? b.text : '')).join('\n')
    if (text.includes('<task-id>')) taskDone($, text)
    return next(e)
  })
}
