<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 bg-black/80 backdrop-blur-sm flex items-center justify-center z-50 p-4"
      @click.self="$emit('close')"
    >
      <div
        class="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl flex flex-col"
        style="width: min(96vw, 1440px); height: min(92vh, 780px)"
      >
        <!-- ── Header ─────────────────────────────────────────────────────── -->
        <div class="flex items-center gap-4 px-5 py-3 border-b border-gray-800 flex-shrink-0">
          <span class="text-sm font-semibold text-white">Session Timeline</span>
          <span class="text-xs text-gray-500 font-mono">{{ formatMs(durationMs) }} · {{ lanes.length }} droids</span>

          <div class="flex items-center gap-1 ml-2">
            <span class="text-xs text-gray-500 mr-1">Zoom</span>
            <button v-for="z in ZOOM_LEVELS" :key="z.v"
              class="text-xs px-2 py-0.5 rounded font-mono transition-colors"
              :class="zoom === z.v ? 'bg-indigo-600 text-white' : 'text-gray-500 hover:text-gray-300 bg-gray-800'"
              @click="zoom = z.v">{{ z.label }}</button>
          </div>

          <div class="flex-1" />

          <!-- Legend -->
          <div class="flex items-center gap-3 text-xs text-gray-500 flex-shrink-0">
            <span v-for="l in LEGEND" :key="l.label" class="flex items-center gap-1.5">
              <span class="w-3 h-3 rounded-sm inline-block" :style="{ background: l.color }" />{{ l.label }}
            </span>
          </div>
          <button class="text-gray-500 hover:text-white transition-colors ml-2 text-lg leading-none" @click="$emit('close')">✕</button>
        </div>

        <!-- ── Empty ─────────────────────────────────────────────────────── -->
        <div v-if="!lanes.length" class="flex-1 flex items-center justify-center text-gray-600 text-sm">
          No droid activity to display
        </div>

        <!-- ── Flame chart ──────────────────────────────────────────────── -->
        <div v-else class="flex flex-1 overflow-hidden">

          <!-- Sticky label column -->
          <div class="flex-shrink-0 bg-gray-900 border-r border-gray-800 z-10" :style="{ width: LABEL_W + 'px' }">
            <div class="border-b border-gray-800" :style="{ height: HEADER_H + 'px' }" />
            <div
              v-for="lane in lanes" :key="lane.name"
              class="flex flex-col justify-center px-3 border-b border-gray-800/30"
              :style="{ height: ROW_H + 'px' }"
            >
              <div class="text-sm font-mono font-semibold truncate" :style="{ color: lane.color }">
                {{ lane.emoji }} {{ lane.name }}
              </div>
              <div class="text-xs text-gray-600 mt-0.5">{{ laneStats(lane.name) }}</div>
            </div>
          </div>

          <!-- Scrollable SVG -->
          <div class="flex-1 overflow-x-auto overflow-y-hidden">
            <svg :width="canvasWidth + MR" :height="svgHeight" style="display:block">

              <!-- Row backgrounds (subtle alternating) -->
              <rect v-for="(_, i) in lanes" :key="`rb-${i}`"
                x="0" :y="HEADER_H + i * ROW_H"
                :width="canvasWidth + MR" :height="ROW_H"
                :fill="i % 2 === 0 ? 'rgba(255,255,255,0.018)' : 'transparent'" />

              <!-- Prompt section backgrounds -->
              <rect v-for="(sec, i) in promptSections" :key="`psec-${i}`"
                :x="sec.x1" :y="0"
                :width="sec.w" :height="svgHeight"
                :fill="i % 2 === 0 ? 'rgba(99,102,241,0.04)' : 'rgba(99,102,241,0.02)'" />

              <!-- Grid lines -->
              <line v-for="tick in timeTicks" :key="`g-${tick.ts}`"
                :x1="tick.x" :y1="HEADER_H"
                :x2="tick.x" :y2="svgHeight"
                stroke="rgba(255,255,255,0.05)" stroke-width="1" />

              <!-- Time axis -->
              <line x1="0" :y1="HEADER_H - 1" :x2="canvasWidth + MR" :y2="HEADER_H - 1"
                stroke="#374151" stroke-width="1" />
              <g v-for="tick in timeTicks" :key="`t-${tick.ts}`">
                <line :x1="tick.x" :y1="HEADER_H - 4" :x2="tick.x" :y2="HEADER_H + 2"
                  stroke="#4B5563" stroke-width="1" />
                <text :x="tick.x" :y="HEADER_H - 8"
                  fill="#6B7280" font-size="11" text-anchor="middle" font-family="ui-monospace,monospace">
                  {{ tick.label }}
                </text>
              </g>

              <!-- Prompt markers + pill labels -->
              <g v-for="(pm, i) in promptMarkers" :key="`pm-${i}`">
                <line :x1="pm.x" y1="0" :x2="pm.x" :y2="svgHeight"
                  stroke="#6366F1" stroke-width="1.5" stroke-dasharray="5,4" opacity="0.45" />
                <rect :x="pm.x - 1" y="4" width="34" height="24" fill="#6366F1" rx="5" />
                <text :x="pm.x + 16" y="21"
                  fill="white" font-size="13" text-anchor="middle"
                  font-family="ui-monospace,monospace" font-weight="700">P{{ i + 1 }}</text>
                <text :x="pm.x + 40" y="21"
                  fill="#a5b4fc" font-size="11" font-family="ui-sans-serif,sans-serif">
                  {{ pm.preview.slice(0, 50) }}{{ pm.preview.length > 50 ? '…' : '' }}
                </text>
              </g>

              <!-- ── FLAME CHART ROWS ────────────────────────────────────── -->
              <g v-for="(lane, li) in lanes" :key="`lane-${li}`">

                <!-- Droid span bars (top sub-row) -->
                <g v-for="span in spansForLane(li)" :key="span.id">
                  <rect
                    :x="span.x1" :y="spanBarY(li)"
                    :width="Math.max(span.w, 4)" :height="SPAN_H"
                    :fill="span.color + '38'" :stroke="span.color"
                    stroke-width="1.5" rx="4"
                  />
                  <!-- Duration label -->
                  <text v-if="span.w > 48"
                    :x="span.x1 + span.w / 2" :y="spanBarY(li) + SPAN_H / 2 + 4"
                    :fill="span.color" font-size="11" text-anchor="middle"
                    font-family="ui-monospace,monospace" font-weight="600">
                    {{ span.durationLabel }}
                  </text>
                  <title>{{ span.droid_name }} · {{ span.durationLabel }}</title>
                </g>

                <!-- Tool call bars (bottom sub-row, nested below droid spans) -->
                <g v-for="(tc, ti) in toolsForLane(li)" :key="`tc-${li}-${ti}`">
                  <rect
                    :x="tc.x" :y="toolBarY(li)"
                    :width="tc.w" :height="TOOL_H"
                    :fill="tc.color" rx="2" opacity="0.88"
                  />
                  <!-- Single-char label if wide enough -->
                  <text v-if="tc.w >= 14"
                    :x="tc.x + tc.w / 2" :y="toolBarY(li) + TOOL_H / 2 + 4"
                    fill="white" font-size="9" text-anchor="middle"
                    font-family="ui-monospace,monospace">{{ tc.abbr }}</text>
                  <title>{{ tc.name }}{{ tc.detail ? ' · ' + tc.detail : '' }}</title>
                </g>

                <!-- Row divider -->
                <line
                  x1="0" :y1="HEADER_H + (li + 1) * ROW_H - 1"
                  :x2="canvasWidth + MR" :y2="HEADER_H + (li + 1) * ROW_H - 1"
                  stroke="rgba(255,255,255,0.05)" stroke-width="1" />
              </g>

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

const props = defineProps<{ events: ObserverEvent[]; durationMs: number }>()
defineEmits<{ close: [] }>()

const eventsRef = computed(() => props.events)
const { sorted, startTs, tree, formatMs } = useSessionAnalysis(eventsRef)

// ── Layout ───────────────────────────────────────────────────────────────────
const LABEL_W  = 172
const MR       = 24
const HEADER_H = 48
const SPAN_H   = 34   // droid span bar height
const TOOL_H   = 16   // tool call bar height
const GAP      = 6    // gap between span and tool rows
const ROW_PAD  = 8    // padding below tools
const ROW_H    = SPAN_H + GAP + TOOL_H + ROW_PAD  // = 64

const spanBarY  = (i: number) => HEADER_H + i * ROW_H + 4
const toolBarY  = (i: number) => spanBarY(i) + SPAN_H + GAP
const svgHeight = computed(() => HEADER_H + lanes.value.length * ROW_H + 20)

// ── Zoom ─────────────────────────────────────────────────────────────────────
const ZOOM_LEVELS = [
  { v: 0.5, label: '0.5×' }, { v: 1, label: '1×' },
  { v: 2,   label: '2×'   }, { v: 4, label: '4×' },
]
const zoom = ref(1)
const pxPerMs   = computed(() => (2 / 1000) * zoom.value)
const canvasWidth = computed(() => Math.max(600, Math.round(props.durationMs * pxPerMs.value)))
const tsToX     = (ts: number) => (ts - startTs.value) * pxPerMs.value

// ── Lanes (unique droids) ─────────────────────────────────────────────────────
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

function laneStats(name: string) {
  let runs = 0, totalMs = 0
  for (const turn of tree.value)
    for (const child of turn.children)
      if (child.type === 'droid' && child.droid_name === name) { runs++; totalMs += child.duration_ms }
  return `${runs} run${runs !== 1 ? 's' : ''} · ${formatMs(totalMs)}`
}

// ── Droid spans per lane ──────────────────────────────────────────────────────
interface Span { id: string; x1: number; w: number; color: string; droid_name: string; durationLabel: string }

function spansForLane(li: number): Span[] {
  const name = lanes.value[li].name
  const color = lanes.value[li].color
  const spans: Span[] = []
  for (const turn of tree.value)
    for (const child of turn.children)
      if (child.type === 'droid' && child.droid_name === name) {
        const x1 = tsToX(child.start_ts)
        const x2 = tsToX(child.end_ts)
        spans.push({ id: child.id, x1, w: Math.max(x2 - x1, 4), color, droid_name: name, durationLabel: formatMs(child.duration_ms) })
      }
  return spans
}

// ── Tool calls per lane ───────────────────────────────────────────────────────
const TOOL_COLORS: Record<string, string> = {
  Read: '#64748b', Write: '#64748b', Edit: '#94a3b8', Glob: '#475569', Grep: '#475569',
  Bash: '#34d399', WebFetch: '#60a5fa', WebSearch: '#60a5fa',
  Skill: '#a855f7', Task: '#f59e0b',
}
function toolColor(name: string) {
  if (TOOL_COLORS[name]) return TOOL_COLORS[name]
  if (name.startsWith('mcp__atlassian')) return '#06b6d4'
  if (name.startsWith('mcp__redshift'))  return '#10b981'
  if (name.startsWith('mcp__'))          return '#67e8f9'
  return '#6b7280'
}

// Width and abbreviation per tool type
function toolMeta(name: string): { w: number; abbr: string } {
  if (name === 'Task' || name === 'Skill')   return { w: 18, abbr: name === 'Skill' ? '⚡' : '⬡' }
  if (name.startsWith('mcp__'))               return { w: 16, abbr: '◉' }
  if (name === 'Bash')                        return { w: 14, abbr: '$' }
  if (name === 'Read')                        return { w: 10, abbr: 'R' }
  if (name === 'Write')                       return { w: 10, abbr: 'W' }
  if (name === 'Edit')                        return { w: 10, abbr: 'E' }
  if (name === 'Grep')                        return { w: 10, abbr: 'G' }
  if (name === 'Glob')                        return { w: 10, abbr: 'Gl' }
  return { w: 10, abbr: '·' }
}

interface ToolDot { x: number; w: number; color: string; abbr: string; name: string; detail: string }

function toolsForLane(li: number): ToolDot[] {
  const name = lanes.value[li].name
  const dots: ToolDot[] = []
  for (const turn of tree.value)
    for (const child of turn.children)
      if (child.type === 'droid' && child.droid_name === name)
        for (const tool of child.tools) {
          const { w, abbr } = toolMeta(tool.event.tool_name)
          const detail = tool.sublabel?.slice(0, 60) ?? ''
          dots.push({ x: tsToX(tool.event.timestamp), w, color: toolColor(tool.event.tool_name), abbr, name: tool.label, detail })
        }
  return dots
}

// ── Time ticks ────────────────────────────────────────────────────────────────
const NICE_MS = [500,1000,2000,5000,10000,15000,30000,60000,120000,300000,600000,1200000,3600000]

const timeTicks = computed(() => {
  const step = NICE_MS.find(n => n >= 100 / pxPerMs.value) ?? NICE_MS[NICE_MS.length - 1]
  const ticks: { x: number; ts: number; label: string }[] = []
  for (let t = 0; t <= props.durationMs; t += step)
    ticks.push({ x: tsToX(startTs.value + t), ts: t, label: formatMs(t) })
  return ticks
})

// ── Prompt markers ────────────────────────────────────────────────────────────
const promptMarkers = computed(() =>
  sorted.value
    .filter(e => e.hook_event_type === 'UserPromptSubmit')
    .map(e => ({ x: tsToX(e.timestamp), preview: (e.payload?.prompt_preview as string) ?? '' }))
)

// Prompt sections (background shading between markers)
const promptSections = computed(() => {
  const xs = promptMarkers.value.map(p => p.x)
  const end = canvasWidth.value
  return xs.map((x1, i) => ({ x1, w: (xs[i + 1] ?? end) - x1 }))
})

// ── Legend ────────────────────────────────────────────────────────────────────
const LEGEND = [
  { label: 'Droid run', color: '#6366f1' },
  { label: 'MCP',    color: '#06b6d4' },
  { label: 'Bash',   color: '#34d399' },
  { label: 'Skill',  color: '#a855f7' },
  { label: 'Task',   color: '#f59e0b' },
  { label: 'File',   color: '#64748b' },
]
</script>
