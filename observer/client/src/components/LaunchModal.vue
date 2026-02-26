<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50 p-4"
      @click.self="emit('close')"
    >
      <div class="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl flex flex-col w-full max-w-2xl" style="max-height: 90vh">

        <!-- Header -->
        <div class="flex items-center justify-between px-6 py-4 border-b border-gray-800 flex-shrink-0">
          <div class="flex items-center gap-2">
            <span class="text-sm font-semibold text-white">Launch New Session</span>
            <span class="text-xs text-gray-600 font-mono">wclds</span>
          </div>
          <button class="text-gray-600 hover:text-gray-400 transition-colors text-lg leading-none" @click="emit('close')">✕</button>
        </div>

        <!-- Quick launchers -->
        <div class="px-6 py-4 border-b border-gray-800 flex-shrink-0">
          <div class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3">Quick Launch</div>
          <div class="grid grid-cols-2 gap-2">
            <button
              v-for="q in quickLaunchers"
              :key="q.label"
              class="flex items-start gap-3 text-left px-3 py-2.5 rounded-lg border border-gray-800 hover:border-gray-700 hover:bg-gray-800/50 transition-colors group"
              @click="cmd = q.prompt"
            >
              <span class="text-lg flex-shrink-0 mt-0.5">{{ q.icon }}</span>
              <div class="min-w-0">
                <div class="text-xs font-semibold text-gray-300 group-hover:text-white transition-colors">{{ q.label }}</div>
                <div class="text-xs text-gray-600 truncate mt-0.5">{{ q.hint }}</div>
              </div>
            </button>
          </div>
        </div>

        <!-- Prompt textarea -->
        <div class="px-6 py-4 flex-1 flex flex-col min-h-0">
          <label class="text-xs font-semibold text-gray-500 uppercase tracking-wider mb-2 block">Prompt</label>
          <textarea
            ref="inputEl"
            v-model="cmd"
            placeholder="Describe the task in detail. You can include ticket numbers, PR URLs, context — anything you'd type to Claude directly."
            class="flex-1 w-full bg-gray-800 border border-gray-700 rounded-lg px-4 py-3 text-sm text-white placeholder-gray-600 resize-none focus:outline-none focus:border-indigo-500 transition-colors leading-relaxed"
            style="min-height: 160px"
            @keydown.meta.enter.prevent="launch"
            @keydown.esc="emit('close')"
          />
          <p class="text-xs text-gray-700 mt-2 flex items-center gap-3">
            <span><kbd class="kbd">⌘↵</kbd> launch</span>
            <span><kbd class="kbd">Esc</kbd> close</span>
            <span class="ml-auto">opens in new iTerm2 tab · <span class="font-mono">claude "…"</span></span>
          </p>
        </div>

        <!-- Footer -->
        <div class="flex items-center justify-end gap-2 px-6 py-4 border-t border-gray-800 flex-shrink-0">
          <button
            class="text-xs text-gray-500 hover:text-gray-300 px-4 py-2 rounded transition-colors"
            @click="emit('close')"
          >Cancel</button>
          <button
            class="text-sm font-semibold px-5 py-2 rounded-lg bg-indigo-600 hover:bg-indigo-500 text-white transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
            :disabled="!cmd.trim()"
            @click="launch"
          >⚡ Launch</button>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'

const emit = defineEmits<{ close: [] }>()
const cmd = ref('')
const inputEl = ref<HTMLTextAreaElement | null>(null)

onMounted(() => inputEl.value?.focus())

const quickLaunchers = [
  {
    icon: '🩺',
    label: 'PR Health Check',
    hint: 'Analyze PR readiness + inline comments',
    prompt: 'pr health check ',
  },
  {
    icon: '🔍',
    label: 'PR Code Review',
    hint: 'Full code quality review of a PR',
    prompt: 'pr code review ',
  },
  {
    icon: '📋',
    label: 'Quick Ticket',
    hint: 'Implement a Jira ticket end-to-end',
    prompt: 'quick ticket ',
  },
  {
    icon: '🎨',
    label: 'Tech Design',
    hint: 'Create a tech design doc in Confluence',
    prompt: 'tech design for ',
  },
  {
    icon: '📊',
    label: 'PR Dashboard',
    hint: 'Open the full PR pipeline dashboard',
    prompt: 'pr dashboard',
  },
  {
    icon: '🔥',
    label: 'RCA',
    hint: 'Write a root cause analysis / postmortem',
    prompt: 'rca ',
  },
]

async function launch() {
  const text = cmd.value.trim()
  if (!text) return
  await fetch(`http://localhost:4001/launch-new?cmd=${encodeURIComponent(text)}`)
  emit('close')
}
</script>
