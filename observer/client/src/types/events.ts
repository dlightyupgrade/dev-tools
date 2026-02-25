export interface SessionSummary {
  session_id: string
  event_count: number
  droids: Array<{ name: string; color: string; emoji: string; count: number }>
  skill_name: string
  ticket_id: string
  start_ts: number
  end_ts: number
  is_active: boolean
  dominant_color: string
  first_prompt: string
}

export interface ObserverEvent {
  id: string
  session_id: string
  hook_event_type: string
  source_app: string
  agent_type: string
  droid_name: string
  droid_color: string
  droid_emoji: string
  skill_name: string
  ticket_id: string
  tool_name: string
  payload: Record<string, unknown>
  timestamp: number
}

export interface DroidConfig {
  name: string
  color: string
  emoji: string
}

export interface FilterOptions {
  sessions: string[]
  droids: string[]
  skills: string[]
  event_types: string[]
}

export interface ActiveFilters {
  session: string
  droid: string
  skill: string
  event_type: string
}
