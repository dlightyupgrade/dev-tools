<template>
  <div class="flex flex-col flex-1 overflow-hidden">

    <!-- Session header -->
    <div class="flex-shrink-0 px-4 py-2.5 bg-gray-900 border-b border-gray-800 flex items-center gap-3">
      <!-- Status + id + skill + ticket -->
      <span class="w-2 h-2 rounded-full flex-shrink-0"
        :class="summary?.is_active ? 'bg-green-500 animate-pulse' : 'bg-gray-600'" />
      <span class="text-xs text-gray-400 font-mono truncate max-w-56">{{ sessionId }}</span>
      <span v-if="summary?.skill_name" class="text-sm text-purple-400 font-mono flex-shrink-0">
        ⚡ /{{ summary.skill_name }}
      </span>
      <span v-if="summary?.ticket_id" class="text-sm text-blue-400 font-mono flex-shrink-0">
        {{ summary.ticket_id }}
      </span>
      <span class="text-xs text-gray-600 flex-shrink-0">{{ allEvents.length }} events · {{ formatMs(durationMs) }}</span>

      <div class="flex-1" />

      <!-- View toggle -->
      <div class="flex items-center gap-1 bg-gray-800 rounded-lg p-1">
        <button
          class="text-xs px-3 py-1 rounded-md font-medium transition-colors"
          :class="view === 'tree' ? 'bg-gray-700 text-white' : 'text-gray-500 hover:text-gray-300'"
          @click="view = 'tree'"
        >Tree</button>
        <button
          class="text-xs px-3 py-1 rounded-md font-medium transition-colors"
          :class="view === 'flame' ? 'bg-gray-700 text-white' : 'text-gray-500 hover:text-gray-300'"
          @click="view = 'flame'"
        >Timeline</button>
      </div>
      <button v-if="view === 'tree'"
        class="text-xs px-2.5 py-1 rounded border transition-colors flex-shrink-0"
        :class="showStats ? 'border-indigo-700 text-indigo-400' : 'border-gray-700 text-gray-500 hover:text-gray-300'"
        @click="showStats = !showStats"
      >Stats</button>

      <!-- Action buttons -->
      <button v-if="summary?.is_active"
        class="text-xs text-green-400 hover:text-green-300 font-mono px-2 py-1 rounded border border-green-900 hover:border-green-700 transition-colors flex-shrink-0"
        @click="focus">⤴ Tab</button>
      <button
        class="text-xs text-indigo-400 hover:text-indigo-300 font-mono px-2 py-1 rounded border border-indigo-800 hover:border-indigo-600 transition-colors flex-shrink-0"
        @click="resume">↩ Resume</button>
    </div>

    <!-- Tree view — full width, stats in collapsible panel -->
    <div v-if="view === 'tree'" class="flex flex-1 overflow-hidden">
      <SessionTree :events="allEvents" />
      <!-- Stats side panel -->
      <Transition name="slide-right">
        <div v-if="showStats" class="w-72 flex-shrink-0 border-l border-gray-800 overflow-y-auto bg-gray-950">
          <div class="px-4 py-2 border-b border-gray-800 bg-gray-900 flex items-center justify-between">
            <span class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Stats</span>
            <button class="text-gray-600 hover:text-gray-400 text-sm" @click="showStats = false">✕</button>
          </div>
          <SessionStats :events="allEvents" />
        </div>
      </Transition>
    </div>

    <!-- Flame chart view (full width, no sidebar) -->
    <SessionFlameChart v-else :events="allEvents" />

  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useEventsStore } from '../stores/events'
import { useSessionAnalysis } from '../composables/useSessionAnalysis'
import SessionTree from './SessionTree.vue'
import SessionStats from './SessionStats.vue'
import SessionFlameChart from './SessionFlameChart.vue'
import type { ObserverEvent } from '../types/events'

const props = defineProps<{ sessionId: string }>()

const store = useEventsStore()
const { sessionSummaries } = storeToRefs(store)

const allEvents = computed<ObserverEvent[]>(() => store.getSessionEvents(props.sessionId))
const summary   = computed(() => sessionSummaries.value.find(s => s.session_id === props.sessionId))

const eventsRef = allEvents
const { durationMs, formatMs } = useSessionAnalysis(eventsRef)

const view = ref<'tree' | 'flame'>('tree')
const showStats = ref(false)

async function focus()  { await fetch(`http://localhost:4001/focus-session?session_id=${props.sessionId}`) }
async function resume() { await fetch(`http://localhost:4001/launch?session_id=${props.sessionId}`) }
</script>
