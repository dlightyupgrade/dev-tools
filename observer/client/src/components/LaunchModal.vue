<template>
  <Teleport to="body">
    <div
      class="fixed inset-0 bg-black/60 backdrop-blur-sm flex items-center justify-center z-50"
      @click.self="$emit('close')"
      @keydown.esc="$emit('close')"
    >
      <div class="bg-gray-900 border border-gray-700 rounded-xl shadow-2xl w-full max-w-lg mx-4">
        <!-- Header -->
        <div class="flex items-center justify-between px-5 py-4 border-b border-gray-800">
          <div class="flex items-center gap-2">
            <span class="text-sm font-semibold text-white">Launch New Session</span>
            <span class="text-xs text-gray-600 font-mono">wclds</span>
          </div>
          <button class="text-gray-600 hover:text-gray-400 transition-colors" @click="$emit('close')">✕</button>
        </div>

        <!-- Body -->
        <div class="px-5 py-4">
          <label class="text-xs text-gray-500 mb-2 block">Prompt / task</label>
          <textarea
            ref="inputEl"
            v-model="cmd"
            rows="3"
            placeholder="e.g. implement SI-10031 using quick-ticket workflow"
            class="w-full bg-gray-800 border border-gray-700 rounded-lg px-3 py-2.5 text-sm text-white placeholder-gray-600 font-mono resize-none focus:outline-none focus:border-indigo-500 transition-colors"
            @keydown.enter.exact.prevent="launch"
            @keydown.esc="$emit('close')"
          />
          <p class="text-xs text-gray-700 mt-2">Opens a new iTerm2 tab running <span class="font-mono text-gray-600">claude "your prompt"</span></p>
        </div>

        <!-- Footer -->
        <div class="flex items-center justify-between px-5 py-3 border-t border-gray-800">
          <!-- Quick prompts -->
          <div class="flex items-center gap-2 flex-wrap">
            <button
              v-for="q in quickPrompts"
              :key="q"
              class="text-xs text-gray-500 hover:text-gray-300 font-mono px-2 py-0.5 rounded bg-gray-800 hover:bg-gray-700 transition-colors"
              @click="cmd = q"
            >
              {{ q }}
            </button>
          </div>
          <div class="flex items-center gap-2 flex-shrink-0 ml-3">
            <button
              class="text-xs text-gray-500 hover:text-gray-300 px-3 py-1.5 rounded transition-colors"
              @click="$emit('close')"
            >
              Cancel
            </button>
            <button
              class="text-xs font-semibold px-4 py-1.5 rounded bg-indigo-600 hover:bg-indigo-500 text-white transition-colors disabled:opacity-40 disabled:cursor-not-allowed"
              :disabled="!cmd.trim()"
              @click="launch"
            >
              ⚡ Launch
            </button>
          </div>
        </div>
      </div>
    </div>
  </Teleport>
</template>

<script setup lang="ts">
import { ref, onMounted } from 'vue'

const cmd = ref('')
const inputEl = ref<HTMLTextAreaElement | null>(null)

const quickPrompts = [
  'morning workflow',
  'run prr',
  'pr dashboard',
]

onMounted(() => {
  inputEl.value?.focus()
})

const emit = defineEmits<{ close: [] }>()

async function launch() {
  const text = cmd.value.trim()
  if (!text) return
  await fetch(`http://localhost:4001/launch-new?cmd=${encodeURIComponent(text)}`)
  emit('close')
}
</script>
