<template>
  <div class="flex-1 overflow-y-auto p-4 space-y-3">
    <!-- Empty state -->
    <div v-if="!tree.length" class="text-center py-12 text-gray-600 text-sm">
      No events yet for this session
    </div>

    <!-- Turn groups -->
    <div
      v-for="turn in displayTree"
      :key="turn.id"
      class="rounded-lg border border-gray-800 overflow-hidden"
    >
      <!-- Prompt header -->
      <div
        class="flex items-start gap-3 px-4 py-3 bg-gray-900 cursor-pointer hover:bg-gray-800/60 transition-colors"
        @click="toggle(turn.id)"
      >
        <span class="text-indigo-400 text-sm flex-shrink-0 font-mono mt-0.5">💬</span>
        <div class="flex-1 min-w-0">
          <div class="text-sm text-gray-200 font-medium leading-snug">
            <TextWithLinks v-if="turn.promptPreview" :text="turn.promptPreview" />
            <span v-else class="text-gray-600">(no preview)</span>
          </div>
        </div>
        <div class="flex items-center gap-3 flex-shrink-0">
          <span class="text-xs text-gray-600 font-mono">{{ formatRel(turn.relTimeSec) }}</span>
          <span class="text-xs text-gray-600">{{ turn.children.length > 0 ? (collapsed.has(turn.id) ? '▶' : '▼') : '' }}</span>
        </div>
      </div>

      <!-- Children (droids + orphan tools) -->
      <div v-if="!collapsed.has(turn.id) && turn.children.length">
        <template v-for="child in turn.children" :key="child.id">
          <!-- Droid node -->
          <div v-if="child.type === 'droid'" class="border-t border-gray-800/60">
            <!-- Droid header -->
            <div
              class="flex items-center gap-3 px-4 py-2.5 cursor-pointer hover:bg-gray-800/30 transition-colors"
              :style="{ borderLeft: `3px solid ${child.droid_color}` }"
              @click="toggle(child.id)"
            >
              <span class="text-sm flex-shrink-0">{{ child.droid_emoji }}</span>
              <span class="text-sm font-semibold font-mono flex-shrink-0" :style="{ color: child.droid_color }">
                {{ child.droid_name }}
              </span>
              <span
                class="text-xs px-1.5 py-0.5 rounded font-mono flex-shrink-0"
                :style="{ backgroundColor: child.droid_color + '22', color: child.droid_color }"
              >
                {{ child.duration_ms > 0 ? formatMs(child.duration_ms) : 'running…' }}
              </span>
              <span class="flex-1" />
              <span class="text-xs text-gray-600 font-mono">{{ formatRel(child.relTimeSec) }}</span>
              <span v-if="child.tools.length" class="text-xs text-gray-700">
                {{ collapsed.has(child.id) ? '▶' : '▼' }}
              </span>
            </div>

            <!-- Droid tool calls -->
            <div v-if="!collapsed.has(child.id) && child.tools.length">
              <div
                v-for="tool in child.tools"
                :key="tool.id"
                class="flex items-start gap-3 px-4 py-1.5 hover:bg-gray-800/20 transition-colors"
                :style="{ borderLeft: `3px solid ${child.droid_color}44`, paddingLeft: '2.5rem' }"
              >
                <!-- Tool icon -->
                <span class="flex-shrink-0 mt-0.5 text-xs" :style="{ color: tool.color }">
                  {{ toolIcon(tool.event.tool_name) }}
                </span>
                <!-- Tool label -->
                <div class="flex-1 min-w-0">
                  <span class="text-xs font-mono" :style="{ color: tool.color }">{{ tool.label }}</span>
                  <span v-if="tool.sublabel" class="text-xs text-gray-600 ml-2">
                    <TextWithLinks :text="tool.sublabel" />
                  </span>
                  <!-- Expandable copy/run block for SQL/Bash -->
                  <div v-if="tool.copyText" class="mt-1.5">
                    <pre class="text-xs text-gray-400 bg-gray-800/60 rounded p-2 whitespace-pre-wrap break-all font-mono leading-relaxed max-h-32 overflow-y-auto">{{ tool.copyText }}</pre>
                    <div class="flex items-center gap-3 mt-1">
                      <button
                        class="text-xs text-gray-600 hover:text-indigo-400 transition-colors"
                        @click.stop="copy(tool.copyText!, tool.id)"
                      >{{ copied === tool.id ? '✓ Copied' : '⎘ Copy' }}</button>
                      <button
                        v-if="tool.event.tool_name === 'mcp__redshift__query_redshift'"
                        class="text-xs text-green-600 hover:text-green-400 transition-colors font-semibold"
                        @click.stop="runQuery(tool.copyText!)"
                      >⚡ Run now</button>
                    </div>
                  </div>
                </div>
                <span class="text-xs text-gray-700 font-mono flex-shrink-0">{{ formatRel(tool.relTimeSec) }}</span>
              </div>
            </div>
          </div>

          <!-- Orphan tool node (not inside a droid) -->
          <div
            v-else-if="child.type === 'tool'"
            class="flex items-start gap-3 px-4 py-2 border-t border-gray-800/60 hover:bg-gray-800/20 transition-colors"
            style="border-left: 3px solid #e2e8f0; padding-left: 2rem"
          >
            <span class="flex-shrink-0 mt-0.5 text-xs" :style="{ color: (child as ToolNode).color }">
              {{ toolIcon((child as ToolNode).event.tool_name) }}
            </span>
            <div class="flex-1 min-w-0">
              <span class="text-xs font-mono" :style="{ color: (child as ToolNode).color }">
                {{ (child as ToolNode).label }}
              </span>
              <span v-if="(child as ToolNode).sublabel" class="text-xs text-gray-600 ml-2">
                <TextWithLinks :text="(child as ToolNode).sublabel" />
              </span>
              <div v-if="(child as ToolNode).copyText" class="mt-1.5">
                <pre class="text-xs text-gray-400 bg-gray-800/60 rounded p-2 whitespace-pre-wrap break-all font-mono leading-relaxed max-h-32 overflow-y-auto">{{ (child as ToolNode).copyText }}</pre>
                <div class="flex items-center gap-3 mt-1">
                  <button
                    class="text-xs text-gray-600 hover:text-indigo-400 transition-colors"
                    @click.stop="copy((child as ToolNode).copyText!, child.id)"
                  >{{ copied === child.id ? '✓ Copied' : '⎘ Copy' }}</button>
                  <button
                    v-if="(child as ToolNode).event.tool_name === 'mcp__redshift__query_redshift'"
                    class="text-xs text-green-600 hover:text-green-400 transition-colors font-semibold"
                    @click.stop="runQuery((child as ToolNode).copyText!)"
                  >⚡ Run now</button>
                </div>
              </div>
            </div>
            <span class="text-xs text-gray-700 font-mono flex-shrink-0">{{ formatRel((child as ToolNode).relTimeSec) }}</span>
          </div>
        </template>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, watch } from 'vue'
import type { ObserverEvent } from '../types/events'
import { useSessionAnalysis, type TurnNode, type ToolNode } from '../composables/useSessionAnalysis'
import TextWithLinks from './TextWithLinks.vue'

const props = defineProps<{ events: ObserverEvent[] }>()

const eventsRef = computed(() => props.events)
const { tree, formatMs, formatRel } = useSessionAnalysis(eventsRef)

// Most recent prompt at top
const displayTree = computed(() => [...tree.value].reverse())

const collapsed = ref(new Set<string>())
const copied = ref<string | null>(null)

function copy(text: string, id?: string) {
  navigator.clipboard.writeText(text)
  if (id) copied.value = id
}

async function runQuery(sql: string) {
  const prompt = `run this redshift query and show me the results:\n\n${sql}`
  await fetch(`http://localhost:4001/launch-new?cmd=${encodeURIComponent(prompt)}`)
}

watch(copied, (val) => {
  if (val) setTimeout(() => { copied.value = null }, 1500)
})

function toggle(id: string) {
  if (collapsed.value.has(id)) collapsed.value.delete(id)
  else collapsed.value.add(id)
  // Force reactivity
  collapsed.value = new Set(collapsed.value)
}

function toolIcon(tool_name: string): string {
  if (tool_name === 'Skill')     return '⚡'
  if (tool_name === 'Task')      return '⬡'
  if (tool_name === 'Read')      return '📄'
  if (tool_name === 'Write')     return '💾'
  if (tool_name === 'Edit')      return '✏️'
  if (tool_name === 'Bash')      return '$'
  if (tool_name === 'Glob')      return '🔎'
  if (tool_name === 'Grep')      return '🔍'
  if (tool_name === 'WebFetch')  return '🌐'
  if (tool_name === 'WebSearch') return '🔍'
  if (tool_name.includes('search') || tool_name.includes('Search')) return '🔍'
  if (tool_name.includes('update') || tool_name.includes('Update')) return '✏️'
  if (tool_name.includes('create') || tool_name.includes('Create')) return '✨'
  if (tool_name.includes('get') || tool_name.includes('Get')) return '📥'
  if (tool_name.startsWith('mcp__')) return '🔌'
  return '▸'
}
</script>
