<template>
  <div class="flex-1 overflow-y-auto p-6 max-w-4xl mx-auto w-full">
    <h1 class="text-2xl font-bold text-white mb-1">Claude Observer</h1>
    <p class="text-gray-500 text-sm mb-8">Real-time observability for your Claude Code sessions.</p>

    <div class="space-y-8">

      <!-- Server -->
      <section>
        <h2 class="section-title">Server</h2>
        <div class="card">
          <table class="w-full text-sm">
            <tbody class="divide-y divide-gray-800">
              <tr v-for="cmd in serverCommands" :key="cmd.command" class="py-2">
                <td class="py-2 pr-6 w-48"><code class="text-indigo-400 font-mono text-xs">{{ cmd.command }}</code></td>
                <td class="py-2 text-gray-400 text-xs">{{ cmd.desc }}</td>
              </tr>
            </tbody>
          </table>
        </div>
      </section>

      <!-- Keyboard shortcuts -->
      <section>
        <h2 class="section-title">Keyboard Shortcuts</h2>
        <div class="card">
          <div v-for="s in shortcuts" :key="s.key" class="flex items-center justify-between py-2 border-b border-gray-800 last:border-0">
            <span class="text-gray-400 text-sm">{{ s.desc }}</span>
            <div class="flex items-center gap-1">
              <kbd class="kbd" v-for="k in s.keys" :key="k">{{ k }}</kbd>
            </div>
          </div>
        </div>
      </section>

      <!-- Views -->
      <section>
        <h2 class="section-title">Views</h2>
        <div class="grid grid-cols-1 sm:grid-cols-2 gap-3">
          <div v-for="v in views" :key="v.name" class="card">
            <div class="text-sm font-semibold text-white mb-1">{{ v.icon }} {{ v.name }}</div>
            <div class="text-xs text-gray-500">{{ v.desc }}</div>
          </div>
        </div>
      </section>

      <!-- Session tile actions -->
      <section>
        <h2 class="section-title">Session Tile Actions</h2>
        <div class="card">
          <div v-for="a in tileActions" :key="a.label" class="flex items-start gap-4 py-2 border-b border-gray-800 last:border-0">
            <span class="text-indigo-400 font-mono text-sm w-20 flex-shrink-0">{{ a.label }}</span>
            <span class="text-gray-400 text-xs">{{ a.desc }}</span>
          </div>
        </div>
      </section>

      <!-- What's captured -->
      <section>
        <h2 class="section-title">What's Captured</h2>
        <div class="card">
          <div v-for="h in hooks" :key="h.event" class="flex items-start gap-4 py-2 border-b border-gray-800 last:border-0">
            <code class="text-cyan-400 font-mono text-xs w-44 flex-shrink-0 mt-0.5">{{ h.event }}</code>
            <span class="text-gray-400 text-xs">{{ h.desc }}</span>
          </div>
        </div>
        <p class="text-xs text-gray-700 mt-2">
          Not yet captured: PostToolUse (tool durations), subagent-internal tool calls, token usage, model response time.
        </p>
      </section>

      <!-- Launch modal -->
      <section>
        <h2 class="section-title">Launch Modal <span class="text-gray-600 font-normal text-xs ml-2">⌘K</span></h2>
        <div class="card text-xs text-gray-400 space-y-2">
          <p>Opens a new Claude session in a new iTerm2 tab via <code class="text-indigo-400">wclds</code>.</p>
          <p>Quick launchers pre-fill the prompt — add your ticket/PR URL, then ⌘↵ to launch.</p>
          <p>Supports multi-paragraph prompts. The full prompt is passed safely via a temp script file.</p>
        </div>
      </section>

    </div>
  </div>
</template>

<script setup lang="ts">
const serverCommands = [
  { command: 'claude-observer start',     desc: 'Start backend (port 4001) + frontend dev server (port 5173)' },
  { command: 'claude-observer stop',      desc: 'Stop all observer processes' },
  { command: 'claude-observer status',    desc: 'Show running state and URLs' },
  { command: 'claude-observer reset',     desc: 'Clear the event database' },
  { command: 'claude-observer install',   desc: 'Copy hooks to ~/.claude/hooks/ and patch settings.json' },
  { command: 'claude-observer setup',     desc: 'Install Python venv + npm dependencies (first-time setup)' },
]

const shortcuts = [
  { key: '⌘K',      desc: 'Open / close Launch modal',            keys: ['⌘', 'K'] },
  { key: '⌘↵',      desc: 'Submit Launch modal',                   keys: ['⌘', '↵'] },
  { key: 'Esc',      desc: 'Close any modal',                       keys: ['Esc'] },
]

const views = [
  { icon: '📊', name: 'Insights',  desc: 'Cross-session analytics: droid leaderboard, workflow frequency, tool breakdown, 14-day activity heatmap, top sessions.' },
  { icon: '🗂',  name: 'Sessions', desc: 'Grid of session tiles sorted by active/recency. Active sessions have a pulsing green border.' },
  { icon: '🌳', name: 'Tree',     desc: 'Causal tree for a session: prompts → droids → tool calls, all linked. URLs are clickable. SQL queries have ⎘ Copy + ⚡ Run now.' },
  { icon: '🔥', name: 'Timeline', desc: 'Flame chart showing droid activity over time. Zoom 0.5×–8×. Rows fill the available height dynamically.' },
]

const tileActions = [
  { label: 'Click',    desc: 'Open session detail (Tree + Timeline views).' },
  { label: '⤴ Tab',   desc: 'Jump to the iTerm2 tab running this session. Only shown for active sessions. Requires TERM_SESSION_ID captured via hooks.' },
  { label: '↩ Resume', desc: 'Open a new iTerm2 tab and run claude --resume <session_id>. Only shown for ended sessions.' },
  { label: '✕',        desc: 'Forget (delete) this session from the database.' },
]

const hooks = [
  { event: 'SessionStart',     desc: 'Fires on session start or resume. Captures the iTerm2 tab ID (TERM_SESSION_ID) for the ⤴ Tab button.' },
  { event: 'SessionEnd',       desc: 'Fires when session terminates. Records exit reason: prompt_input_exit, clear, logout, or other.' },
  { event: 'UserPromptSubmit', desc: 'Fires when the user submits a prompt. Extracts /skill-name and ticket IDs (SI-XXXX, SD-XXXX). Prompt preview stored (200 chars).' },
  { event: 'SubagentStart',    desc: 'Fires when a Task subagent starts. Records droid name, color, emoji.' },
  { event: 'SubagentStop',     desc: 'Fires when a Task subagent finishes. Used to calculate droid run duration.' },
  { event: 'PreToolUse',       desc: 'Fires before every tool call. Captures tool name + full input (file paths, SQL queries, MCP args, Bash commands, etc.).' },
]
</script>

<style scoped>
.section-title {
  @apply text-xs font-semibold text-gray-500 uppercase tracking-wider mb-3;
}
.card {
  @apply bg-gray-900 border border-gray-800 rounded-lg px-4 py-3;
}
</style>
