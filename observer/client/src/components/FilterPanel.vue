<template>
  <div class="p-4 space-y-4">
    <div class="flex items-center justify-between">
      <h2 class="text-xs font-semibold text-gray-400 uppercase tracking-wider">Filters</h2>
      <button
        v-if="activeFilterCount > 0"
        @click="clearFilters"
        class="text-xs text-purple-400 hover:text-purple-300 transition-colors"
      >
        Clear ({{ activeFilterCount }})
      </button>
    </div>

    <FilterSelect
      label="Session"
      :options="filterOptions.sessions"
      :value="filters.session"
      @change="val => setFilter('session', val)"
    />

    <FilterSelect
      label="Droid"
      :options="filterOptions.droids"
      :value="filters.droid"
      @change="val => setFilter('droid', val)"
    />

    <FilterSelect
      label="Skill"
      :options="filterOptions.skills"
      :value="filters.skill"
      @change="val => setFilter('skill', val)"
    />

    <FilterSelect
      label="Event Type"
      :options="filterOptions.event_types"
      :value="filters.event_type"
      @change="val => setFilter('event_type', val)"
    />
  </div>
</template>

<script setup lang="ts">
import { computed } from 'vue'
import { storeToRefs } from 'pinia'
import FilterSelect from './FilterSelect.vue'
import { useEventsStore } from '../stores/events'

const store = useEventsStore()
const { filters, filterOptions } = storeToRefs(store)

const activeFilterCount = computed(() =>
  Object.values(filters.value).filter(Boolean).length
)

function setFilter(key: string, val: string) {
  store.setFilter(key as any, val)
}

function clearFilters() {
  store.clearFilters()
}
</script>
