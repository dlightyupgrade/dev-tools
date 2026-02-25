<template>
  <div class="flex flex-col h-full overflow-hidden">
    <!-- Toolbar -->
    <div class="flex items-center justify-between px-4 py-2 border-b border-gray-800 flex-shrink-0">
      <span class="text-sm text-gray-400">
        {{ filteredEvents.length }} events
        <span v-if="filters.droid || filters.session || filters.skill || filters.event_type" class="text-purple-400 ml-1">(filtered)</span>
      </span>
      <div class="flex items-center gap-3">
        <label class="flex items-center gap-1.5 text-xs text-gray-500 cursor-pointer select-none">
          <input type="checkbox" v-model="autoScroll" class="accent-purple-500" />
          Auto-scroll
        </label>
        <button
          @click="clearEvents"
          class="text-xs text-red-400 hover:text-red-300 transition-colors"
        >
          Clear
        </button>
      </div>
    </div>

    <!-- Event list -->
    <div
      ref="scrollContainer"
      class="flex-1 overflow-y-auto"
      @scroll="onScroll"
    >
      <div v-if="filteredEvents.length === 0" class="flex items-center justify-center h-full">
        <div class="text-center text-gray-600">
          <div class="text-4xl mb-3">🤖</div>
          <p class="text-sm">Waiting for droid activity...</p>
          <p class="text-xs mt-1">Start a Claude session to see events</p>
        </div>
      </div>

      <EventRow
        v-for="event in filteredEvents"
        :key="event.id"
        :event="event"
        :duration-ms="getDuration(event)"
      />

      <div ref="scrollAnchor" />
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, nextTick } from 'vue'
import { storeToRefs } from 'pinia'
import EventRow from './EventRow.vue'
import { useEventsStore } from '../stores/events'
import type { ObserverEvent } from '../types/events'

const store = useEventsStore()
const { filteredEvents, filters } = storeToRefs(store)

const scrollContainer = ref<HTMLElement | null>(null)
const scrollAnchor = ref<HTMLElement | null>(null)
const autoScroll = ref(true)

// Map sessionId+droidName → start timestamp for duration calculation
const startTimes: Record<string, number> = {}
const durations: Record<string, number> = {}

function getDuration(event: ObserverEvent): number {
  if (event.hook_event_type === 'SubagentStart') {
    startTimes[event.id] = event.timestamp
  }
  if (event.hook_event_type === 'SubagentStop') {
    // Find matching start by droid_name + session proximity
    return durations[event.session_id + event.droid_name] ?? 0
  }
  return 0
}

function onScroll() {
  if (!scrollContainer.value) return
  const { scrollTop, scrollHeight, clientHeight } = scrollContainer.value
  autoScroll.value = scrollHeight - scrollTop - clientHeight < 50
}

function scrollToBottom() {
  nextTick(() => {
    scrollAnchor.value?.scrollIntoView({ behavior: 'smooth' })
  })
}

watch(
  () => filteredEvents.value.length,
  () => { if (autoScroll.value) scrollToBottom() }
)

function clearEvents() {
  store.clearEvents()
}
</script>
