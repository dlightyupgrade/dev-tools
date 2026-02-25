<template>
  <div
    class="session-tile relative rounded-lg border border-gray-800 bg-gray-900 p-4 cursor-pointer select-none transition-all duration-200"
    :class="{ 'tile-active': summary.is_active }"
    :style="tileStyle"
    @click="$emit('select', summary.session_id)"
  >
    <!-- Active pulse ring overlay -->
    <div v-if="summary.is_active" class="pulse-ring absolute inset-0 rounded-lg pointer-events-none" />

    <!-- Header row: status + session ID + elapsed -->
    <div class="flex items-center justify-between mb-2">
      <div class="flex items-center gap-2">
        <span
          class="w-2 h-2 rounded-full flex-shrink-0"
          :class="summary.is_active ? 'bg-green-500 animate-pulse' : 'bg-gray-600'"
        />
        <span class="text-xs font-semibold" :class="summary.is_active ? 'text-green-400' : 'text-gray-500'">
          {{ summary.is_active ? 'ACTIVE' : 'DONE' }}
        </span>
        <span class="text-xs text-gray-600 font-mono truncate max-w-24" :title="summary.session_id">
          {{ shortId }}
        </span>
      </div>
      <span class="text-xs text-gray-500 font-mono flex-shrink-0">{{ elapsed }}</span>
    </div>

    <!-- Skill + ticket row -->
    <div class="flex items-center gap-2 mb-1.5 min-h-[1.25rem]">
      <span v-if="summary.skill_name" class="text-xs text-purple-400 font-mono">
        ⚡ /{{ summary.skill_name }}
      </span>
      <span v-if="summary.ticket_id" class="text-xs text-blue-400 font-mono">
        {{ summary.ticket_id }}
      </span>
      <span v-if="!summary.skill_name && !summary.ticket_id" class="text-xs text-gray-600 italic">
        no mission
      </span>
    </div>

    <!-- First prompt preview -->
    <div class="mb-3 min-h-[1.25rem]">
      <span v-if="summary.first_prompt" class="text-xs text-gray-500 leading-snug line-clamp-2">
        {{ summary.first_prompt }}
      </span>
    </div>

    <!-- Droid badges row -->
    <div class="flex items-center gap-1.5 mb-3 flex-wrap min-h-[1.5rem]">
      <template v-if="summary.droids.length">
        <span
          v-for="droid in summary.droids.slice(0, 5)"
          :key="droid.name"
          class="flex items-center gap-1 text-xs font-mono px-1.5 py-0.5 rounded"
          :style="{ backgroundColor: droid.color + '22', color: droid.color, border: `1px solid ${droid.color}44` }"
        >
          {{ droid.emoji }} {{ droid.name }}
          <span v-if="droid.count > 1" class="text-gray-500">×{{ droid.count }}</span>
        </span>
        <span v-if="summary.droids.length > 5" class="text-xs text-gray-500">+{{ summary.droids.length - 5 }}</span>
      </template>
      <span v-else class="text-xs text-gray-600">no droids</span>
    </div>

    <!-- Footer: event count + droid count + resume -->
    <div class="flex items-center justify-between">
      <span class="text-xs text-gray-500">{{ summary.event_count }} events</span>
      <div class="flex items-center gap-2">
        <span v-if="summary.droids.length" class="text-xs text-gray-500">{{ summary.droids.length }} droid{{ summary.droids.length > 1 ? 's' : '' }}</span>
        <button
          v-if="!summary.is_active"
          class="text-xs text-indigo-400 hover:text-indigo-300 font-mono px-1.5 py-0.5 rounded border border-indigo-800 hover:border-indigo-600 transition-colors"
          @click.stop="resume"
        >
          ↩ Resume
        </button>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed, ref, onMounted, onUnmounted } from 'vue'
import type { SessionSummary } from '../types/events'

const props = defineProps<{ summary: SessionSummary }>()
defineEmits<{ select: [id: string] }>()

const shortId = computed(() => props.summary.session_id.slice(0, 8))

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

const tileStyle = computed(() => ({
  '--glow-color': props.summary.dominant_color,
}))

async function resume() {
  await fetch(`http://localhost:4001/launch?session_id=${props.summary.session_id}`)
}
</script>

<style scoped>
.session-tile {
  transition: transform 0.18s ease, box-shadow 0.18s ease;
}
.session-tile:hover {
  transform: translateY(-4px);
  box-shadow: 0 0 16px 2px var(--glow-color, #4B5563) 40;
  box-shadow: 0 4px 24px 0 color-mix(in srgb, var(--glow-color, #4B5563) 35%, transparent),
              0 0 0 1px color-mix(in srgb, var(--glow-color, #4B5563) 25%, transparent);
}
.tile-active {
  border-color: rgba(34, 197, 94, 0.3);
}
.pulse-ring {
  animation: pulse-ring 2s cubic-bezier(0.4, 0, 0.6, 1) infinite;
}
</style>
