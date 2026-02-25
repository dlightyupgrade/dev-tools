<template>
  <div
    class="flex items-start gap-3 px-4 py-2.5 border-b border-gray-800 hover:bg-gray-900/50 transition-colors"
    :style="{ borderLeft: `3px solid ${event.droid_color || '#4B5563'}` }"
  >
    <!-- Left: droid badge or event icon -->
    <div class="flex-shrink-0 pt-0.5 w-28">
      <DroidBadge
        v-if="event.droid_name && event.droid_name !== '???'"
        :name="event.droid_name"
        :color="event.droid_color"
        :emoji="event.droid_emoji"
      />
      <span v-else class="text-xs text-gray-500 font-mono">{{ event.hook_event_type }}</span>
    </div>

    <!-- Center: event details -->
    <div class="flex-1 min-w-0">
      <div class="flex items-center gap-2 flex-wrap">
        <span class="text-xs font-semibold text-gray-300">{{ eventLabel }}</span>
        <span v-if="event.tool_name" class="text-xs text-gray-400 font-mono bg-gray-800 px-1.5 rounded">
          {{ event.tool_name }}
        </span>
        <span v-if="event.ticket_id" class="text-xs text-blue-400 font-mono">
          {{ event.ticket_id }}
        </span>
        <span v-if="event.skill_name" class="text-xs text-purple-400 font-mono">
          /{{ event.skill_name }}
        </span>
      </div>
      <div v-if="promptPreview" class="text-xs text-gray-500 mt-0.5 truncate">
        {{ promptPreview }}
      </div>
    </div>

    <!-- Right: timestamp + duration -->
    <div class="flex-shrink-0 text-right">
      <div class="text-xs text-gray-500 font-mono">{{ formattedTime }}</div>
      <div v-if="duration" class="text-xs text-amber-400 font-mono mt-0.5">{{ duration }}</div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import DroidBadge from './DroidBadge.vue'
import type { ObserverEvent } from '../types/events'

const props = defineProps<{
  event: ObserverEvent
  durationMs?: number
}>()

const EVENT_LABELS: Record<string, string> = {
  SubagentStart:    'Droid invoked',
  SubagentStop:     'Droid done',
  UserPromptSubmit: 'User prompt',
  PreToolUse:       'Tool start',
  PostToolUse:      'Tool done',
}

const eventLabel = computed(() => EVENT_LABELS[props.event.hook_event_type] ?? props.event.hook_event_type)

const promptPreview = computed(() => {
  const p = props.event.payload
  return (p?.prompt_preview as string) ?? ''
})

const formattedTime = computed(() => {
  const d = new Date(props.event.timestamp)
  return d.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
})

const duration = computed(() => {
  if (!props.durationMs) return ''
  if (props.durationMs < 1000) return `${props.durationMs}ms`
  return `${(props.durationMs / 1000).toFixed(1)}s`
})
</script>
