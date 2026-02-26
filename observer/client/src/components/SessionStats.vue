<template>
  <div class="flex flex-col gap-5 px-4 py-4 overflow-y-auto h-full">

    <!-- KPI strip -->
    <div class="grid grid-cols-2 gap-2">
      <div class="bg-gray-800/60 rounded-lg p-3 text-center">
        <div class="text-lg font-bold text-white font-mono">{{ formatMs(stats.duration_ms) }}</div>
        <div class="text-xs text-gray-500 mt-0.5">Duration</div>
      </div>
      <div class="bg-gray-800/60 rounded-lg p-3 text-center">
        <div class="text-lg font-bold text-white">{{ stats.prompt_count }}</div>
        <div class="text-xs text-gray-500 mt-0.5">Prompts</div>
      </div>
      <div class="bg-gray-800/60 rounded-lg p-3 text-center">
        <div class="text-lg font-bold text-white">{{ stats.droid_rows.length }}</div>
        <div class="text-xs text-gray-500 mt-0.5">Droids</div>
      </div>
      <div class="bg-gray-800/60 rounded-lg p-3 text-center">
        <div class="text-lg font-bold text-white">{{ stats.total_tool_calls }}</div>
        <div class="text-xs text-gray-500 mt-0.5">Tool calls</div>
      </div>
    </div>

    <!-- Droid activity -->
    <div v-if="stats.droid_rows.length">
      <div class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Droid Activity</div>
      <div v-for="droid in stats.droid_rows" :key="droid.name" class="mb-3">
        <div class="flex items-center justify-between mb-1.5">
          <span class="text-xs font-mono font-semibold" :style="{ color: droid.color }">
            {{ droid.emoji }} {{ droid.name }}
          </span>
          <span class="text-xs text-gray-500 font-mono">
            {{ droid.count }}× · {{ formatMs(droid.total_ms) }}
          </span>
        </div>
        <div class="h-1.5 bg-gray-800 rounded-full overflow-hidden">
          <div
            class="h-full rounded-full transition-all"
            :style="{
              width: Math.min(100, droid.total_ms / stats.duration_ms * 100) + '%',
              backgroundColor: droid.color
            }"
          />
        </div>
      </div>
    </div>

    <!-- Parallelism -->
    <div v-if="stats.parallelism > 0" class="bg-gray-800/40 rounded-lg p-3">
      <div class="flex items-center justify-between mb-1">
        <span class="text-xs text-gray-400">Parallelism</span>
        <span
          class="text-sm font-bold font-mono"
          :class="stats.parallelism > 1.3 ? 'text-green-400' : stats.parallelism > 0.7 ? 'text-yellow-400' : 'text-gray-400'"
        >
          {{ stats.parallelism.toFixed(2) }}×
        </span>
      </div>
      <div class="text-xs text-gray-600">droid active time / wall time</div>
    </div>

    <!-- Tool call breakdown -->
    <div v-if="stats.total_tool_calls">
      <div class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Tool Calls</div>

      <div v-if="stats.task_count" class="flex items-center justify-between py-1 border-b border-gray-800/60">
        <span class="text-xs text-amber-400">⬡ Task</span>
        <span class="text-xs font-mono text-gray-400">{{ stats.task_count }}</span>
      </div>
      <div v-if="stats.skill_count" class="flex items-center justify-between py-1 border-b border-gray-800/60">
        <span class="text-xs text-purple-400">⚡ Skill</span>
        <span class="text-xs font-mono text-gray-400">{{ stats.skill_count }}</span>
      </div>
      <div v-if="stats.bash_count" class="flex items-center justify-between py-1 border-b border-gray-800/60">
        <span class="text-xs text-green-400">$ Bash</span>
        <span class="text-xs font-mono text-gray-400">{{ stats.bash_count }}</span>
      </div>
      <div v-if="stats.web_count" class="flex items-center justify-between py-1 border-b border-gray-800/60">
        <span class="text-xs text-blue-400">🌐 Web</span>
        <span class="text-xs font-mono text-gray-400">{{ stats.web_count }}</span>
      </div>
      <div v-for="op in stats.file_ops" :key="op.name" class="flex items-center justify-between py-1 border-b border-gray-800/60">
        <span class="text-xs text-gray-400">{{ fileOpIcon(op.name) }} {{ op.name }}</span>
        <span class="text-xs font-mono text-gray-400">{{ op.count }}</span>
      </div>

      <div
        v-for="svc in stats.mcp_services"
        :key="svc.name"
        class="flex items-center justify-between py-1 border-b border-gray-800/60"
      >
        <span class="text-xs text-cyan-400 font-mono truncate max-w-36">🔌 {{ svc.name }}</span>
        <span class="text-xs font-mono text-gray-400">{{ svc.count }}</span>
      </div>
    </div>


    <!-- Not tracked -->
    <div class="border-t border-gray-800 pt-4">
      <div class="text-xs font-semibold text-gray-700 uppercase tracking-wider mb-2">Not tracked</div>
      <div class="space-y-1 text-xs text-gray-700">
        <div>↳ PostToolUse — tool durations & outcomes</div>
        <div>↳ Subagent-internal tool calls</div>
        <div>↳ Token usage per turn</div>
        <div>↳ Model response / thinking time</div>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { ObserverEvent } from '../types/events'
import { useSessionAnalysis } from '../composables/useSessionAnalysis'

const props = defineProps<{ events: ObserverEvent[] }>()

const eventsRef = computed(() => props.events)
const { stats, formatMs } = useSessionAnalysis(eventsRef)

function fileOpIcon(name: string): string {
  const icons: Record<string, string> = { Read: '📄', Write: '💾', Edit: '✏️', Glob: '🔎', Grep: '🔍', NotebookEdit: '📓' }
  return icons[name] ?? '▸'
}
</script>
