<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 bg-black/80 backdrop-blur-sm flex items-center justify-center z-50 p-4"
      @click.self="$emit('close')"
    >
      <div
        class="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl flex flex-col"
        style="width: min(96vw, 1400px); height: min(90vh, 700px)"
        @keydown.esc="$emit('close')"
      >
        <!-- Header bar -->
        <div class="flex items-center gap-4 px-5 py-3 border-b border-gray-800 flex-shrink-0">
          <span class="text-sm font-semibold text-white">Session Timeline</span>
          <span class="text-xs text-gray-500 font-mono">{{ formatMs(durationMs) }} · {{ lanes.length }} droids</span>

          <!-- Zoom controls -->
          <div class="flex items-center gap-1 ml-2">
            <span class="text-xs text-gray-500 mr-1">Zoom</span>
            <button
              v-for="z in ZOOM_LEVELS"
              :key="z.v"
              class="text-xs px-2 py-0.5 rounded font-mono transition-colors"
              :class="zoom === z.v ? 'bg-indigo-600 text-white' : 'text-gray-500 hover:text-gray-300 bg-gray-800'"
              @click="zoom = z.v"
            >{{ z.label }}</button>
          </div>

          <div class="flex-1" />

          <!-- Legend -->
          <div class="flex items-center gap-3 text-xs text-gray-500 flex-shrink-0">
            <span class="flex items-center gap-1.5"><span class="w-2 h-2 rounded-full bg-indigo-500"></span>Prompt</span>
            <span class="flex items-center gap-1.5"><span class="w-3 h-2 rounded bg-amber-400"></span>Task</span>
            <span class="flex items-center gap-1.5"><span class="w-3 h-2 rounded bg-purple-500"></span>Skill</span>
            <span class="flex items-center gap-1.5"><span class="w-3 h-2 rounded bg-cyan-400"></span>MCP</span>
            <span class="flex items-center gap-1.5"><span class="w-3 h-2 rounded bg-green-400"></span>Bash</span>
            <span class="flex items-center gap-1.5"><span class="w-3 h-2 rounded bg-gray-400"></span>File</span>
          </div>

          <button class="text-gray-500 hover:text-white transition-colors ml-2 text-lg leading-none" @click="$emit('close')">✕</button>
        </div>

        <!-- Empty state -->
        <div v-if="!lanes.length" class="flex-1 flex items-center justify-center text-gray-600 text-sm">
          No droid activity to display
        </div>

        <!-- Two-column timeline -->
        <div v-else class="flex flex-1 overflow-hidden">

          <!-- LEFT: sticky droid labels -->
          <div class="flex-shrink-0 bg-gray-900 border-r border-gray-800 z-10" :style="{ width: LABEL_W + 'px' }">
            <!-- Spacer for time axis -->
            <div class="border-b border-gray-800" :style="{ height: HEADER_H + 'px' }" />
            <!-- Lane labels -->
            <div
              v-for="lane in lanes"
              :key="lane.name"
              class="flex items-center px-4 border-b border-gray-800/40"
              :style="{ height: ROW_H + 'px' }"
            >
              <div>
                <div class="text-sm font-mono font-semibold leading-tight" :style="{ color: lane.color }">
                  {{ lane.emoji }} {{ lane.name }}
                </div>
                <div class="text-xs text-gray-600 mt-0.5">
                  {{ laneStats(lane.name) }}
                </div>
              </div>
            </div>
          </div>

          <!-- RIGHT: scrollable chart -->
          <div ref="chartEl" class="flex-1 overflow-x-auto overflow-y-hidden">
            <svg
              :width="canvasWidth + MR"
              :height="svgHeight"
              style="display: block; min-height: 100%"
            >
              <!-- Row backgrounds -->
              <rect
                v-for="(_, i) in lanes"
                :key="`rb-${i}`"
                x="0" :y="HEADER_H + i * ROW_H"
                :width="canvasWidth + MR" :height="ROW_H"
                :fill="i % 2 === 0 ? 'rgba(255,255,255,0.015)' : 'transparent'"
              />

              <!-- Vertical grid lines -->
              <line
                v-for="tick in timeTicks"
                :key="`g-${tick.ts}`"
                :x1="tick.x" :y1="HEADER_H"
                :x2="tick.x" :y2="svgHeight"
                stroke="rgba(255,255,255,0.05)" stroke-width="1"
              />

              <!-- Time axis line -->
              <line x1="0" :y1="HEADER_H - 1" :x2="canvasWidth + MR" :y2="HEADER_H - 1"
                stroke="#374151" stroke-width="1" />

              <!-- Time tick marks + labels -->
              <g v-for="tick in timeTicks" :key="`tick-${tick.ts}`">
                <line :x1="tick.x" :y1="HEADER_H - 5" :x2="tick.x" :y2="HEADER_H + 3"
                  stroke="#4B5563" stroke-width="1" />
                <text :x="tick.x" :y="HEADER_H - 10"
                  fill="#6B7280" font-size="11" text-anchor="middle" font-family="ui-monospace,monospace">
                  {{ tick.label }}
                </text>
              </g>

              <!-- Prompt markers -->
              <g v-for="(pm, i) in promptMarkers" :key="`pm-${i}`">
                <!-- Full-height dashed line -->
                <line
                  :x1="pm.x" y1="0"
                  :x2="pm.x" :y2="svgHeight"
                  stroke="#6366F1" stroke-width="2" stroke-dasharray="5,4" opacity="0.5"
                />
                <!-- Pill badge -->
                <rect :x="pm.x - 1" y="5" width="36" height="24" fill="#6366F1" rx="5" />
                <text :x="pm.x + 17" y="22"
                  fill="white" font-size="14" text-anchor="middle"
                  font-family="ui-monospace,monospace" font-weight="700">
                  P{{ i + 1 }}
                </text>
                <!-- Preview text beside badge -->
                <text
                  :x="pm.x + 42" y="22"
                  fill="#a5b4fc" font-size="12" font-family="ui-sans-serif,sans-serif"
                >{{ pm.preview.slice(0, 55) }}{{ pm.preview.length > 55 ? '…' : '' }}</text>
              </g>

              <!-- Droid spans -->
              <g v-for="span in allSpans" :key="span.id">
                <!-- Main bar -->
                <rect
                  :x="span.x1" :y="span.barY"
                  :width="Math.max(span.w, 4)" :height="BAR_H"
                  :fill="span.color + '35'" :stroke="span.color"
                  stroke-width="2" rx="5"
                />
                <!-- Duration label -->
                <text
                  v-if="span.w > 60"
                  :x="span.x1 + span.w / 2" :y="span.barY + BAR_H / 2 + 5"
                  :fill="span.color" font-size="12" text-anchor="middle"
                  font-family="ui-monospace,monospace" font-weight="600"
                >{{ span.durationLabel }}</text>
              </g>

              <!-- Tool call dots (shown on the droid lane center) -->
              <circle
                v-for="(tc, i) in toolDots"
                :key="`td-${i}`"
                :cx="tc.x" :cy="tc.cy"
                :r="tc.r"
                :fill="tc.color"
                opacity="0.9"
              />

              <!-- End time label -->
              <text :x="canvasWidth + MR - 4" :y="svgHeight - 4"
                fill="#4B5563" font-size="10" text-anchor="end"
                font-family="ui-monospace,monospace">{{ formatMs(durationMs) }}</text>
            </svg>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, computed } from 'vue'
import type { ObserverEvent } from '../types/events'
import { useSessionAnalysis } from '../composables/useSessionAnalysis'

const props = defineProps<{
  events: ObserverEvent[]
  durationMs: number
}>()
defineEmits<{ close: [] }>()

const eventsRef = computed(() => props.events)
const { sorted, startTs, tree, formatMs } = useSessionAnalysis(eventsRef)

// ── Layout constants ──────────────────────────────────────────────────────────
const LABEL_W = 180
const MR      = 32
const HEADER_H = 52
const ROW_H   = 72
const BAR_H   = 38
const BAR_PAD = (ROW_H - BAR_H) / 2

// ── Zoom ──────────────────────────────────────────────────────────────────────
const ZOOM_LEVELS = [
  { v: 0.5, label: '0.5×' },
  { v: 1,   label: '1×'   },
  { v: 2,   label: '2×'   },
  { v: 4,   label: '4×'   },
]
const zoom = ref(1)

// pixels per millisecond: base is 2px/second at zoom=1
const pxPerMs = computed(() => (2 / 1000) * zoom.value)
const canvasWidth = computed(() =>
  Math.max(600, Math.round(props.durationMs * pxPerMs.value))
)

function tsToX(ts: number) {
  return (ts - startTs.value) * pxPerMs.value
}

const svgHeight = computed(() => HEADER_H + lanes.value.length * ROW_H + 24)

// ── Lanes ─────────────────────────────────────────────────────────────────────
const lanes = computed(() => {
  const seen = new Set<string>()
  const result: Array<{ name: string; color: string; emoji: string }> = []
  for (const turn of tree.value) {
    for (const child of turn.children) {
      if (child.type === 'droid' && !seen.has(child.droid_name)) {
        seen.add(child.droid_name)
        result.push({ name: child.droid_name, color: child.droid_color, emoji: child.droid_emoji })
      }
    }
  }
  return result
})

function laneY(i: number) { return HEADER_H + i * ROW_H }

function laneStats(name: string) {
  let runs = 0, totalMs = 0
  for (const turn of tree.value) {
    for (const child of turn.children) {
      if (child.type === 'droid' && child.droid_name === name) {
        runs++
        totalMs += child.duration_ms
      }
    }
  }
  return `${runs} run${runs !== 1 ? 's' : ''} · ${formatMs(totalMs)}`
}

// ── Time axis ticks ───────────────────────────────────────────────────────────
const NICE_INTERVALS_MS = [
  500, 1000, 2000, 5000, 10000, 15000, 30000,
  60000, 120000, 300000, 600000, 1200000, 3600000,
]

const timeTicks = computed(() => {
  const targetGapPx = 100
  const targetMs = targetGapPx / pxPerMs.value
  const step = NICE_INTERVALS_MS.find(n => n >= targetMs) ?? NICE_INTERVALS_MS[NICE_INTERVALS_MS.length - 1]

  const ticks: { x: number; ts: number; label: string }[] = []
  for (let t = 0; t <= props.durationMs; t += step) {
    ticks.push({ x: tsToX(startTs.value + t), ts: t, label: formatMs(t) })
  }
  return ticks
})

// ── Prompt markers ────────────────────────────────────────────────────────────
const promptMarkers = computed(() =>
  sorted.value
    .filter(e => e.hook_event_type === 'UserPromptSubmit')
    .map(e => ({
      x: tsToX(e.timestamp),
      preview: (e.payload?.prompt_preview as string) ?? '',
    }))
)

// ── Droid spans ───────────────────────────────────────────────────────────────
const allSpans = computed(() => {
  const spans: Array<{
    id: string; x1: number; w: number; barY: number; color: string; durationLabel: string
  }> = []
  for (const turn of tree.value) {
    for (const child of turn.children) {
      if (child.type === 'droid') {
        const li = lanes.value.findIndex(l => l.name === child.droid_name)
        if (li < 0) continue
        const x1 = tsToX(child.start_ts)
        const x2 = tsToX(child.end_ts)
        spans.push({
          id: child.id,
          x1,
          w: Math.max(x2 - x1, 4),
          barY: laneY(li) + BAR_PAD,
          color: child.droid_color,
          durationLabel: child.duration_ms > 0 ? formatMs(child.duration_ms) : '…',
        })
      }
    }
  }
  return spans
})

// ── Tool dots ─────────────────────────────────────────────────────────────────
const TOOL_COLOR: Record<string, string> = {
  Skill: '#A855F7', Task: '#F59E0B', Bash: '#34D399',
  WebFetch: '#60A5FA', WebSearch: '#60A5FA',
}
function toolColor(name: string) {
  if (TOOL_COLOR[name]) return TOOL_COLOR[name]
  if (name.startsWith('mcp__atlassian')) return '#06B6D4'
  if (name.startsWith('mcp__redshift'))  return '#10B981'
  if (name.startsWith('mcp__'))          return '#67E8F9'
  return '#9CA3AF'
}

const toolDots = computed(() => {
  const dots: Array<{ x: number; cy: number; r: number; color: string }> = []
  for (const turn of tree.value) {
    for (const child of turn.children) {
      if (child.type === 'droid') {
        const li = lanes.value.findIndex(l => l.name === child.droid_name)
        if (li < 0) continue
        const cy = laneY(li) + ROW_H / 2
        for (const tool of child.tools) {
          const name = tool.event.tool_name
          // Different sizes for different tool types
          const r = (name === 'Task' || name === 'Skill') ? 6 : name.startsWith('mcp__') ? 5 : 4
          dots.push({ x: tsToX(tool.event.timestamp), cy, r, color: toolColor(name) })
        }
      }
    }
  }
  return dots
})

const chartEl = ref<HTMLElement | null>(null)
</script>
