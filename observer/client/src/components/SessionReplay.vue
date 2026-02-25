<template>
  <div class="flex flex-col flex-1 overflow-hidden">
    <!-- Session info header -->
    <div class="flex-shrink-0 px-6 py-3 bg-gray-900 border-b border-gray-800 flex items-center gap-4">
      <div class="flex items-center gap-3 flex-1 min-w-0">
        <span
          class="w-2 h-2 rounded-full flex-shrink-0"
          :class="summary?.is_active ? 'bg-green-500 animate-pulse' : 'bg-gray-600'"
        />
        <span class="text-sm text-gray-400 font-mono truncate">{{ sessionId }}</span>
        <span v-if="summary?.skill_name" class="text-sm text-purple-400 font-mono flex-shrink-0">
          ⚡ /{{ summary.skill_name }}
        </span>
        <span v-if="summary?.ticket_id" class="text-sm text-blue-400 font-mono flex-shrink-0">
          {{ summary.ticket_id }}
        </span>
      </div>
      <span class="text-xs text-gray-500 flex-shrink-0">{{ allEvents.length }} events · {{ formatMs(durationMs) }}</span>
    </div>

    <!-- Main layout: tree + stats -->
    <div class="flex flex-1 overflow-hidden">

      <!-- Left: causal tree -->
      <SessionTree :events="allEvents" />

      <!-- Right: stats panel -->
      <div class="w-64 flex-shrink-0 border-l border-gray-800 overflow-y-auto bg-gray-950">
        <div class="px-4 py-2 border-b border-gray-800 bg-gray-900">
          <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Stats</span>
        </div>
        <SessionStats :events="allEvents" />
      </div>

    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useEventsStore } from '../stores/events'
import { useSessionAnalysis } from '../composables/useSessionAnalysis'
import SessionTree from './SessionTree.vue'
import SessionStats from './SessionStats.vue'
import type { ObserverEvent } from '../types/events'

const props = defineProps<{ sessionId: string }>()

const store = useEventsStore()
const { sessionSummaries } = storeToRefs(store)

const allEvents = computed<ObserverEvent[]>(() => store.getSessionEvents(props.sessionId))
const summary = computed(() => sessionSummaries.value.find(s => s.session_id === props.sessionId))

const eventsRef = allEvents
const { durationMs, formatMs } = useSessionAnalysis(eventsRef)
</script>
