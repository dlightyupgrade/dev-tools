<template>
  <div class="flex flex-col h-full bg-gray-900 border-l border-gray-800">
    <!-- Sticky header -->
    <div class="flex-shrink-0 px-4 py-3 border-b border-gray-800 bg-gray-900">
      <div class="text-xs font-semibold text-gray-400 uppercase tracking-wider">All Events</div>
      <div class="text-xs text-gray-600 font-mono mt-0.5">{{ events.length }} total</div>
    </div>

    <!-- Scrollable event list -->
    <div ref="listEl" class="flex-1 overflow-y-auto">
      <div
        v-for="(event, idx) in events"
        :key="event.id"
        :ref="(el) => { rowRefs[idx] = el as HTMLElement | null }"
        class="flex items-start gap-2 px-3 py-2 border-b border-gray-800/60 transition-colors duration-150 cursor-pointer text-xs"
        :class="idx === currentIndex ? 'bg-gray-800 border-l-2' : 'hover:bg-gray-800/40'"
        :style="idx === currentIndex ? { borderLeftColor: event.droid_color || '#6366f1' } : {}"
        @click="$emit('seek', idx)"
      >
        <!-- Index -->
        <span class="text-gray-600 font-mono flex-shrink-0 w-6 text-right">{{ idx + 1 }}</span>

        <!-- Droid or event type -->
        <span
          v-if="event.droid_name && event.droid_name !== '???'"
          class="flex-shrink-0 font-mono text-xs px-1 rounded"
          :style="{ color: event.droid_color, backgroundColor: event.droid_color + '22' }"
        >
          {{ event.droid_emoji }} {{ event.droid_name }}
        </span>
        <span v-else class="flex-shrink-0 text-gray-500 font-mono">{{ event.hook_event_type }}</span>

        <!-- Details -->
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-1 flex-wrap">
            <span v-if="event.tool_name" class="text-gray-400 font-mono bg-gray-800 px-1 rounded">{{ event.tool_name }}</span>
            <span v-if="event.skill_name" class="text-purple-400 font-mono">/{{ event.skill_name }}</span>
            <span v-if="event.ticket_id" class="text-blue-400 font-mono">{{ event.ticket_id }}</span>
          </div>
        </div>

        <!-- Time -->
        <span class="flex-shrink-0 text-gray-600 font-mono">{{ formatTime(event.timestamp) }}</span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, nextTick } from 'vue'
import type { ObserverEvent } from '../types/events'

const props = defineProps<{
  events: ObserverEvent[]
  currentIndex: number
}>()
defineEmits<{ seek: [index: number] }>()

const listEl = ref<HTMLElement | null>(null)
const rowRefs = ref<(HTMLElement | null)[]>([])

watch(() => props.currentIndex, async (idx) => {
  await nextTick()
  rowRefs.value[idx]?.scrollIntoView({ block: 'nearest', behavior: 'smooth' })
})

function formatTime(ts: number) {
  const d = new Date(ts)
  return d.toLocaleTimeString('en-US', { hour12: false, hour: '2-digit', minute: '2-digit', second: '2-digit' })
}
</script>
