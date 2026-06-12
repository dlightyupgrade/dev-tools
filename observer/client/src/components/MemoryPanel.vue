<template>
  <div class="flex-1 flex overflow-hidden">

    <!-- Left: memory list -->
    <div class="w-72 flex flex-col border-r border-gray-800 flex-shrink-0 overflow-hidden">
      <!-- Search + actions -->
      <div class="p-3 border-b border-gray-800 space-y-2">
        <input
          v-model="search"
          type="text"
          placeholder="Search memories…"
          class="w-full text-xs bg-gray-800 border border-gray-700 rounded px-2.5 py-1.5 text-gray-300 placeholder-gray-600 focus:outline-none focus:border-indigo-500"
        />
        <!-- Type filters -->
        <div class="flex flex-wrap gap-1">
          <button
            v-for="t in ['all', 'feedback', 'project', 'reference', 'user']"
            :key="t"
            class="text-xs px-2 py-0.5 rounded font-medium transition-colors"
            :class="typeFilter === t ? typeChipActive(t) : 'bg-gray-800 text-gray-500 hover:text-gray-300'"
            @click="typeFilter = t"
          >{{ t === 'all' ? 'All' : t }}</button>
        </div>
      </div>

      <!-- Memory count + merge button -->
      <div class="flex items-center justify-between px-3 py-1.5 border-b border-gray-800">
        <span class="text-xs text-gray-600">{{ filtered.length }} memories</span>
        <button
          v-if="selected.size === 2"
          class="text-xs px-2 py-0.5 rounded bg-amber-600 hover:bg-amber-500 text-white font-medium transition-colors"
          @click="startMerge"
        >⇌ Merge {{ selected.size }}</button>
        <button
          v-else-if="selectMode"
          class="text-xs px-2 py-0.5 rounded bg-gray-700 hover:bg-gray-600 text-gray-300 transition-colors"
          @click="cancelSelect"
        >Cancel</button>
        <button
          v-else
          class="text-xs px-2 py-0.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-500 transition-colors"
          @click="selectMode = true"
        >Select</button>
      </div>

      <!-- List -->
      <div class="flex-1 overflow-y-auto">
        <div
          v-for="m in filtered"
          :key="m.slug"
          class="flex items-start gap-2 px-3 py-2.5 cursor-pointer border-b border-gray-800/50 transition-colors group"
          :class="[
            activeSlug === m.slug ? 'bg-gray-800' : 'hover:bg-gray-900',
            selected.has(m.slug) ? 'ring-1 ring-inset ring-amber-600/40' : ''
          ]"
          @click="selectMode ? toggleSelect(m.slug) : loadMemory(m.slug)"
        >
          <!-- Checkbox in select mode -->
          <div v-if="selectMode" class="mt-0.5 flex-shrink-0">
            <div
              class="w-3.5 h-3.5 rounded border transition-colors"
              :class="selected.has(m.slug) ? 'bg-amber-600 border-amber-600' : 'border-gray-600'"
            />
          </div>

          <div class="flex-1 min-w-0">
            <div class="flex items-center gap-1.5 mb-0.5">
              <span class="text-xs font-mono" :class="typeColor(m.type)">{{ typeIcon(m.type) }}</span>
              <span class="text-xs text-gray-300 truncate font-medium">{{ m.name || m.slug }}</span>
            </div>
            <div class="text-xs text-gray-600 truncate leading-relaxed">{{ m.description }}</div>
            <div class="text-xs text-gray-700 mt-0.5">{{ m.age_days }}d ago · {{ formatSize(m.size) }}</div>
          </div>
        </div>

        <div v-if="filtered.length === 0" class="p-6 text-center text-gray-600 text-xs">
          No memories match your filter.
        </div>
      </div>
    </div>

    <!-- Center: memory content -->
    <div class="flex-1 flex flex-col overflow-hidden">
      <!-- Header bar -->
      <div class="flex items-center gap-3 px-4 py-2.5 border-b border-gray-800 flex-shrink-0">
        <template v-if="activeMemory">
          <span class="text-xs font-mono font-semibold text-white">{{ activeMemory.name || activeMemory.slug }}</span>
          <span class="text-xs px-1.5 py-0.5 rounded font-medium" :class="typeChipActive(activeMemory.type)">{{ activeMemory.type }}</span>
          <span class="text-xs text-gray-600">{{ activeMemory.age_days }}d ago</span>
          <div class="flex-1" />
          <button
            v-if="!editing"
            class="text-xs px-2 py-1 rounded bg-gray-800 hover:bg-gray-700 text-gray-400 hover:text-white transition-colors"
            @click="startEdit"
          >Edit</button>
          <button
            v-if="editing"
            class="text-xs px-2 py-1 rounded bg-indigo-600 hover:bg-indigo-500 text-white transition-colors"
            @click="saveEdit"
          >Save</button>
          <button
            v-if="editing"
            class="text-xs px-2 py-1 rounded bg-gray-800 hover:bg-gray-700 text-gray-400 transition-colors"
            @click="cancelEdit"
          >Cancel</button>
          <button
            class="text-xs px-2 py-1 rounded bg-gray-800 hover:bg-red-900 text-gray-500 hover:text-red-400 transition-colors"
            @click="confirmDelete"
          >Delete</button>
        </template>
        <template v-else>
          <span class="text-xs text-gray-600">Select a memory to view</span>
          <div class="flex-1" />
        </template>

        <!-- Dream button always visible -->
        <button
          class="flex items-center gap-1.5 text-xs px-3 py-1.5 rounded font-semibold transition-colors flex-shrink-0"
          :class="dreaming ? 'bg-violet-700 text-white' : 'bg-gray-800 hover:bg-violet-800 text-gray-300 hover:text-white'"
          @click="toggleDream"
        >
          {{ dreaming ? '⏸ Dreaming…' : '🌙 Dream' }}
        </button>

        <!-- Export button -->
        <button
          class="text-xs px-2 py-1.5 rounded bg-gray-800 hover:bg-gray-700 text-gray-400 hover:text-white transition-colors flex-shrink-0"
          title="Export all memories as JSON"
          @click="exportMemories"
        >↓ Export</button>
      </div>

      <!-- Content area -->
      <div v-if="activeMemory" class="flex-1 overflow-y-auto p-5">
        <textarea
          v-if="editing"
          v-model="editBody"
          class="w-full h-full min-h-96 text-xs font-mono bg-gray-900 border border-gray-700 rounded p-3 text-gray-300 focus:outline-none focus:border-indigo-500 resize-none"
        />
        <pre v-else class="text-xs text-gray-300 font-mono whitespace-pre-wrap leading-relaxed">{{ activeMemory.body }}</pre>
      </div>

      <!-- Empty state -->
      <div v-else class="flex-1 flex items-center justify-center text-center">
        <div>
          <div class="text-4xl mb-3">🧠</div>
          <div class="text-gray-600 text-sm">{{ memories.length }} memories stored</div>
          <div class="text-gray-700 text-xs mt-1">Select a memory to view its content</div>
          <div class="text-gray-700 text-xs mt-3">or click <span class="text-violet-400">🌙 Dream</span> to analyze patterns</div>
        </div>
      </div>
    </div>

    <!-- Right: Dream / Merge panel -->
    <Transition name="slide-right">
      <div v-if="showRightPanel" class="w-96 border-l border-gray-800 flex flex-col flex-shrink-0 overflow-hidden">

        <!-- Dream panel -->
        <template v-if="dreamMode">
          <div class="flex items-center justify-between px-4 py-2.5 border-b border-gray-800 flex-shrink-0">
            <span class="text-xs font-semibold text-violet-300">🌙 Dream Analysis</span>
            <button class="text-gray-600 hover:text-gray-400 text-sm" @click="closeDream">✕</button>
          </div>
          <div ref="dreamScroll" class="flex-1 overflow-y-auto p-4">
            <pre
              v-if="dreamOutput"
              class="text-xs text-gray-300 font-mono whitespace-pre-wrap leading-relaxed"
            >{{ dreamOutput }}</pre>
            <div v-else-if="dreaming" class="flex items-center gap-2 text-xs text-violet-400">
              <span class="animate-pulse">●</span> Analyzing {{ memories.length }} memories…
            </div>
            <div v-else class="text-xs text-gray-600">Dream output will appear here.</div>
          </div>
        </template>

        <!-- Merge panel -->
        <template v-else-if="mergeMode">
          <div class="flex items-center justify-between px-4 py-2.5 border-b border-gray-800 flex-shrink-0">
            <span class="text-xs font-semibold text-amber-300">⇌ Merge Memories</span>
            <button class="text-gray-600 hover:text-gray-400 text-sm" @click="cancelMerge">✕</button>
          </div>
          <div class="flex-1 overflow-y-auto p-4 space-y-4">
            <!-- Selected memories -->
            <div class="space-y-2">
              <div v-for="slug in [...selected]" :key="slug" class="text-xs text-gray-400 bg-gray-800 rounded px-2.5 py-1.5 font-mono">
                {{ slug }}
              </div>
            </div>

            <div v-if="merging" class="flex items-center gap-2 text-xs text-amber-400">
              <span class="animate-pulse">●</span> Generating merged memory…
            </div>

            <div v-if="mergeResult" class="space-y-3">
              <div class="text-xs text-gray-500 font-semibold">Suggested merge:</div>
              <pre class="text-xs text-gray-300 font-mono whitespace-pre-wrap leading-relaxed bg-gray-800 rounded p-3">{{ mergeResult.merged_body }}</pre>
              <div class="flex gap-2">
                <button
                  class="flex-1 text-xs py-1.5 rounded bg-amber-600 hover:bg-amber-500 text-white font-medium transition-colors"
                  @click="applyMerge"
                >Apply Merge</button>
                <button
                  class="text-xs px-3 py-1.5 rounded bg-gray-700 hover:bg-gray-600 text-gray-300 transition-colors"
                  @click="mergeResult = null"
                >Discard</button>
              </div>
              <div class="text-xs text-gray-600">
                Will update <span class="text-amber-400 font-mono">{{ mergeResult.target_slug }}</span>
                and delete <span class="text-red-400 font-mono">{{ mergeResult.source_slug }}</span>.
              </div>
            </div>

            <button
              v-if="!merging && !mergeResult"
              class="w-full text-xs py-1.5 rounded bg-amber-600 hover:bg-amber-500 text-white font-medium transition-colors"
              @click="runMerge"
            >Generate Merge →</button>
          </div>
        </template>

      </div>
    </Transition>

  </div>
</template>

<script setup lang="ts">
import { ref, computed, onMounted, nextTick, watch } from 'vue'

const SERVER = 'http://localhost:4001'

interface MemorySummary {
  slug: string
  name: string
  description: string
  type: string
  age_days: number
  size: number
}

interface MemoryDetail extends MemorySummary {
  body: string
}

interface MergeResult {
  merged_body: string
  source_slug: string
  target_slug: string
}

// State
const memories = ref<MemorySummary[]>([])
const activeSlug = ref<string | null>(null)
const activeMemory = ref<MemoryDetail | null>(null)
const search = ref('')
const typeFilter = ref('all')
const selectMode = ref(false)
const selected = ref<Set<string>>(new Set())
const editing = ref(false)
const editBody = ref('')

// Dream state
const dreamMode = ref(false)
const dreaming = ref(false)
const dreamOutput = ref('')
const dreamScroll = ref<HTMLElement | null>(null)

// Merge state
const mergeMode = ref(false)
const merging = ref(false)
const mergeResult = ref<MergeResult | null>(null)

const showRightPanel = computed(() => dreamMode.value || mergeMode.value)

// Filtering
const filtered = computed(() => {
  return memories.value.filter(m => {
    const matchType = typeFilter.value === 'all' || m.type === typeFilter.value
    const q = search.value.toLowerCase()
    const matchSearch = !q || m.slug.includes(q) || m.name.toLowerCase().includes(q) || m.description.toLowerCase().includes(q)
    return matchType && matchSearch
  })
})

// Type helpers
function typeColor(t: string): string {
  switch (t) {
    case 'feedback': return 'text-indigo-400'
    case 'project': return 'text-emerald-400'
    case 'reference': return 'text-cyan-400'
    case 'user': return 'text-amber-400'
    default: return 'text-gray-500'
  }
}

function typeIcon(t: string): string {
  switch (t) {
    case 'feedback': return '↺'
    case 'project': return '◆'
    case 'reference': return '◎'
    case 'user': return '◉'
    default: return '·'
  }
}

function typeChipActive(t: string): string {
  switch (t) {
    case 'feedback': return 'bg-indigo-900/60 text-indigo-300'
    case 'project': return 'bg-emerald-900/60 text-emerald-300'
    case 'reference': return 'bg-cyan-900/60 text-cyan-300'
    case 'user': return 'bg-amber-900/60 text-amber-300'
    case 'all': return 'bg-gray-700 text-white'
    default: return 'bg-gray-700 text-gray-300'
  }
}

function formatSize(bytes: number): string {
  if (bytes < 1024) return `${bytes}B`
  return `${(bytes / 1024).toFixed(1)}KB`
}

// Load list
async function fetchMemories() {
  const res = await fetch(`${SERVER}/memory`)
  memories.value = await res.json()
}

// Load single memory
async function loadMemory(slug: string) {
  if (activeSlug.value === slug) return
  activeSlug.value = slug
  editing.value = false
  const res = await fetch(`${SERVER}/memory/${slug}`)
  activeMemory.value = await res.json()
}

// Edit
function startEdit() {
  editBody.value = activeMemory.value?.body ?? ''
  editing.value = true
}

async function saveEdit() {
  if (!activeSlug.value) return
  await fetch(`${SERVER}/memory/${activeSlug.value}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ body: editBody.value }),
  })
  if (activeMemory.value) activeMemory.value.body = editBody.value
  editing.value = false
}

function cancelEdit() {
  editing.value = false
}

// Delete
async function confirmDelete() {
  if (!activeSlug.value) return
  if (!confirm(`Delete memory "${activeSlug.value}"? This cannot be undone.`)) return
  await fetch(`${SERVER}/memory/${activeSlug.value}`, { method: 'DELETE' })
  memories.value = memories.value.filter(m => m.slug !== activeSlug.value)
  activeSlug.value = null
  activeMemory.value = null
}

// Select mode
function toggleSelect(slug: string) {
  const next = new Set(selected.value)
  if (next.has(slug)) {
    next.delete(slug)
  } else if (next.size < 2) {
    next.add(slug)
  }
  selected.value = next
}

function cancelSelect() {
  selectMode.value = false
  selected.value = new Set()
}

// Dream
function toggleDream() {
  if (dreamMode.value) {
    closeDream()
  } else {
    dreamMode.value = true
    mergeMode.value = false
    if (!dreaming.value) startDream()
  }
}

function closeDream() {
  dreamMode.value = false
  dreaming.value = false
}

async function startDream() {
  dreaming.value = true
  dreamOutput.value = ''
  try {
    const res = await fetch(`${SERVER}/memory/dream`)
    const reader = res.body?.getReader()
    if (!reader) return
    const decoder = new TextDecoder()
    let buf = ''
    while (true) {
      const { value, done } = await reader.read()
      if (done) break
      buf += decoder.decode(value, { stream: true })
      const lines = buf.split('\n')
      buf = lines.pop() ?? ''
      for (const line of lines) {
        if (!line.startsWith('data: ')) continue
        try {
          const msg = JSON.parse(line.slice(6))
          if (msg.text) {
            dreamOutput.value += msg.text
            await nextTick()
            if (dreamScroll.value) {
              dreamScroll.value.scrollTop = dreamScroll.value.scrollHeight
            }
          }
          if (msg.done || msg.error) break
        } catch {}
      }
    }
  } finally {
    dreaming.value = false
  }
}

// Merge
function startMerge() {
  mergeMode.value = true
  dreamMode.value = false
  mergeResult.value = null
}

function cancelMerge() {
  mergeMode.value = false
  mergeResult.value = null
  cancelSelect()
}

async function runMerge() {
  const [source, target] = [...selected.value]
  merging.value = true
  try {
    const res = await fetch(`${SERVER}/memory/merge`, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ source, target }),
    })
    mergeResult.value = await res.json()
  } finally {
    merging.value = false
  }
}

async function applyMerge() {
  if (!mergeResult.value) return
  // Save merged body into target
  await fetch(`${SERVER}/memory/${mergeResult.value.target_slug}`, {
    method: 'PUT',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ body: mergeResult.value.merged_body }),
  })
  // Delete source
  await fetch(`${SERVER}/memory/${mergeResult.value.source_slug}`, { method: 'DELETE' })
  await fetchMemories()
  cancelMerge()
  if (activeSlug.value === mergeResult.value.source_slug) {
    activeSlug.value = null
    activeMemory.value = null
  }
}

// Export
async function exportMemories() {
  const res = await fetch(`${SERVER}/memory/export`)
  const data = await res.json()
  const blob = new Blob([JSON.stringify(data, null, 2)], { type: 'application/json' })
  const url = URL.createObjectURL(blob)
  const a = document.createElement('a')
  a.href = url
  a.download = `memories-${new Date().toISOString().slice(0, 10)}.json`
  a.click()
  URL.revokeObjectURL(url)
}

onMounted(fetchMemories)
</script>

<style scoped>
.section-heading {
  @apply text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3;
}
</style>
