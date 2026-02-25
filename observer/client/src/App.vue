<template>
  <div class="h-screen flex flex-col bg-gray-950 font-sans overflow-hidden">
    <!-- Persistent header -->
    <header class="flex items-center gap-3 px-4 border-b border-gray-800 bg-gray-900 flex-shrink-0">
      <button
        v-if="selectedSessionId"
        class="flex items-center gap-1.5 text-xs text-gray-400 hover:text-white py-3 pr-3 border-r border-gray-800 mr-1 transition-colors"
        @click="selectedSessionId = null"
      >
        ← Sessions
      </button>
      <MissionHeader :connected="connected" />
    </header>

    <!-- Page transition between grid and replay -->
    <Transition name="page-slide" mode="out-in">
      <SessionGrid
        v-if="!selectedSessionId"
        @select="selectedSessionId = $event"
      />
      <SessionReplay
        v-else
        :key="selectedSessionId"
        :session-id="selectedSessionId"
      />
    </Transition>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import MissionHeader from './components/MissionHeader.vue'
import SessionGrid from './components/SessionGrid.vue'
import SessionReplay from './components/SessionReplay.vue'
import { useWebSocket } from './composables/useWebSocket'
import { useEventsStore } from './stores/events'

const { connected } = useWebSocket()
const store = useEventsStore()

const selectedSessionId = ref<string | null>(null)

onMounted(async () => {
  await store.fetchEvents()
  await store.fetchFilterOptions()
})
</script>
