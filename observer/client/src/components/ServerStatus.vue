<template>
  <div class="relative" ref="rootEl">
    <!-- Trigger -->
    <button
      class="flex items-center gap-1.5 text-xs px-2.5 py-1.5 rounded-lg border transition-colors"
      :class="connected
        ? 'border-gray-700 text-gray-400 hover:text-white hover:border-gray-600'
        : 'border-red-900 text-red-500'"
      @click="toggle"
    >
      <span
        class="w-1.5 h-1.5 rounded-full flex-shrink-0"
        :class="connected ? 'bg-green-500 animate-pulse' : 'bg-red-500'"
      />
      <span class="font-mono">{{ connected ? 'SERVER' : 'OFFLINE' }}</span>
      <span v-if="statusData" class="text-gray-600">{{ statusData.uptime }}</span>
    </button>

    <!-- Popover -->
    <Transition name="pop">
      <div
        v-if="open"
        class="absolute right-0 top-full mt-2 w-64 bg-gray-900 border border-gray-700 rounded-xl shadow-2xl z-40 overflow-hidden"
      >
        <!-- Status rows -->
        <div class="px-4 py-3 space-y-2 border-b border-gray-800">
          <div class="flex items-center justify-between">
            <span class="text-xs text-gray-500">Status</span>
            <span class="text-xs font-semibold" :class="connected ? 'text-green-400' : 'text-red-400'">
              {{ connected ? 'Running' : 'Offline' }}
            </span>
          </div>
          <template v-if="statusData">
            <div class="flex items-center justify-between">
              <span class="text-xs text-gray-500">Uptime</span>
              <span class="text-xs font-mono text-gray-300">{{ statusData.uptime }}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-gray-500">WS clients</span>
              <span class="text-xs font-mono text-gray-300">{{ statusData.clients }}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-gray-500">Events stored</span>
              <span class="text-xs font-mono text-gray-300">{{ statusData.event_count }}</span>
            </div>
            <div class="flex items-center justify-between">
              <span class="text-xs text-gray-500">Port</span>
              <span class="text-xs font-mono text-gray-300">{{ statusData.port }}</span>
            </div>
          </template>
        </div>

        <!-- Actions -->
        <div class="px-4 py-3 space-y-2">
          <button
            class="w-full flex items-center justify-center gap-2 text-xs text-red-400 hover:text-red-300 py-1.5 px-3 rounded-lg border border-red-900 hover:border-red-700 hover:bg-red-950/40 transition-colors"
            :disabled="stopping || !connected"
            @click="stopServer"
          >
            <span>{{ stopping ? 'Stopping…' : '⏹ Stop Server' }}</span>
          </button>
          <p class="text-xs text-gray-700 text-center">
            Restart: <span class="font-mono">claude-observer start</span>
          </p>
        </div>
      </div>
    </Transition>
  </div>
</template>

<script setup lang="ts">
import { ref, watch, onMounted, onUnmounted } from 'vue'

const props = defineProps<{ connected: boolean }>()

const open = ref(false)
const stopping = ref(false)
const rootEl = ref<HTMLElement | null>(null)
const statusData = ref<{ uptime: string; clients: number; event_count: number; port: number } | null>(null)

async function fetchStatus() {
  try {
    const res = await fetch('http://localhost:4001/status')
    statusData.value = await res.json()
  } catch {
    statusData.value = null
  }
}

function toggle() {
  open.value = !open.value
  if (open.value) fetchStatus()
}

async function stopServer() {
  stopping.value = true
  try {
    await fetch('http://localhost:4001/shutdown', { method: 'POST' })
  } catch { /* expected — server closes connection */ }
  stopping.value = false
  open.value = false
}

// Close on outside click
function onOutside(e: MouseEvent) {
  if (open.value && rootEl.value && !rootEl.value.contains(e.target as Node)) {
    open.value = false
  }
}
onMounted(() => document.addEventListener('mousedown', onOutside))
onUnmounted(() => document.removeEventListener('mousedown', onOutside))

// Refresh status when popover is open
let pollTimer: ReturnType<typeof setInterval> | null = null
watch(open, (val) => {
  if (val) {
    pollTimer = setInterval(fetchStatus, 3000)
  } else {
    if (pollTimer) { clearInterval(pollTimer); pollTimer = null }
  }
})
</script>

<style scoped>
.pop-enter-active, .pop-leave-active { transition: all 0.15s ease-out; }
.pop-enter-from, .pop-leave-to { transform: translateY(-6px); opacity: 0; }
</style>
