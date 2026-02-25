<template>
  <div class="flex-1 overflow-y-auto p-6">
    <!-- Empty state -->
    <div v-if="!summaries.length" class="flex flex-col items-center justify-center h-full text-center">
      <div class="text-5xl mb-4">🤖</div>
      <div class="text-xl font-semibold text-gray-400 mb-2">No sessions yet</div>
      <div class="text-sm text-gray-600">Waiting for Claude activity...</div>
    </div>

    <!-- Grid of tiles -->
    <template v-else>
      <div class="mb-4 flex items-center justify-between">
        <h2 class="text-sm font-semibold text-gray-400 uppercase tracking-wider">
          Sessions
          <span class="ml-2 text-gray-600 font-mono normal-case">{{ summaries.length }}</span>
        </h2>
        <span v-if="activeCount" class="text-xs text-green-400">
          {{ activeCount }} active
        </span>
      </div>

      <TransitionGroup
        tag="div"
        name="tile-fade"
        class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4"
      >
        <SessionTile
          v-for="(summary, index) in summaries"
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
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import { useEventsStore } from '../stores/events'
import SessionTile from './SessionTile.vue'

defineEmits<{ select: [id: string] }>()

const store = useEventsStore()
const { sessionSummaries } = storeToRefs(store)
const summaries = sessionSummaries

const activeCount = computed(() => summaries.value.filter(s => s.is_active).length)
</script>
