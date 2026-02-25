<template>
  <div class="flex-1 overflow-y-auto p-6">
    <!-- Empty state -->
    <div v-if="!sessionSummaries.length" class="flex flex-col items-center justify-center h-full text-center">
      <div class="text-5xl mb-4">🤖</div>
      <div class="text-xl font-semibold text-gray-400 mb-2">No sessions yet</div>
      <div class="text-sm text-gray-600">Waiting for Claude activity...</div>
    </div>

    <!-- Grid of tiles -->
    <template v-else>
      <div class="mb-4 flex items-center justify-between">
        <h2 class="text-sm font-semibold text-gray-400 uppercase tracking-wider">
          Sessions
          <span class="ml-2 text-gray-600 font-mono normal-case">{{ sessionSummaries.length }}</span>
        </h2>
        <div class="flex items-center gap-3">
          <span v-if="activeCount" class="text-xs text-green-400">{{ activeCount }} active</span>
          <button
            class="flex items-center gap-1 text-xs text-gray-500 hover:text-gray-300 font-mono transition-colors"
            :title="sortAsc ? 'Showing oldest first' : 'Showing newest first'"
            @click="sortAsc = !sortAsc"
          >
            {{ sortAsc ? '↑ oldest' : '↓ newest' }}
          </button>
        </div>
      </div>

      <TransitionGroup
        tag="div"
        name="tile-fade"
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"
      >
        <SessionTile
          v-for="(summary, index) in sorted"
          :key="summary.session_id"
          :summary="summary"
          :style="{ animationDelay: `${index * 40}ms` }"
          @select="$emit('select', $event)"
        />
      </TransitionGroup>
    </template>
  </div>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useEventsStore } from '../stores/events'
import SessionTile from './SessionTile.vue'

defineEmits<{ select: [id: string] }>()

const store = useEventsStore()
const { sessionSummaries } = storeToRefs(store)

const sortAsc = ref(false)

const activeCount = computed(() => sessionSummaries.value.filter(s => s.is_active).length)

const sorted = computed(() =>
  sortAsc.value ? [...sessionSummaries.value].reverse() : sessionSummaries.value
)
</script>
