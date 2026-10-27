import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register, Timer } from 'claude-code'

import type { Run } from '../types'

const run = atom({ plugin: 'turn-runner', key: 'run' } as const, null)

const TRACK = 32
const STRIDES = ['🏃', '🏃‍➡️']

// Turn length is unknown, so the runner eases toward the line and never
// reaches it until the turn really ends. Tool calls nudge it forward.
const progress = (r: Run) => {
  if (r.endedAt !== null) {
    return 1
  }
  const effort = (r.now - r.startedAt) / 60_000 + r.tools * 0.08

  return Math.min(0.95, 1 - Math.exp(-effort))
}

const clock = (ms: number) => {
  const s = Math.max(0, Math.round(ms / 1000))

  return `${Math.floor(s / 60)}:${String(s % 60).padStart(2, '0')}`
}

// The floating window (~/.claude/turn-runner/TurnRunner.app) draws whatever
// this file says, so the runner stays visible over other apps and Spaces.
const mirror = async ($: EngineInterface, r: Run | null) => {
  // runs in the session's working directory: line 1 is home, line 2 the project
  const { stdout } = await $.process.run(['/bin/sh', '-c', 'echo "$HOME"; pwd'])
  const [home = '', project = ''] = stdout.trim().split('\n')
  const dir = `${home}/.claude/turn-runner`
  await $.fs.write(`${dir}/state.json`, JSON.stringify(r && { ...r, project }))
  if (r !== null && r.endedAt === null) {
    // open -g leaves an already running copy alone and never steals focus
    await $.process.run(['open', '-g', `${dir}/TurnRunner.app`]).catch(() => undefined)
  }
}

export const register: Register = on => {
  let tick: Timer | null = null

  on('turn.start', async ($, e, next) => {
    if (e.agentId !== undefined || tick !== null) {
      return next(e)
    }
    const now = await $.clock.now()
    const fresh: Run = { startedAt: now, now, tools: 0, endedAt: null, reason: null }
    await update($, run, () => fresh)
    void mirror($, fresh)
    tick = $.clock.every(400, async () => {
      const t = await $.clock.now()
      await update($, run, r => (r && r.endedAt === null ? { ...r, now: t } : r))
    })

    return next(e)
  })

  on('tool.call', async ($, e, next) => {
    await update($, run, r => (r && r.endedAt === null ? { ...r, tools: r.tools + 1 } : r))
    void read($, run).then(r => mirror($, r))

    return next(e)
  })

  on('turn.complete', async ($, e, next) => {
    if (e.agentId !== undefined) {
      return next(e)
    }
    tick?.cancel()
    tick = null
    const now = await $.clock.now()
    const r = await read($, run)
    await update($, run, prev => (prev ? { ...prev, now, endedAt: now, reason: e.reason } : prev))
    void read($, run).then(done => mirror($, done))

    const took = r ? clock(now - r.startedAt) : ''
    const headline = e.reason === 'answer' ? `🏁 Finished in ${took}` : `🛑 Stopped (${e.reason}) after ${took}`
    void $.ui.notify(headline, { title: 'Claude Code' })

    return next(e)
  })

  on('ui.render', { component: 'AbovePrompt' }, async ($, e, next) => {
    const r = await read($, run)
    if (e.props.hasSurvey || r === null) {
      return next(e)
    }
    const { Box, Text, Button } = $.ui.resolve(e)

    const done = r.endedAt !== null
    const ok = r.reason === null || r.reason === 'answer'
    const pos = Math.round(progress(r) * (TRACK - 1))
    const elapsed = clock((r.endedAt ?? r.now) - r.startedAt)
    const runner = done ? (ok ? '🙌' : '🛑') : STRIDES[Math.floor(r.now / 400) % STRIDES.length]

    return (
      <Box>
        <Text color={done ? (ok ? 'green' : 'red') : 'yellow'}>
          {'─'.repeat(pos)}
        </Text>
        <Text>{runner}</Text>
        <Text dimColor>{'·'.repeat(TRACK - 1 - pos)}</Text>
        <Text>🏁 </Text>
        <Text dimColor tabular>
          {done ? (ok ? `done in ${elapsed}` : `stopped at ${elapsed}`) : `${elapsed} · ${r.tools} steps`}{' '}
        </Text>
        {done ? <Button key="clear" label="Clear" onPress={() => update($, run, () => null)} /> : null}
      </Box>
    )
  })
}
