<template>
  <div class="flex-shrink-0 bg-gray-900 border-t border-gray-800 px-4 py-3">
    <!-- Controls row -->
    <div class="flex items-center gap-3 mb-2">
      <!-- Reset -->
      <button
        class="text-xs text-gray-400 hover:text-white font-mono px-2 py-1 rounded bg-gray-800 hover:bg-gray-700 transition-colors"
        @click="$emit('reset')"
      >
        ◀◀ Reset
      </button>

      <!-- Play / Pause -->
      <button
        class="text-xs font-semibold px-3 py-1 rounded transition-colors"
        :class="playing ? 'bg-amber-500/20 text-amber-400 hover:bg-amber-500/30' : 'bg-green-500/20 text-green-400 hover:bg-green-500/30'"
        @click="$emit('toggle-play')"
      >
        {{ playing ? '⏸ Pause' : '▶ Play' }}
      </button>

      <!-- Speed selector -->
      <div class="flex items-center gap-1">
        <span class="text-xs text-gray-500">Speed:</span>
        <button
          v-for="opt in speedOptions"
          :key="opt.value"
          class="text-xs font-mono px-2 py-0.5 rounded transition-colors"
          :class="speed === opt.value ? 'bg-purple-500/30 text-purple-300' : 'text-gray-500 hover:text-gray-300'"
          @click="$emit('set-speed', opt.value)"
        >
          {{ opt.label }}
        </button>
      </div>

      <div class="flex-1" />

      <!-- Event counter -->
      <span class="text-xs text-gray-500 font-mono">
        {{ currentIndex + 1 }} / {{ total }} events
      </span>
    </div>

    <!-- Progress bar -->
    <div
      class="relative h-1.5 bg-gray-800 rounded-full cursor-pointer"
      @click="onScrub"
    >
      <div
        class="h-full rounded-full bg-purple-500 transition-all duration-150"
        :style="{ width: progressPct + '%' }"
      />
      <!-- Scrub handle -->
      <div
        class="absolute top-1/2 -translate-y-1/2 w-3 h-3 rounded-full bg-white shadow-md transition-all duration-150"
        :style="{ left: `calc(${progressPct}% - 6px)` }"
      />
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{
  playing: boolean
  speed: number
  currentIndex: number
  total: number
}>()

const emit = defineEmits<{
  'toggle-play': []
  'reset': []
  'set-speed': [speed: number]
  'seek': [index: number]
}>()

const speedOptions = [
  { label: '0.5×', value: 0.5 },
  { label: '1×',   value: 1   },
  { label: '2×',   value: 2   },
  { label: '5×',   value: 5   },
  { label: '∞',    value: Infinity },
]

const progressPct = computed(() => {
  if (props.total <= 1) return 0
  return Math.round((props.currentIndex / (props.total - 1)) * 100)
})

function onScrub(e: MouseEvent) {
  const bar = e.currentTarget as HTMLElement
  const rect = bar.getBoundingClientRect()
  const pct = Math.max(0, Math.min(1, (e.clientX - rect.left) / rect.width))
  const idx = Math.round(pct * (props.total - 1))
  emit('seek', idx)
}
</script>
