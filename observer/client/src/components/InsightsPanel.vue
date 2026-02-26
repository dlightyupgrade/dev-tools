<template>
  <div class="flex-1 overflow-y-auto p-6 space-y-8">

    <!-- Empty state -->
    <div v-if="!overview.sessions" class="flex flex-col items-center justify-center h-64 text-center">
      <div class="text-4xl mb-3">📊</div>
      <div class="text-gray-500 text-sm">No sessions tracked yet.<br>Start working and insights will appear here.</div>
    </div>

    <template v-else>

      <!-- Overview KPIs -->
      <section>
        <h2 class="section-heading">Overview</h2>
        <div class="grid grid-cols-2 lg:grid-cols-5 gap-3">
          <div class="kpi-card">
            <div class="kpi-value">{{ overview.sessions }}</div>
            <div class="kpi-label">Sessions</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-value">{{ overview.events }}</div>
            <div class="kpi-label">Events</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-value">{{ formatMs(overview.totalWallMs) }}</div>
            <div class="kpi-label">Total Time</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-value">{{ overview.droidInvocations }}</div>
            <div class="kpi-label">Droid Runs</div>
          </div>
          <div class="kpi-card">
            <div class="kpi-value">{{ overview.toolCalls }}</div>
            <div class="kpi-label">Tool Calls</div>
          </div>
        </div>
      </section>

      <!-- Two-column layout for leaderboards -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">

        <!-- Droid leaderboard -->
        <section v-if="droidLeaderboard.length">
          <h2 class="section-heading">Droid Activity</h2>
          <div class="space-y-2">
            <div v-for="d in droidLeaderboard" :key="d.name" class="flex items-center gap-3">
              <span class="text-sm w-5 text-center flex-shrink-0">{{ d.emoji }}</span>
              <span class="text-xs font-mono w-40 truncate flex-shrink-0" :style="{ color: d.color }">{{ d.name }}</span>
              <div class="flex-1 h-1.5 bg-gray-800 rounded-full overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: d.pct + '%', backgroundColor: d.color }" />
              </div>
              <span class="text-xs font-mono text-gray-500 w-8 text-right flex-shrink-0">{{ d.count }}</span>
            </div>
          </div>
        </section>

        <!-- Skill frequency -->
        <section v-if="skillFrequency.length">
          <h2 class="section-heading">Workflow Frequency</h2>
          <div class="space-y-2">
            <div v-for="s in skillFrequency" :key="s.skill" class="flex items-center gap-3">
              <span class="text-xs text-purple-400 font-mono w-44 truncate flex-shrink-0">⚡ /{{ s.skill }}</span>
              <div class="flex-1 h-1.5 bg-gray-800 rounded-full overflow-hidden">
                <div class="h-full rounded-full bg-purple-500" :style="{ width: s.pct + '%' }" />
              </div>
              <span class="text-xs font-mono text-gray-500 w-8 text-right flex-shrink-0">{{ s.count }}</span>
            </div>
          </div>
        </section>

        <!-- Tool breakdown -->
        <section v-if="toolBreakdown.length">
          <h2 class="section-heading">Tool Breakdown</h2>
          <div class="space-y-2">
            <div v-for="t in toolBreakdown" :key="t.name" class="flex items-center gap-3">
              <span class="text-xs font-mono w-36 truncate flex-shrink-0" :style="{ color: t.color }">{{ t.name }}</span>
              <div class="flex-1 h-1.5 bg-gray-800 rounded-full overflow-hidden">
                <div class="h-full rounded-full" :style="{ width: t.pct + '%', backgroundColor: t.color }" />
              </div>
              <span class="text-xs font-mono text-gray-500 w-14 text-right flex-shrink-0">{{ t.count }} <span class="text-gray-700">{{ t.share }}</span></span>
            </div>
          </div>
        </section>

        <!-- Ticket leaderboard -->
        <section v-if="ticketLeaderboard.length">
          <h2 class="section-heading">Most Active Tickets</h2>
          <div class="space-y-2">
            <div v-for="t in ticketLeaderboard" :key="t.ticket" class="flex items-center gap-3">
              <span class="text-xs text-blue-400 font-mono w-24 flex-shrink-0">{{ t.ticket }}</span>
              <div class="flex-1 text-xs text-gray-600">{{ t.sessions }} session{{ t.sessions > 1 ? 's' : '' }}</div>
            </div>
          </div>
        </section>

      </div>

      <!-- Activity by day (last 14 days) -->
      <section>
        <h2 class="section-heading">Activity — Last 14 Days</h2>
        <div class="flex items-end gap-1.5">
          <div
            v-for="day in activityByDay"
            :key="day.date"
            class="flex-1 flex flex-col items-center gap-1.5"
            :title="`${day.date}: ${day.count} session${day.count !== 1 ? 's' : ''}${day.durationMs ? ' · ' + formatMs(day.durationMs) : ''}`"
          >
            <div
              class="w-full rounded"
              :style="{
                height: '40px',
                backgroundColor: day.count > 0
                  ? `rgba(99,102,241,${0.2 + day.intensity * 0.8})`
                  : 'rgba(255,255,255,0.04)',
                border: day.count > 0 ? `1px solid rgba(129,140,248,${0.2 + day.intensity * 0.5})` : '1px solid rgba(255,255,255,0.06)'
              }"
            />
            <span
              class="text-xs font-mono leading-none"
              :class="day.count > 0 ? 'text-gray-400' : 'text-gray-700'"
              style="font-size: 9px; white-space: nowrap"
            >{{ day.count > 0 ? day.count : '·' }}</span>
          </div>
        </div>
        <div class="flex items-center justify-between mt-1">
          <span class="text-xs text-gray-700">{{ activityByDay[0]?.date }}</span>
          <span class="text-xs text-gray-700">Today</span>
        </div>
      </section>

      <!-- Top sessions -->
      <div class="grid grid-cols-1 lg:grid-cols-2 gap-8">

        <section>
          <h2 class="section-heading">Most Active Sessions</h2>
          <div class="space-y-2">
            <div
              v-for="sess in topSessionsByEvents"
              :key="sess.session_id"
              class="flex items-center gap-3 p-2.5 rounded-lg bg-gray-900 border border-gray-800 cursor-pointer hover:border-gray-700 transition-colors"
              @click="$emit('select', sess.session_id)"
            >
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-0.5">
                  <span v-if="sess.skill_name" class="text-xs text-purple-400 font-mono">⚡ /{{ sess.skill_name }}</span>
                  <span v-if="sess.ticket_id" class="text-xs text-blue-400 font-mono">{{ sess.ticket_id }}</span>
                </div>
                <div v-if="sess.first_prompt" class="text-xs text-gray-600 truncate">{{ sess.first_prompt }}</div>
              </div>
              <div class="text-right flex-shrink-0">
                <div class="text-xs font-mono text-gray-400">{{ sess.event_count }} events</div>
                <div class="text-xs text-gray-600">{{ formatMs(sess.end_ts - sess.start_ts) }}</div>
              </div>
            </div>
          </div>
        </section>

        <section>
          <h2 class="section-heading">Longest Sessions</h2>
          <div class="space-y-2">
            <div
              v-for="sess in topSessionsByDuration"
              :key="sess.session_id"
              class="flex items-center gap-3 p-2.5 rounded-lg bg-gray-900 border border-gray-800 cursor-pointer hover:border-gray-700 transition-colors"
              @click="$emit('select', sess.session_id)"
            >
              <div class="flex-1 min-w-0">
                <div class="flex items-center gap-2 mb-0.5">
                  <span v-if="sess.skill_name" class="text-xs text-purple-400 font-mono">⚡ /{{ sess.skill_name }}</span>
                  <span v-if="sess.ticket_id" class="text-xs text-blue-400 font-mono">{{ sess.ticket_id }}</span>
                </div>
                <div v-if="sess.first_prompt" class="text-xs text-gray-600 truncate">{{ sess.first_prompt }}</div>
              </div>
              <div class="text-right flex-shrink-0">
                <div class="text-xs font-mono text-indigo-400">{{ formatMs(sess.end_ts - sess.start_ts) }}</div>
                <div class="text-xs text-gray-600">{{ sess.event_count }} events</div>
              </div>
            </div>
          </div>
        </section>

      </div>

    </template>
  </div>
</template>

<script setup lang="ts">
import { useInsights } from '../composables/useInsights'

defineEmits<{ select: [sessionId: string] }>()

const { overview, droidLeaderboard, skillFrequency, toolBreakdown, activityByDay, ticketLeaderboard, topSessionsByEvents, topSessionsByDuration, formatMs } = useInsights()
</script>

<style scoped>
.section-heading {
  @apply text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3;
}
.kpi-card {
  @apply bg-gray-900 border border-gray-800 rounded-lg p-4 text-center;
}
.kpi-value {
  @apply text-xl font-bold text-white font-mono;
}
.kpi-label {
  @apply text-xs text-gray-500 mt-1;
}
</style>
