<template>
  <div ref="containerEl" class="flex-1 overflow-y-auto">
    <TransitionGroup name="event-enter" tag="div">
      <div
        v-for="(event, idx) in visibleEvents"
        :key="event.id"
        class="flex items-start gap-3 px-4 py-2.5 border-b border-gray-800 transition-colors"
        :class="idx === visibleEvents.length - 1 ? 'event-current' : ''"
        :style="{ borderLeft: `3px solid ${event.droid_color || '#4B5563'}` }"
      >
        <!-- Droid badge -->
        <div class="flex-shrink-0 pt-0.5 w-28">
          <span
            v-if="event.droid_name && event.droid_name !== '???'"
            class="inline-flex items-center gap-1 text-xs font-mono px-1.5 py-0.5 rounded"
            :class="idx === visibleEvents.length - 1 ? 'droid-pop' : ''"
            :style="{ color: event.droid_color, backgroundColor: event.droid_color + '22' }"
          >
            {{ event.droid_emoji }} {{ event.droid_name }}
          </span>
          <span v-else class="text-xs text-gray-500 font-mono">{{ event.hook_event_type }}</span>
        </div>

        <!-- Event details -->
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <span class="text-xs font-semibold text-gray-300">{{ EVENT_LABELS[event.hook_event_type] ?? event.hook_event_type }}</span>
            <span v-if="event.tool_name" class="text-xs text-gray-400 font-mono bg-gray-800 px-1.5 rounded">{{ event.tool_name }}</span>
            <span v-if="event.ticket_id" class="text-xs text-blue-400 font-mono">{{ event.ticket_id }}</span>
            <span v-if="event.skill_name" class="text-xs text-purple-400 font-mono">/{{ event.skill_name }}</span>
          </div>
          <div v-if="promptPreview(event)" class="text-xs text-gray-500 mt-0.5 truncate">
            {{ promptPreview(event) }}
          </div>
        </div>

        <!-- Timestamp -->
        <div class="flex-shrink-0 text-xs text-gray-500 font-mono">
          {{ formatTime(event.timestamp) }}
        </div>
      </div>
    </TransitionGroup>
  </div>
</template>

<script setup lang="ts">
import { ref, nextTick } from 'vue'
import type { ObserverEvent } from '../types/events'

defineProps<{ visibleEvents: ObserverEvent[] }>()

const containerEl = ref<HTMLElement | null>(null)

const EVENT_LABELS: Record<string, string> = {
  SubagentStart:    'Droid invoked',
  SubagentStop:     'Droid done',
  UserPromptSubmit: 'User prompt',
  PreToolUse:       'Tool start',
  PostToolUse:      'Tool done',
}

function promptPreview(event: ObserverEvent): string {
  return (event.payload?.prompt_preview as string) ?? ''
}

function formatTime(ts: number) {
  const d = new Date(ts)
  return d.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
}

async function scrollToBottom() {
  await nextTick()
  if (containerEl.value) {
    containerEl.value.scrollTop = containerEl.value.scrollHeight
  }
}

defineExpose({ scrollToBottom })
</script>

<style scoped>
.event-current {
  background-color: rgba(99, 102, 241, 0.08);
}
</style>
