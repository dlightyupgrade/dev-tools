<template>
  <div class="p-4 space-y-4">
    <h2 class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Droids</h2>

    <div v-if="droidStats.length === 0" class="text-xs text-gray-600">
      No droids invoked yet
    </div>

    <div v-for="droid in droidStats" :key="droid.name" class="space-y-1">
      <div class="flex items-center justify-between">
        <div class="flex items-center gap-1.5">
          <span class="text-sm">{{ droid.emoji }}</span>
          <span
            class="text-xs font-semibold font-mono"
            :style="{ color: droid.color }"
          >{{ droid.name }}</span>
        </div>
        <span class="text-xs text-gray-400 font-mono">×{{ droid.count }}</span>
      </div>
      <div v-if="droid.totalMs > 0" class="text-xs text-gray-600 font-mono pl-5">
        {{ formatMs(droid.totalMs) }} total
      </div>
      <!-- Mini bar -->
      <div class="h-0.5 rounded bg-gray-800 overflow-hidden">
        <div
          class="h-full rounded transition-all"
          :style="{ width: barWidth(droid.count) + '%', backgroundColor: droid.color }"
        />
      </div>
    </div>

    <div class="pt-2 border-t border-gray-800 space-y-1">
      <div class="flex justify-between text-xs">
        <span class="text-gray-500">Total events</span>
        <span class="text-gray-300 font-mono">{{ totalEvents }}</span>
      </div>
      <div class="flex justify-between text-xs">
        <span class="text-gray-500">Droids active</span>
        <span class="text-gray-300 font-mono">{{ droidStats.length }}</span>
      </div>
      <div v-if="slowestDroid" class="flex justify-between text-xs">
        <span class="text-gray-500">Slowest</span>
        <span class="text-amber-400 font-mono">{{ slowestDroid.name }} ({{ formatMs(slowestDroid.totalMs) }})</span>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useEventsStore } from '../stores/events'

const store = useEventsStore()
const { droidStats, filteredEvents } = storeToRefs(store)

const totalEvents = computed(() => filteredEvents.value.length)

const maxCount = computed(() => Math.max(...droidStats.value.map(d => d.count), 1))

const slowestDroid = computed(() => {
  const withTime = droidStats.value.filter(d => d.totalMs > 0)
  return withTime.sort((a, b) => b.totalMs - a.totalMs)[0] ?? null
})

function barWidth(count: number): number {
  return Math.round((count / maxCount.value) * 100)
}

function formatMs(ms: number): string {
  if (ms < 1000) return `${ms}ms`
  if (ms < 60_000) return `${(ms / 1000).toFixed(1)}s`
  const m = Math.floor(ms / 60_000)
  const s = Math.floor((ms % 60_000) / 1000)
  return `${m}m ${s}s`
}
</script>
