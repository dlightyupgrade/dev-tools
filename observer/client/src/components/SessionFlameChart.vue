<template>
  <div class="flex flex-col flex-1 overflow-hidden bg-gray-950">

    <!-- Toolbar -->
    <div class="flex items-center gap-3 px-4 py-2 border-b border-gray-800 flex-shrink-0 bg-gray-900">
      <!-- Zoom -->
      <span class="text-xs text-gray-500">Zoom</span>
      <div class="flex items-center gap-1">
        <button v-for="z in ZOOM_LEVELS" :key="z.v"
          class="text-xs px-2.5 py-1 rounded font-mono transition-colors"
          :class="zoom === z.v ? 'bg-indigo-600 text-white' : 'text-gray-500 hover:text-gray-300 bg-gray-800'"
          @click="zoom = z.v">{{ z.label }}</button>
      </div>
      <span class="text-xs text-gray-700">|</span>
      <span class="text-xs text-gray-500 font-mono">{{ formatMs(durationMs) }} · {{ lanes.length }} droids · {{ totalToolCalls }} tool calls</span>
      <div class="flex-1" />
      <!-- Legend -->
      <div class="flex items-center gap-3">
        <span v-for="l in LEGEND" :key="l.label" class="flex items-center gap-1.5 text-xs text-gray-500">
          <span class="w-3 h-2.5 rounded-sm inline-block flex-shrink-0" :style="{ background: l.color }" />
          {{ l.label }}
        </span>
      </div>
    </div>

    <!-- Empty -->
    <div v-if="!lanes.length" class="flex-1 flex items-center justify-center text-gray-600 text-sm">
      No droid activity recorded for this session
    </div>

    <!-- Flame chart -->
    <div v-else class="flex flex-1 overflow-hidden">

      <!-- Sticky label column -->
      <div class="flex-shrink-0 border-r border-gray-800 bg-gray-900 z-10 overflow-y-hidden"
        :style="{ width: LABEL_W + 'px' }">
        <!-- Time axis spacer -->
        <div class="border-b border-gray-800" :style="{ height: HEADER_H + 'px' }" />
        <!-- Lane labels -->
        <div v-for="lane in lanes" :key="lane.name"
          class="flex flex-col justify-center px-4 border-b border-gray-800/40"
          :style="{ height: ROW_H + 'px', minHeight: ROW_H + 'px' }">
          <div class="text-sm font-mono font-semibold truncate" :style="{ color: lane.color }">
            {{ lane.emoji }} {{ lane.name }}
          </div>
          <div class="text-xs text-gray-600 mt-0.5">{{ laneStats(lane.name) }}</div>
        </div>
      </div>

      <!-- Scrollable chart -->
      <div ref="chartContainerEl" class="flex-1 overflow-x-auto overflow-y-hidden">
        <svg
          :width="canvasWidth + MR"
          :height="svgH"
          style="display: block; min-height: 100%"
        >
          <!-- Row backgrounds -->
          <rect v-for="(_, i) in lanes" :key="`rb-${i}`"
            x="0" :y="HEADER_H + i * ROW_H" :width="canvasWidth + MR" :height="ROW_H"
            :fill="i % 2 === 0 ? 'rgba(255,255,255,0.018)' : 'transparent'" />

          <!-- Prompt section tints -->
          <rect v-for="(sec, i) in promptSections" :key="`ps-${i}`"
            :x="sec.x1" y="0" :width="sec.w" :height="svgH"
            :fill="i % 2 === 0 ? 'rgba(99,102,241,0.05)' : 'rgba(99,102,241,0.02)'" />

          <!-- Vertical grid lines -->
          <line v-for="tick in timeTicks" :key="`gl-${tick.ts}`"
            :x1="tick.x" :y1="HEADER_H" :x2="tick.x" :y2="svgH"
            stroke="rgba(255,255,255,0.05)" stroke-width="1" />

          <!-- Time axis -->
          <line x1="0" :y1="HEADER_H" :x2="canvasWidth + MR" :y2="HEADER_H"
            stroke="#374151" stroke-width="1" />
          <g v-for="tick in timeTicks" :key="`tick-${tick.ts}`">
            <line :x1="tick.x" :y1="HEADER_H - 4" :x2="tick.x" :y2="HEADER_H + 3"
              stroke="#4B5563" stroke-width="1" />
            <text :x="tick.x" :y="HEADER_H - 8" fill="#6B7280" font-size="11"
              text-anchor="middle" font-family="ui-monospace,monospace">{{ tick.label }}</text>
          </g>

          <!-- Prompt markers -->
          <g v-for="(pm, i) in promptMarkers" :key="`pm-${i}`">
            <line :x1="pm.x" y1="0" :x2="pm.x" :y2="svgH"
              stroke="#6366F1" stroke-width="1.5" stroke-dasharray="6,4" opacity="0.4" />
            <!-- Big pill badge -->
            <rect :x="pm.x - 1" y="4" width="36" height="26" fill="#6366F1" rx="6" />
            <text :x="pm.x + 17" y="22" fill="white" font-size="14" text-anchor="middle"
              font-family="ui-monospace,monospace" font-weight="700">P{{ i + 1 }}</text>
            <!-- Preview text -->
            <text :x="pm.x + 42" y="22" fill="#a5b4fc" font-size="12"
              font-family="ui-sans-serif,sans-serif">
              {{ pm.preview.slice(0, 60) }}{{ pm.preview.length > 60 ? '…' : '' }}
            </text>
          </g>

          <!-- ── Flame rows ── -->
          <g v-for="(lane, li) in lanes" :key="`row-${li}`">

            <!-- Droid span bars -->
            <g v-for="span in spansFor(li)" :key="span.id">
              <rect
                :x="span.x1" :y="spanY(li)"
                :width="Math.max(span.w, 4)" :height="spanH"
                :fill="span.color + '35'" :stroke="span.color" stroke-width="2" rx="5"
              />
              <text v-if="span.w > 55"
                :x="span.x1 + span.w / 2" :y="spanY(li) + spanH / 2 + 5"
                :fill="span.color" :font-size="Math.min(14, spanH * 0.35)" text-anchor="middle"
                font-family="ui-monospace,monospace" font-weight="600">
                {{ span.label }}
              </text>
              <title>{{ lane.name }} — {{ span.label }}</title>
            </g>

            <!-- Lane separator -->
            <line x1="0" :y1="HEADER_H + (li + 1) * ROW_H"
              :x2="canvasWidth + MR" :y2="HEADER_H + (li + 1) * ROW_H"
              stroke="rgba(255,255,255,0.05)" stroke-width="1" />
          </g>

          <!-- End label -->
          <text :x="canvasWidth + MR - 4" :y="svgH - 6" fill="#4B5563" font-size="10"
            text-anchor="end" font-family="ui-monospace,monospace">{{ formatMs(durationMs) }}</text>
        </svg>
      </div>
    </div>
  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, onUnmounted } from 'vue'
import type { ObserverEvent } from '../types/events'
import { useSessionAnalysis } from '../composables/useSessionAnalysis'

const props = defineProps<{ events: ObserverEvent[] }>()

const eventsRef = computed(() => props.events)
const { sorted, startTs, durationMs, tree, formatMs } = useSessionAnalysis(eventsRef)

// ── Layout ───────────────────────────────────────────────────────────────────
const LABEL_W  = 200
const MR       = 32
const HEADER_H = 52

// Dynamic row height — fills all available vertical space
const chartContainerEl = ref<HTMLElement | null>(null)
const containerH = ref(500)

let ro: ResizeObserver | null = null
onMounted(() => {
  ro = new ResizeObserver(entries => { containerH.value = entries[0]?.contentRect.height ?? 500 })
  if (chartContainerEl.value) ro.observe(chartContainerEl.value)
})
onUnmounted(() => ro?.disconnect())

const ROW_H = computed(() =>
  lanes.value.length ? Math.max(60, Math.floor((containerH.value - HEADER_H - 20) / lanes.value.length)) : 100
)
const spanH = computed(() => Math.max(36, Math.floor(ROW_H.value * 0.72)))
const spanY = (i: number) => HEADER_H + i * ROW_H.value + Math.floor((ROW_H.value - spanH.value) / 2)
const svgH  = computed(() => HEADER_H + lanes.value.length * ROW_H.value + 16)


// ── Zoom ─────────────────────────────────────────────────────────────────────
const ZOOM_LEVELS = [
  { v: 0.5, label: '0.5×' }, { v: 1, label: '1×' },
  { v: 2,   label: '2×'   }, { v: 4, label: '4×' },
  { v: 8,   label: '8×'   },
]
const zoom      = ref(1)
const pxPerMs   = computed(() => (2 / 1000) * zoom.value)
const canvasWidth = computed(() => Math.max(800, Math.round(durationMs.value * pxPerMs.value)))
const tsToX     = (ts: number) => (ts - startTs.value) * pxPerMs.value

// ── Lanes ─────────────────────────────────────────────────────────────────────
const lanes = computed(() => {
  const seen = new Set<string>()
  const out: Array<{ name: string; color: string; emoji: string }> = []
  for (const turn of tree.value)
    for (const ch of turn.children)
      if (ch.type === 'droid' && !seen.has(ch.droid_name)) {
        seen.add(ch.droid_name)
        out.push({ name: ch.droid_name, color: ch.droid_color, emoji: ch.droid_emoji })
      }
  return out
})

function laneStats(name: string) {
  let runs = 0, ms = 0
  for (const turn of tree.value)
    for (const ch of turn.children)
      if (ch.type === 'droid' && ch.droid_name === name) { runs++; ms += ch.duration_ms }
  return `${runs} run${runs !== 1 ? 's' : ''} · ${formatMs(ms)}`
}

const totalToolCalls = computed(() => {
  let n = 0
  for (const turn of tree.value)
    for (const ch of turn.children)
      if (ch.type === 'droid') n += ch.tools.length
  return n
})

// ── Spans ─────────────────────────────────────────────────────────────────────
function spansFor(li: number) {
  const name = lanes.value[li].name
  const color = lanes.value[li].color
  const out: Array<{ id: string; x1: number; w: number; color: string; label: string }> = []
  for (const turn of tree.value)
    for (const ch of turn.children)
      if (ch.type === 'droid' && ch.droid_name === name) {
        const x1 = tsToX(ch.start_ts), x2 = tsToX(ch.end_ts)
        out.push({ id: ch.id, x1, w: Math.max(x2 - x1, 4), color, label: formatMs(ch.duration_ms) })
      }
  return out
}

// ── Tools ─────────────────────────────────────────────────────────────────────
const TC: Record<string, string> = {
  Read:'#64748b', Write:'#94a3b8', Edit:'#94a3b8', Glob:'#475569', Grep:'#475569',
  Bash:'#34d399', WebFetch:'#60a5fa', WebSearch:'#60a5fa', Skill:'#a855f7', Task:'#f59e0b',
}
function tc(name: string) {
  if (TC[name]) return TC[name]
  if (name.startsWith('mcp__atlassian')) return '#06b6d4'
  if (name.startsWith('mcp__redshift'))  return '#10b981'
  if (name.startsWith('mcp__'))          return '#67e8f9'
  return '#6b7280'
}
function toolW(name: string) {
  if (name === 'Task' || name === 'Skill') return 20
  if (name.startsWith('mcp__'))            return 18
  if (name === 'Bash')                     return 16
  return 12
}
function toolAbbr(name: string) {
  if (name === 'Task')      return '⬡'
  if (name === 'Skill')     return '⚡'
  if (name === 'Bash')      return '$'
  if (name === 'Read')      return 'R'
  if (name === 'Write')     return 'W'
  if (name === 'Edit')      return 'E'
  if (name === 'Grep')      return 'Gr'
  if (name === 'Glob')      return 'Gl'
  if (name.startsWith('mcp__atlassian')) return 'At'
  if (name.startsWith('mcp__redshift'))  return 'RS'
  if (name.startsWith('mcp__'))          return 'M'
  return '·'
}

function toolsFor(li: number) {
  const name = lanes.value[li].name
  const out: Array<{ x: number; w: number; color: string; abbr: string; name: string; detail: string }> = []
  for (const turn of tree.value)
    for (const ch of turn.children)
      if (ch.type === 'droid' && ch.droid_name === name)
        for (const tool of ch.tools) {
          const w = Math.max(toolW(tool.event.tool_name) * zoom.value, 10)
          out.push({
            x: tsToX(tool.event.timestamp),
            w,
            color: tc(tool.event.tool_name),
            abbr: toolAbbr(tool.event.tool_name),
            name: tool.label,
            detail: tool.sublabel?.slice(0, 80) ?? '',
          })
        }
  return out
}

// ── Time ticks ─────────────────────────────────────────────────────────────────
const NICE = [500,1000,2000,5000,10000,15000,30000,60000,120000,300000,600000,1200000,3600000]
const timeTicks = computed(() => {
  const step = NICE.find(n => n >= 100 / pxPerMs.value) ?? NICE[NICE.length - 1]
  const ticks: { x: number; ts: number; label: string }[] = []
  for (let t = 0; t <= durationMs.value; t += step)
    ticks.push({ x: tsToX(startTs.value + t), ts: t, label: formatMs(t) })
  return ticks
})

// ── Prompt markers ─────────────────────────────────────────────────────────────
const promptMarkers = computed(() =>
  sorted.value
    .filter(e => e.hook_event_type === 'UserPromptSubmit')
    .map(e => ({ x: tsToX(e.timestamp), preview: (e.payload?.prompt_preview as string) ?? '' }))
)
const promptSections = computed(() => {
  const xs = promptMarkers.value.map(p => p.x)
  return xs.map((x1, i) => ({ x1, w: (xs[i + 1] ?? canvasWidth.value) - x1 }))
})

// ── Legend ─────────────────────────────────────────────────────────────────────
const LEGEND = [
  { label: 'Droid run', color: '#6366f1' }, { label: 'MCP', color: '#06b6d4' },
  { label: 'Bash', color: '#34d399' }, { label: 'Skill', color: '#a855f7' },
  { label: 'Task', color: '#f59e0b' }, { label: 'File', color: '#64748b' },
]

const chartEl = ref<HTMLElement | null>(null)
</script>
