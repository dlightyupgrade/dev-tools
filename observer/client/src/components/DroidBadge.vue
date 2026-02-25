<template>
  <span
    class="inline-flex items-center gap-1 px-2 py-0.5 rounded-full text-xs font-semibold font-mono tracking-wide"
    :style="{ backgroundColor: bgColor, color: '#fff', borderColor: props.color, border: '1px solid' }"
  >
    {{ props.emoji }} {{ props.name }}
  </span>
</template>

<script setup lang="ts">
const props = defineProps<{
  name: string
  color: string
  emoji: string
}>()

// Darken color slightly for background to maintain contrast
const bgColor = computed(() => props.color + '33') // 20% opacity

import { computed } from 'vue'
</script>
