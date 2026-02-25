import { computed } from 'vue'
import { useEventsStore } from '../stores/events'

export function useFilters() {
  const store = useEventsStore()

  const activeFilterCount = computed(() => {
    return Object.values(store.filters).filter(Boolean).length
  })

  return {
    filters: store.filters,
    filterOptions: store.filterOptions,
    filteredEvents: store.filteredEvents,
    activeFilterCount,
    setFilter: store.setFilter,
    clearFilters: store.clearFilters,
  }
}
