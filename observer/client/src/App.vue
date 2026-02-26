<template>
  <div class="h-screen flex flex-col bg-gray-950 font-sans overflow-hidden">
    <!-- Persistent header -->
    <header class="flex items-center gap-3 px-4 border-b border-gray-800 bg-gray-900 flex-shrink-0">
      <!-- Logo -->
      <div class="flex items-center gap-2 flex-shrink-0 pr-3 border-r border-gray-800">
        <div class="w-7 h-7 bg-gray-100 rounded-md flex items-center justify-center text-base text-gray-900 font-bold select-none">⌥</div>
      </div>

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
        <button class="nav-tab" :class="view === 'insights' ? 'nav-tab-active' : ''" @click="view = 'insights'">Insights</button>
        <button class="nav-tab" :class="view === 'sessions' ? 'nav-tab-active' : ''" @click="view = 'sessions'">Sessions</button>
        <button class="nav-tab" :class="view === 'help'     ? 'nav-tab-active' : ''" @click="view = 'help'">Help</button>
      </div>

      <!-- MissionHeader fills remaining space -->
      <MissionHeader :connected="connected" />

      <!-- Right-side controls -->
      <div class="flex items-center gap-2 ml-auto flex-shrink-0">
        <ServerStatus :connected="connected" />

        <button
          class="text-xs px-2 py-1.5 rounded border border-gray-700 text-gray-400 hover:text-white hover:border-gray-600 transition-colors"
          :title="isDark ? 'Switch to light mode' : 'Switch to dark mode'"
          @click="toggleTheme"
        >{{ isDark ? '☀️' : '🌙' }}</button>

        <button
          class="flex items-center gap-1.5 text-xs font-semibold px-3 py-1.5 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white transition-colors"
          @click="showLaunch = true"
        >⚡ New <span class="opacity-60 font-normal text-xs ml-1">⌘K</span></button>
      </div>
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
        :connected="connected"
        @select="goToSession"
      />
      <HelpPanel
        v-else-if="!selectedSessionId && view === 'help'"
        key="help"
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
import { ref, onMounted, onUnmounted } from 'vue'
import MissionHeader from './components/MissionHeader.vue'
import SessionGrid from './components/SessionGrid.vue'
import SessionReplay from './components/SessionReplay.vue'
import InsightsPanel from './components/InsightsPanel.vue'
import LaunchModal from './components/LaunchModal.vue'
import ServerStatus from './components/ServerStatus.vue'
import HelpPanel from './components/HelpPanel.vue'
import { useWebSocket } from './composables/useWebSocket'
import { useEventsStore } from './stores/events'

const { connected } = useWebSocket()
const store = useEventsStore()

const view = ref<'sessions' | 'insights' | 'help'>('insights')
const selectedSessionId = ref<string | null>(null)
const showLaunch = ref(false)

const isDark = ref(localStorage.getItem('observer-theme') !== 'light')

function applyTheme() {
  if (isDark.value) {
    document.documentElement.classList.remove('theme-light')
  } else {
    document.documentElement.classList.add('theme-light')
  }
}

function toggleTheme() {
  isDark.value = !isDark.value
  localStorage.setItem('observer-theme', isDark.value ? 'dark' : 'light')
  applyTheme()
}

// Apply on mount
applyTheme()

function goToSession(id: string) {
  view.value = 'sessions'
  selectedSessionId.value = id
}

function onKeydown(e: KeyboardEvent) {
  if ((e.metaKey || e.ctrlKey) && e.key === 'k') {
    e.preventDefault()
    showLaunch.value = !showLaunch.value
  }
  if (e.key === 'Escape' && showLaunch.value) {
    showLaunch.value = false
  }
}

onMounted(async () => {
  await store.fetchEvents()
  await store.fetchFilterOptions()
  document.addEventListener('keydown', onKeydown)
})

onUnmounted(() => document.removeEventListener('keydown', onKeydown))
</script>

<style scoped>
.nav-tab {
  @apply text-xs px-3 py-1.5 rounded font-medium text-gray-500 hover:text-gray-300 transition-colors;
}
.nav-tab-active {
  @apply bg-gray-800 text-white;
}
</style>
