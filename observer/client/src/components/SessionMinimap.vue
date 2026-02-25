<template>
  <div class="rounded bg-gray-800/40 p-2">
    <svg
      :viewBox="`0 0 240 ${svgHeight}`"
      width="100%"
      class="overflow-visible"
    >
      <!-- Background -->
      <rect x="0" y="0" width="240" rx="3" :height="svgHeight" fill="#f1f5f9" />

      <!-- Axis line -->
      <line x1="0" :y1="AXIS_Y" x2="240" :y2="AXIS_Y" stroke="#cbd5e1" stroke-width="0.5" />

      <!-- Prompt markers -->
      <g v-for="(pm, i) in promptMarkers" :key="`pm-${i}`">
        <line
          :x1="pm.x" y1="0"
          :x2="pm.x" :y2="svgHeight"
          stroke="#6366F1" stroke-width="0.75" stroke-dasharray="2,2" opacity="0.5"
        />
        <text :x="pm.x + 1.5" y="8" fill="#818CF8" font-size="5">P{{ i + 1 }}</text>
      </g>

      <!-- Droid lanes -->
      <g v-for="(lane, li) in droidLanes" :key="lane.name">
        <!-- Lane label -->
        <text
          x="1" :y="laneY(li) + ROW_H / 2 + 2"
          :fill="lane.color" font-size="5.5"
        >{{ lane.emoji }}</text>

        <!-- Spans for this droid -->
        <g v-for="(span, si) in spansForDroid(lane.name)" :key="`span-${si}`">
          <rect
            :x="span.x1" :y="laneY(li) + 1"
            :width="Math.max(span.w, 2)" :height="ROW_H - 2"
            :fill="lane.color + '55'" :stroke="lane.color"
            stroke-width="0.75" rx="1.5"
          />
        </g>
      </g>

      <!-- Tool call ticks -->
      <g v-for="(tc, i) in toolTicks" :key="`tc-${i}`">
        <line
          :x1="tc.x" :y1="AXIS_Y - 3"
          :x2="tc.x" :y2="AXIS_Y + 3"
          :stroke="tc.color" stroke-width="1.5"
        />
      </g>

      <!-- Time labels at start and end -->
      <text x="2" :y="svgHeight - 1" fill="#94a3b8" font-size="5">0s</text>
      <text :x="238" :y="svgHeight - 1" fill="#94a3b8" font-size="5" text-anchor="end">
        {{ formatMs(durationMs) }}
      </text>
    </svg>
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import type { ObserverEvent } from '../types/events'
import { useSessionAnalysis } from '../composables/useSessionAnalysis'

const props = defineProps<{
  events: ObserverEvent[]
  durationMs: number
}>()

const eventsRef = computed(() => props.events)
const { sorted, startTs, tree, formatMs } = useSessionAnalysis(eventsRef)

const W = 240
const ML = 10   // left margin for emoji labels
const CHART_W = W - ML - 2
const AXIS_Y = 10
const ROW_H = 8

// Droid lanes
const droidLanes = computed(() => {
  const seen = new Set<string>()
  const lanes: Array<{ name: string; color: string; emoji: string }> = []
  for (const turn of tree.value) {
    for (const child of turn.children) {
      if (child.type === 'droid' && !seen.has(child.droid_name)) {
        seen.add(child.droid_name)
        lanes.push({ name: child.droid_name, color: child.droid_color, emoji: child.droid_emoji })
      }
    }
  }
  return lanes
})

const svgHeight = computed(() => AXIS_Y + droidLanes.value.length * (ROW_H + 2) + 10)

function laneY(i: number): number {
  return AXIS_Y + 2 + i * (ROW_H + 2)
}

function tsToX(ts: number): number {
  return ML + ((ts - startTs.value) / props.durationMs) * CHART_W
}

// Collect all droid spans
interface Span { name: string; x1: number; w: number }
const allSpans = computed((): Span[] => {
  const spans: Span[] = []
  for (const turn of tree.value) {
    for (const child of turn.children) {
      if (child.type === 'droid') {
        spans.push({
          name: child.droid_name,
          x1: tsToX(child.start_ts),
          w: tsToX(child.end_ts) - tsToX(child.start_ts),
        })
      }
    }
  }
  return spans
})

function spansForDroid(name: string) {
  return allSpans.value.filter(s => s.name === name)
}

// Prompt markers
const promptMarkers = computed(() =>
  sorted.value
    .filter(e => e.hook_event_type === 'UserPromptSubmit')
    .map(e => ({ x: tsToX(e.timestamp) }))
)

// Tool ticks on the axis
const TOOL_COLORS: Record<string, string> = {
  Skill: '#A855F7',
  Task: '#F59E0B',
}
const toolTicks = computed(() =>
  sorted.value
    .filter(e => e.hook_event_type === 'PreToolUse')
    .map(e => ({
      x: tsToX(e.timestamp),
      color: e.tool_name === 'Skill' ? TOOL_COLORS.Skill
        : e.tool_name === 'Task' ? TOOL_COLORS.Task
        : e.tool_name.startsWith('mcp__') ? '#06B6D4'
        : '#4B5563',
    }))
)
</script>
