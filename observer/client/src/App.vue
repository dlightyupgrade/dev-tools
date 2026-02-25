<template>
  <div class="h-screen flex flex-col bg-gray-950 font-sans overflow-hidden">
    <!-- Persistent header -->
    <header class="flex items-center gap-3 px-4 border-b border-gray-800 bg-gray-900 flex-shrink-0">
      <!-- Back button (session detail only) -->
      <button
        v-if="selectedSessionId"
        class="flex items-center gap-1.5 text-xs text-gray-400 hover:text-white py-3 pr-3 border-r border-gray-800 mr-1 transition-colors flex-shrink-0"
        @click="selectedSessionId = null"
      >
        ← Sessions
      </button>

      <!-- Nav tabs (only when not in session detail) -->
      <div v-if="!selectedSessionId" class="flex items-center gap-1 py-2 flex-shrink-0">
        <button
          class="nav-tab"
          :class="view === 'sessions' ? 'nav-tab-active' : ''"
          @click="view = 'sessions'"
        >
          Sessions
        </button>
        <button
          class="nav-tab"
          :class="view === 'insights' ? 'nav-tab-active' : ''"
          @click="view = 'insights'"
        >
          Insights
        </button>
      </div>

      <MissionHeader :connected="connected" />

      <!-- Launch button -->
      <button
        class="flex-shrink-0 ml-2 flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white transition-colors"
        @click="showLaunch = true"
      >
        ⚡ New
      </button>
    </header>

    <!-- Launch modal -->
    <LaunchModal v-if="showLaunch" @close="showLaunch = false" />

    <!-- Page transition -->
    <Transition name="page-slide" mode="out-in">
      <SessionGrid
        v-if="!selectedSessionId && view === 'sessions'"
        key="grid"
        @select="selectedSessionId = $event"
      />
      <InsightsPanel
        v-else-if="!selectedSessionId && view === 'insights'"
        key="insights"
        @select="goToSession"
      />
      <SessionReplay
        v-else
        :key="selectedSessionId!"
        :session-id="selectedSessionId!"
      />
    </Transition>
  </div>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'
import MissionHeader from './components/MissionHeader.vue'
import SessionGrid from './components/SessionGrid.vue'
import SessionReplay from './components/SessionReplay.vue'
import InsightsPanel from './components/InsightsPanel.vue'
import LaunchModal from './components/LaunchModal.vue'
import { useWebSocket } from './composables/useWebSocket'
import { useEventsStore } from './stores/events'

const { connected } = useWebSocket()
const store = useEventsStore()

const view = ref<'sessions' | 'insights'>('insights')
const selectedSessionId = ref<string | null>(null)
const showLaunch = ref(false)

function goToSession(id: string) {
  view.value = 'sessions'
  selectedSessionId.value = id
}

onMounted(async () => {
  await store.fetchEvents()
  await store.fetchFilterOptions()
})
</script>

<style scoped>
.nav-tab {
  @apply text-xs px-3 py-1.5 rounded font-medium text-gray-500 hover:text-gray-300 transition-colors;
}
.nav-tab-active {
  @apply bg-gray-800 text-white;
}
</style>
