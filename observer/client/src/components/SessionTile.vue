<template>
  <div
    class="session-tile relative rounded-lg border border-gray-800 bg-gray-900 px-4 py-3 cursor-pointer select-none transition-all duration-150"
    :class="{ 'tile-active': summary.is_active }"
    :style="tileStyle"
    @click="$emit('select', summary.session_id)"
  >
    <div v-if="summary.is_active" class="pulse-ring absolute inset-0 rounded-lg pointer-events-none" />

    <!-- Row 1: status · id · skill · ticket · elapsed -->
    <div class="flex items-center gap-2 mb-1.5 min-w-0">
      <span class="w-1.5 h-1.5 rounded-full flex-shrink-0"
        :class="summary.is_active ? 'bg-green-500 animate-pulse' : 'bg-gray-600'" />
      <span class="text-xs font-semibold flex-shrink-0"
        :class="summary.is_active ? 'text-green-500' : 'text-gray-500'">
        {{ summary.is_active ? 'ACTIVE' : endLabel }}
      </span>
      <span class="text-xs text-gray-600 font-mono flex-shrink-0" :title="summary.session_id">{{ shortId }}</span>
      <span v-if="summary.skill_name" class="text-xs text-purple-500 font-mono truncate">⚡ /{{ summary.skill_name }}</span>
      <span v-if="summary.ticket_id" class="text-xs text-blue-500 font-mono flex-shrink-0">{{ summary.ticket_id }}</span>
      <span class="flex-1" />
      <span class="text-xs text-gray-500 font-mono flex-shrink-0">{{ elapsed }}</span>
    </div>

    <!-- Row 2: first prompt -->
    <div v-if="summary.first_prompt" class="text-xs text-gray-400 truncate mb-2 leading-snug">
      {{ summary.first_prompt }}
    </div>

    <!-- Row 3: droid badges · event count · actions -->
    <div class="flex items-center gap-2 flex-wrap">
      <span
        v-for="droid in summary.droids.slice(0, 4)"
        :key="droid.name"
        class="inline-flex items-center gap-1 text-xs font-mono px-1.5 py-0.5 rounded"
        :style="{ backgroundColor: droid.color + '18', color: droid.color, border: `1px solid ${droid.color}30` }"
      >
        {{ droid.emoji }} {{ droid.name }}<span v-if="droid.count > 1" class="opacity-60">×{{ droid.count }}</span>
      </span>
      <span v-if="summary.droids.length > 4" class="text-xs text-gray-600">+{{ summary.droids.length - 4 }}</span>
      <span class="flex-1" />
      <span class="text-xs text-gray-500">{{ summary.event_count }} events</span>
      <button
        v-if="summary.is_active"
        class="text-xs text-green-400 hover:text-green-300 font-mono px-1.5 py-0.5 rounded border border-green-900 hover:border-green-700 transition-colors"
        title="Jump to iTerm2 tab"
        @click.stop="focus"
      >⤴ Tab</button>
      <button
        v-if="!summary.is_active"
        class="text-xs text-indigo-400 hover:text-indigo-300 font-mono px-1.5 py-0.5 rounded border border-indigo-800 hover:border-indigo-600 transition-colors"
        @click.stop="resume"
      >↩</button>
      <button
        class="text-xs text-gray-500 hover:text-red-400 w-5 text-center rounded border border-transparent hover:border-red-800 transition-colors"
        title="Forget session"
        @click="forget"
      >✕</button>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import type { SessionSummary } from '../types/events'
import { useEventsStore } from '../stores/events'

const props = defineProps<{ summary: SessionSummary }>()
defineEmits<{ select: [id: string] }>()

const store = useEventsStore()

const shortId = computed(() => props.summary.session_id.slice(0, 8))

const END_REASON_LABELS: Record<string, string> = {
  prompt_input_exit: 'EXITED',
  clear: 'CLEARED',
  logout: 'LOGOUT',
  other: 'ENDED',
  '': 'DONE',
}
const endLabel = computed(() => END_REASON_LABELS[props.summary.end_reason] ?? 'DONE')

const now = ref(Date.now())
let timer: ReturnType<typeof setInterval>
onMounted(() => { timer = setInterval(() => { now.value = Date.now() }, 1000) })
onUnmounted(() => clearInterval(timer))

const elapsed = computed(() => {
  const ms = now.value - props.summary.start_ts
  const s = Math.floor(ms / 1000)
  const h = Math.floor(s / 3600)
  const m = Math.floor((s % 3600) / 60)
  const sec = s % 60
  return `${String(h).padStart(2, '0')}:${String(m).padStart(2, '0')}:${String(sec).padStart(2, '0')}`
})

const tileStyle = computed(() => ({ '--glow-color': props.summary.dominant_color }))

async function focus() {
  await fetch(`http://localhost:4001/focus-session?session_id=${props.summary.session_id}`)
}

async function resume() {
  await fetch(`http://localhost:4001/launch?session_id=${props.summary.session_id}`)
}

async function forget(e: MouseEvent) {
  e.stopPropagation()
  await store.deleteSession(props.summary.session_id)
}
</script>

<style scoped>
.session-tile { transition: transform 0.15s ease, box-shadow 0.15s ease; }
.session-tile:hover { transform: translateY(-2px); }
.tile-active { border-color: rgba(34,197,94,0.25) !important; }
.pulse-ring { animation: pulse-ring 2s cubic-bezier(0.4,0,0.6,1) infinite; }
</style>
