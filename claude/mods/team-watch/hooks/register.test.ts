import { expect, mock, test } from 'claude-code/testing'

type Status = 'idle' | 'running' | 'pending'
type Row = { id: string; name: string; status: Status }

const agent = ({ id, name, status }: Row) => ({
  id, name, status, teammateId: `${name}@t`, description: name, type: 'teammate',
})

function stub(on: Parameters<Parameters<typeof test>[1]>[1], rows: Row[]) {
  on('agent.list', () => ({ value: rows.map(agent) }) as never)
  mock.clock(on)
  on('env.get', () => ({ value: undefined }) as never)
  on('session.start', (_, e) => ({ cwd: e.cwd }))
  on('session.send', () => ({ isDelivered: true }))
  on('tool.call', () => ({ result: {} }))
}

const send = ($: Parameters<Parameters<typeof test>[1]>[0], to: string, text: string, agentId?: string) =>
  $.session.send({ to, text, origin: { kind: 'model' }, agentId })

const next = async ($: Parameters<Parameters<typeof test>[1]>[0], agentId: string) =>
  (await $.tool.call({ tool: 'Bash', command: 'ls', agentId })).context ?? []

test('a peer message to a running teammate is injected into its next tool call, naming the sender', async ($, on) => {
  stub(on, [
    { id: 'a-impl', name: 'impl', status: 'running' },
    { id: 'a-arch', name: 'arch', status: 'running' },
  ])
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'stop now', 'a-arch')
  const ctx = await next($, 'a-impl')
  expect(ctx).toEqual(['Message from arch, delivered mid-turn (if it arrives again after your turn, it is a duplicate):\nstop now'])
  expect(await next($, 'a-impl')).toEqual([])
})

test('a lead message to a running teammate is injected, naming team-lead', async ($, on) => {
  stub(on, [{ id: 'b-impl', name: 'impl', status: 'pending' }])
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'wrap up')
  expect(await next($, 'b-impl')).toEqual(['Message from team-lead, delivered mid-turn (if it arrives again after your turn, it is a duplicate):\nwrap up'])
})

test('a sender missing from the roster is named by its id', async ($, on) => {
  stub(on, [{ id: 'c-impl', name: 'impl', status: 'running' }])
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'hello', 'ghost-id')
  expect(await next($, 'c-impl')).toEqual(['Message from ghost-id, delivered mid-turn (if it arrives again after your turn, it is a duplicate):\nhello'])
})

test('a message to an idle teammate is not held', async ($, on) => {
  stub(on, [
    { id: 'd-impl', name: 'impl', status: 'idle' },
    { id: 'd-arch', name: 'arch', status: 'running' },
  ])
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'from peer', 'd-arch')
  await send($, 'impl', 'from lead')
  expect(await next($, 'd-impl')).toEqual([])
})

test('a teammate messaging itself is not held', async ($, on) => {
  stub(on, [{ id: 'e-impl', name: 'impl', status: 'running' }])
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'note to self', 'e-impl')
  expect(await next($, 'e-impl')).toEqual([])
})

test('the later duplicate of an injected peer message is consumed, once', async ($, on) => {
  stub(on, [
    { id: 'f-impl', name: 'impl', status: 'running' },
    { id: 'f-arch', name: 'arch', status: 'running' },
  ])
  on('session.receive', (_, e) => ({ text: e.text }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'stop now', 'f-arch')
  await next($, 'f-impl')
  const dup = await $.session.receive({ origin: { kind: 'peer' }, text: 'stop now', agentId: 'f-impl' })
  expect(dup.consumed).toBeDefined()
  const again = await $.session.receive({ origin: { kind: 'peer' }, text: 'stop now', agentId: 'f-impl' })
  expect(again.consumed).toBeUndefined()
})

test('the later duplicate of an injected lead message is consumed', async ($, on) => {
  stub(on, [{ id: 'g-impl', name: 'impl', status: 'running' }])
  on('session.receive', (_, e) => ({ text: e.text }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'wrap up')
  await next($, 'g-impl')
  const dup = await $.session.receive({ origin: { kind: 'coordinator' }, text: 'wrap up', agentId: 'g-impl' })
  expect(dup.consumed).toBeDefined()
})

test('a held text already in the turn text is dropped at turn.start', async ($, on) => {
  stub(on, [
    { id: 'h-impl', name: 'impl', status: 'running' },
    { id: 'h-arch', name: 'arch', status: 'running' },
  ])
  on('turn.start', () => ({ turnId: 't' }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'stop now', 'h-arch')
  await $.turn.start({ text: 'envelope: stop now', turnId: 't', agentId: 'h-impl' })
  expect(await next($, 'h-impl')).toEqual([])
})

test('a held text the turn text does not contain survives turn.start and is injected', async ($, on) => {
  stub(on, [
    { id: 'i-impl', name: 'impl', status: 'running' },
    { id: 'i-arch', name: 'arch', status: 'running' },
  ])
  on('turn.start', () => ({ turnId: 't' }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'stop now', 'i-arch')
  await $.turn.start({ text: 'something else entirely', turnId: 't', agentId: 'i-impl' })
  expect(await next($, 'i-impl')).toEqual(['Message from arch, delivered mid-turn (if it arrives again after your turn, it is a duplicate):\nstop now'])
})

test('a peer message with other text, or for another agent, is not consumed', async ($, on) => {
  stub(on, [
    { id: 'j-impl', name: 'impl', status: 'running' },
    { id: 'j-arch', name: 'arch', status: 'running' },
    { id: 'j-other', name: 'other', status: 'running' },
  ])
  on('session.receive', (_, e) => ({ text: e.text }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'stop now', 'j-arch')
  await next($, 'j-impl')
  expect((await $.session.receive({ origin: { kind: 'peer' }, text: 'stop later', agentId: 'j-impl' })).consumed).toBeUndefined()
  expect((await $.session.receive({ origin: { kind: 'peer' }, text: 'stop now', agentId: 'j-other' })).consumed).toBeUndefined()
  expect((await $.session.receive({ origin: { kind: 'peer' }, text: 'stop now', agentId: 'j-impl' })).consumed).toBeDefined()
})

test('the same text from a different sender is not consumed as the duplicate', async ($, on) => {
  stub(on, [
    { id: 'k-impl', name: 'impl', status: 'running' },
    { id: 'k-arch', name: 'arch', status: 'running' },
  ])
  on('session.receive', (_, e) => ({ text: e.text }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'ok', 'k-arch')
  await next($, 'k-impl')
  const from = (teammate: string) => ({ kind: 'peer' as const, teammate, isVerified: true })
  expect((await $.session.receive({ origin: from('someone'), text: 'ok', agentId: 'k-impl' })).consumed).toBeUndefined()
  expect((await $.session.receive({ origin: from('arch'), text: 'ok', agentId: 'k-impl' })).consumed).toBeDefined()
})

test('a lead duplicate stamped team-lead is consumed', async ($, on) => {
  stub(on, [{ id: 'l-impl', name: 'impl', status: 'running' }])
  on('session.receive', (_, e) => ({ text: e.text }))
  await $.session.start({ cwd: '/', surface: 'terminal', isInteractive: true })
  await send($, 'impl', 'wrap up')
  await next($, 'l-impl')
  const origin = { kind: 'coordinator' as const, teammate: 'team-lead', isVerified: true }
  expect((await $.session.receive({ origin, text: 'wrap up', agentId: 'l-impl' })).consumed).toBeDefined()
})
