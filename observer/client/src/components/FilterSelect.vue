<template>
  <div>
    <label class="block text-xs text-gray-500 mb-1">{{ label }}</label>
    <select
      :value="value"
      @change="emit('change', ($event.target as HTMLSelectElement).value)"
      class="w-full bg-gray-800 border border-gray-700 text-gray-200 text-xs rounded px-2 py-1.5 focus:outline-none focus:border-purple-500"
    >
      <option value="">All</option>
      <option v-for="opt in options" :key="opt" :value="opt">{{ opt }}</option>
    </select>
  </div>
</template>

<script setup lang="ts">
defineProps<{
  label: string
  options: string[]
  value: string
}>()

const emit = defineEmits<{
  change: [value: string]
}>()
</script>
