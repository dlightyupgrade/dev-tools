<template>
  <div
    class="px-6 py-3 flex items-center gap-4 border-b border-gray-800"
    :class="connected ? 'bg-gray-900' : 'bg-gray-900/50'"
  >
    <!-- Live indicator -->
    <div class="flex items-center gap-2 flex-shrink-0">
      <span
        class="w-2 h-2 rounded-full"
        :class="connected ? 'bg-green-500 animate-pulse' : 'bg-red-500'"
      />
      <span class="text-xs text-gray-500">{{ connected ? 'LIVE' : 'OFFLINE' }}</span>
    </div>

    <!-- Mission info -->
    <div class="flex-1 min-w-0">
      <template v-if="activeMission">
        <span class="text-sm font-semibold text-purple-400 font-mono">
          ⚡ /{{ activeMission.skill }}
        </span>
        <span v-if="activeMission.ticket" class="ml-2 text-sm text-blue-400 font-mono">
          {{ activeMission.ticket }}
        </span>
      </template>
      <span v-else class="text-sm text-gray-600">No active mission</span>
    </div>

    <!-- Stats strip -->
    <div class="flex items-center gap-4 flex-shrink-0 text-xs text-gray-500">
      <span>{{ totalEvents }} events</span>
      <span v-if="activeSessions > 0">{{ activeSessions }} session{{ activeSessions > 1 ? 's' : '' }}</span>
      <span v-if="elapsed" class="font-mono text-gray-400">{{ elapsed }}</span>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import { storeToRefs } from 'pinia'
import { useEventsStore } from '../stores/events'

defineProps<{ connected: boolean }>()

const store = useEventsStore()
const { activeMission, filteredEvents, sessionIds, oldestTimestamp } = storeToRefs(store)

const totalEvents = computed(() => filteredEvents.value.length)
const activeSessions = computed(() => sessionIds.value.length)

const now = ref(Date.now())
let timer: ReturnType<typeof setInterval>

onMounted(() => { timer = setInterval(() => { now.value = Date.now() }, 1000) })
onUnmounted(() => clearInterval(timer))

const elapsed = computed(() => {
  if (!oldestTimestamp.value) return ''
  const ms = now.value - oldestTimestamp.value
  const s = Math.floor(ms / 1000)
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`
})
</script>
