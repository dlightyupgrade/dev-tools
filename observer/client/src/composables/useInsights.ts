import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useEventsStore } from '../stores/events'

const FILE_OPS = new Set(['Read', 'Write', 'Edit', 'Glob', 'Grep', 'NotebookEdit'])

export function useInsights() {
  const store = useEventsStore()
  const { events, sessionSummaries } = storeToRefs(store)

  // ── Overview KPIs ──────────────────────────────────────────────────────────

  const overview = computed(() => {
    const totalWallMs = sessionSummaries.value.reduce(
      (s, sess) => s + Math.max(sess.end_ts - sess.start_ts, 0), 0
    )
    const toolCalls = events.value.filter(e => e.hook_event_type === 'PreToolUse').length
    const droidInvocations = events.value.filter(e => e.hook_event_type === 'SubagentStart').length
    return {
      sessions: sessionSummaries.value.length,
      events: events.value.length,
      totalWallMs,
      toolCalls,
      droidInvocations,
    }
  })

  // ── Droid leaderboard ──────────────────────────────────────────────────────

  const droidLeaderboard = computed(() => {
    const map: Record<string, { count: number; color: string; emoji: string; sessions: number }> = {}
    for (const sess of sessionSummaries.value) {
      for (const d of sess.droids) {
        if (!map[d.name]) map[d.name] = { count: 0, color: d.color, emoji: d.emoji, sessions: 0 }
        map[d.name].count += d.count
        map[d.name].sessions++
      }
    }
    const rows = Object.entries(map)
      .map(([name, d]) => ({ name, ...d }))
      .sort((a, b) => b.count - a.count)
    const maxCount = rows[0]?.count ?? 1
    return rows.slice(0, 10).map(r => ({ ...r, pct: (r.count / maxCount) * 100 }))
  })

  // ── Skill frequency ────────────────────────────────────────────────────────

  const skillFrequency = computed(() => {
    const map: Record<string, number> = {}
    for (const sess of sessionSummaries.value) {
      if (sess.skill_name) map[sess.skill_name] = (map[sess.skill_name] ?? 0) + 1
    }
    const rows = Object.entries(map)
      .map(([skill, count]) => ({ skill, count }))
      .sort((a, b) => b.count - a.count)
      .slice(0, 8)
    const max = rows[0]?.count ?? 1
    return rows.map(r => ({ ...r, pct: (r.count / max) * 100 }))
  })

  // ── Tool breakdown ─────────────────────────────────────────────────────────

  const toolBreakdown = computed(() => {
    const cats: Record<string, { count: number; color: string }> = {}

    function add(cat: string, color: string) {
      if (!cats[cat]) cats[cat] = { count: 0, color }
      cats[cat].count++
    }

    for (const e of events.value) {
      if (e.hook_event_type !== 'PreToolUse') continue
      const t = e.tool_name
      if (t === 'Read')      add('Read',    '#9CA3AF')
      else if (t === 'Grep') add('Grep',    '#6B7280')
      else if (t === 'Glob') add('Glob',    '#6B7280')
      else if (t === 'Edit') add('Edit',    '#9CA3AF')
      else if (t === 'Write') add('Write',  '#9CA3AF')
      else if (t === 'Bash') add('Bash',    '#34D399')
      else if (t === 'WebFetch' || t === 'WebSearch') add('Web', '#60A5FA')
      else if (t === 'Skill') add('Skill',  '#A855F7')
      else if (t === 'Task')  add('Task',   '#F59E0B')
      else if (t.startsWith('mcp__')) {
        const svc = t.split('__')[1] ?? 'mcp'
        add(`mcp:${svc}`, svc.includes('atlassian') ? '#06B6D4' : svc.includes('redshift') ? '#10B981' : '#67E8F9')
      }
      else add(t, '#4B5563')
    }

    const rows = Object.entries(cats)
      .map(([name, { count, color }]) => ({ name, count, color }))
      .sort((a, b) => b.count - a.count)
    const total = rows.reduce((s, r) => s + r.count, 0)
    const max = rows[0]?.count ?? 1
    return rows.slice(0, 14).map(r => ({
      ...r,
      pct: (r.count / max) * 100,
      share: total > 0 ? ((r.count / total) * 100).toFixed(0) + '%' : '0%',
    }))
  })

  // ── Activity by day (last 14 days) ────────────────────────────────────────

  // Use local date to avoid UTC roll-over (e.g. sessions after 4pm PST = next UTC day)
  function localDateKey(ts: number): string {
    const d = new Date(ts)
    return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`
  }

  const activityByDay = computed(() => {
    const days: { date: string; label: string; count: number; durationMs: number }[] = []
    const today = new Date()

    for (let i = 13; i >= 0; i--) {
      const d = new Date(today)
      d.setDate(d.getDate() - i)
      const key = localDateKey(d.getTime())
      const label = i === 0 ? 'Today' : i === 1 ? 'Yest' : d.toLocaleDateString('en-US', { weekday: 'short', month: 'numeric', day: 'numeric' })
      days.push({ date: key, label, count: 0, durationMs: 0 })
    }

    for (const sess of sessionSummaries.value) {
      const key = localDateKey(sess.start_ts)
      const day = days.find(d => d.date === key)
      if (day) {
        day.count++
        day.durationMs += Math.max(sess.end_ts - sess.start_ts, 0)
      }
    }

    const maxCount = Math.max(...days.map(d => d.count), 1)
    return days.map(d => ({ ...d, intensity: d.count / maxCount }))
  })

  // ── Ticket leaderboard ────────────────────────────────────────────────────

  const ticketLeaderboard = computed(() => {
    const map: Record<string, number> = {}
    for (const sess of sessionSummaries.value) {
      if (sess.ticket_id) map[sess.ticket_id] = (map[sess.ticket_id] ?? 0) + 1
    }
    return Object.entries(map)
      .map(([ticket, sessions]) => ({ ticket, sessions }))
      .sort((a, b) => b.sessions - a.sessions)
      .slice(0, 8)
  })

  // ── Top sessions ──────────────────────────────────────────────────────────

  const topSessionsByEvents = computed(() =>
    [...sessionSummaries.value]
      .sort((a, b) => b.event_count - a.event_count)
      .slice(0, 6)
  )

  const topSessionsByDuration = computed(() =>
    [...sessionSummaries.value]
      .sort((a, b) => (b.end_ts - b.start_ts) - (a.end_ts - a.start_ts))
      .slice(0, 6)
  )

  // ── Formatters ────────────────────────────────────────────────────────────

  function formatMs(ms: number): string {
    const s = Math.floor(ms / 1000)
    const m = Math.floor(s / 60)
    const h = Math.floor(m / 60)
    if (h > 0) return `${h}h ${m % 60}m`
    if (m > 0) return `${m}m ${s % 60}s`
    return `${s}s`
  }

  return {
    overview,
    droidLeaderboard,
    skillFrequency,
    toolBreakdown,
    activityByDay,
    ticketLeaderboard,
    topSessionsByEvents,
    topSessionsByDuration,
    formatMs,
  }
}
