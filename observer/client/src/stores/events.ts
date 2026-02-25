import { defineStore } from 'pinia'
import { ref, computed } from 'vue'
import type { ObserverEvent, FilterOptions, ActiveFilters, SessionSummary } from '../types/events'

const SERVER = 'http://localhost:4001'

export const useEventsStore = defineStore('events', () => {
  const events = ref<ObserverEvent[]>([])
  const filterOptions = ref<FilterOptions>({ sessions: [], droids: [], skills: [], event_types: [] })
  const filters = ref<ActiveFilters>({ session: '', droid: '', skill: '', event_type: '' })
  const loading = ref(false)

  const filteredEvents = computed(() => {
    return events.value.filter(e => {
      if (filters.value.session && e.session_id !== filters.value.session) return false
      if (filters.value.droid && e.droid_name !== filters.value.droid) return false
      if (filters.value.skill && e.skill_name !== filters.value.skill) return false
      if (filters.value.event_type && e.hook_event_type !== filters.value.event_type) return false
      return true
    })
  })

  const activeMission = computed(() => {
    const latest = events.value.findLast(e => e.skill_name || e.ticket_id)
    return latest ? { skill: latest.skill_name, ticket: latest.ticket_id } : null
  })

  const droidStats = computed(() => {
    const counts: Record<string, { name: string; color: string; emoji: string; count: number; totalMs: number }> = {}
    const starts: Record<string, number> = {}

    for (const e of filteredEvents.value) {
      if (!e.droid_name || e.droid_name === '???') continue

      if (!counts[e.droid_name]) {
        counts[e.droid_name] = {
          name: e.droid_name,
          color: e.droid_color,
          emoji: e.droid_emoji,
          count: 0,
          totalMs: 0,
        }
      }

      if (e.hook_event_type === 'SubagentStart') {
        counts[e.droid_name].count++
        starts[e.session_id + e.droid_name] = e.timestamp
      } else if (e.hook_event_type === 'SubagentStop') {
        const key = e.session_id + e.droid_name
        if (starts[key]) {
          counts[e.droid_name].totalMs += e.timestamp - starts[key]
          delete starts[key]
        }
      }
    }

    return Object.values(counts).sort((a, b) => b.count - a.count)
  })

  const sessionIds = computed(() => [...new Set(events.value.map(e => e.session_id).filter(Boolean))])

  const sessionSummaries = computed((): SessionSummary[] => {
    const groups: Record<string, ObserverEvent[]> = {}
    for (const e of events.value) {
      if (!e.session_id) continue
      if (!groups[e.session_id]) groups[e.session_id] = []
      groups[e.session_id].push(e)
    }

    const TEN_MINUTES = 10 * 60 * 1000
    const now = Date.now()

    return Object.entries(groups).map(([session_id, evts]) => {
      const sorted = [...evts].sort((a, b) => a.timestamp - b.timestamp)
      const start_ts = sorted[0].timestamp
      const end_ts = sorted[sorted.length - 1].timestamp

      const droidCounts: Record<string, { name: string; color: string; emoji: string; count: number }> = {}
      for (const e of sorted) {
        if (!e.droid_name || e.droid_name === '???') continue
        if (e.hook_event_type !== 'SubagentStart') continue
        if (!droidCounts[e.droid_name]) {
          droidCounts[e.droid_name] = { name: e.droid_name, color: e.droid_color, emoji: e.droid_emoji, count: 0 }
        }
        droidCounts[e.droid_name].count++
      }
      const droids = Object.values(droidCounts).sort((a, b) => b.count - a.count)

      const skillEvent = sorted.find(e => e.skill_name)
      const ticketEvent = sorted.find(e => e.ticket_id)

      const dominant_color = droids[0]?.color ?? '#4B5563'
      const is_active = (now - end_ts) < TEN_MINUTES

      const firstPromptEvent = sorted.find(e => e.hook_event_type === 'UserPromptSubmit')
      const first_prompt = (firstPromptEvent?.payload?.prompt_preview as string) ?? ''

      return {
        session_id,
        event_count: sorted.length,
        droids,
        skill_name: skillEvent?.skill_name ?? '',
        ticket_id: ticketEvent?.ticket_id ?? '',
        start_ts,
        end_ts,
        is_active,
        dominant_color,
        first_prompt,
      }
    }).sort((a, b) => {
      if (a.is_active !== b.is_active) return a.is_active ? -1 : 1
      return b.end_ts - a.end_ts
    })
  })

  function getSessionEvents(sessionId: string): ObserverEvent[] {
    return events.value
      .filter(e => e.session_id === sessionId)
      .sort((a, b) => a.timestamp - b.timestamp)
  }

  const oldestTimestamp = computed(() => {
    const ts = filteredEvents.value.map(e => e.timestamp)
    return ts.length ? Math.min(...ts) : 0
  })

  async function fetchEvents() {
    loading.value = true
    try {
      const res = await fetch(`${SERVER}/events?limit=500`)
      const data: ObserverEvent[] = await res.json()
      events.value = data.reverse() // oldest first for timeline
    } finally {
      loading.value = false
    }
  }

  async function fetchFilterOptions() {
    const res = await fetch(`${SERVER}/events/filter-options`)
    filterOptions.value = await res.json()
  }

  function pushEvent(event: ObserverEvent) {
    events.value.push(event)
    // Keep filter options fresh
    if (event.session_id && !filterOptions.value.sessions.includes(event.session_id)) {
      filterOptions.value.sessions.push(event.session_id)
    }
    if (event.droid_name && event.droid_name !== '???' && !filterOptions.value.droids.includes(event.droid_name)) {
      filterOptions.value.droids.push(event.droid_name)
    }
    if (event.skill_name && !filterOptions.value.skills.includes(event.skill_name)) {
      filterOptions.value.skills.push(event.skill_name)
    }
    if (!filterOptions.value.event_types.includes(event.hook_event_type)) {
      filterOptions.value.event_types.push(event.hook_event_type)
    }
  }

  function setFilter(key: keyof ActiveFilters, value: string) {
    filters.value[key] = value
  }

  function clearFilters() {
    filters.value = { session: '', droid: '', skill: '', event_type: '' }
  }

  async function clearEvents() {
    await fetch(`${SERVER}/events`, { method: 'DELETE' })
    events.value = []
    filterOptions.value = { sessions: [], droids: [], skills: [], event_types: [] }
  }

  async function deleteSession(sessionId: string) {
    await fetch(`${SERVER}/events/session/${sessionId}`, { method: 'DELETE' })
    events.value = events.value.filter(e => e.session_id !== sessionId)
  }

  return {
    events,
    filteredEvents,
    filterOptions,
    filters,
    loading,
    activeMission,
    droidStats,
    sessionIds,
    oldestTimestamp,
    fetchEvents,
    fetchFilterOptions,
    pushEvent,
    setFilter,
    clearFilters,
    clearEvents,
    sessionSummaries,
    getSessionEvents,
    deleteSession,
  }
})
