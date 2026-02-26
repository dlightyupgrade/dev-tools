<template>
  <span>
    <template v-for="(seg, i) in segments" :key="i">
      <a
        v-if="seg.isUrl"
        :href="seg.text"
        target="_blank"
        rel="noopener noreferrer"
        class="text-blue-400 hover:text-blue-300 underline underline-offset-2 break-all"
        @click.stop
      >{{ seg.text }}</a>
      <span v-else>{{ seg.text }}</span>
    </template>
  </span>
</template>

<script setup lang="ts">
import { computed } from 'vue'

const props = defineProps<{ text: string }>()

const URL_RE = /https?:\/\/[^\s<>"')\]]+/g

const segments = computed(() => {
  const result: Array<{ text: string; isUrl: boolean }> = []
  const str = props.text
  let lastIndex = 0
  URL_RE.lastIndex = 0
  let match: RegExpExecArray | null
  while ((match = URL_RE.exec(str)) !== null) {
    if (match.index > lastIndex) {
      result.push({ text: str.slice(lastIndex, match.index), isUrl: false })
    }
    result.push({ text: match[0], isUrl: true })
    lastIndex = URL_RE.lastIndex
  }
  if (lastIndex < str.length) {
    result.push({ text: str.slice(lastIndex), isUrl: false })
  }
  return result
})
</script>
