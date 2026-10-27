export type Run = {
  startedAt: number
  now: number
  tools: number
  endedAt: number | null
  reason: 'answer' | 'aborted' | 'refusal' | 'error' | null
}

declare module 'claude-code' {
  interface PluginState {
    'turn-runner': { run: Run | null }
  }
}
