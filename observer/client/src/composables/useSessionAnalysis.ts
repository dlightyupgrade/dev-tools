import { computed } from 'vue'
import type { Ref } from 'vue'
import type { ObserverEvent } from '../types/events'

// ── Tree node types ──────────────────────────────────────────────────────────

export interface ToolNode {
  type: 'tool'
  id: string
  event: ObserverEvent
  label: string
  sublabel: string
  color: string
  relTimeSec: number
}

export interface DroidNode {
  type: 'droid'
  id: string
  droid_name: string
  droid_color: string
  droid_emoji: string
  start_ts: number
  end_ts: number
  duration_ms: number
  relTimeSec: number
  tools: ToolNode[]
}

export interface TurnNode {
  type: 'turn'
  id: string
  event: ObserverEvent
  promptPreview: string
  relTimeSec: number
  children: Array<DroidNode | ToolNode>
}

export interface SessionStats {
  duration_ms: number
  prompt_count: number
  droid_rows: Array<{ name: string; color: string; emoji: string; count: number; total_ms: number }>
  mcp_services: Array<{ name: string; count: number }>
  skill_count: number
  task_count: number
  bash_count: number
  web_count: number
  file_ops: Array<{ name: string; count: number }>
  total_tool_calls: number
  total_droid_ms: number
  parallelism: number
}

// ── Tool label extraction ────────────────────────────────────────────────────

function toolLabel(tool_name: string, input: Record<string, unknown>): { label: string; sublabel: string } {
  // Standard Claude Code tools
  const fp = (input.file_path as string) ?? ''
  const filename = fp ? fp.split('/').pop() ?? fp : ''
  if (tool_name === 'Read')      return { label: `Read ${filename}`, sublabel: fp }
  if (tool_name === 'Write')     return { label: `Write ${filename}`, sublabel: fp }
  if (tool_name === 'Edit')      return { label: `Edit ${filename}`, sublabel: fp }
  if (tool_name === 'Glob')      return { label: `Glob`, sublabel: (input.pattern as string) ?? '' }
  if (tool_name === 'Grep')      return { label: `Grep ${(input.pattern as string) ?? ''}`, sublabel: (input.path as string) ?? '' }
  if (tool_name === 'Bash') {
    const desc = (input.description as string) ?? ''
    const cmd = (input.command as string) ?? ''
    return { label: `Bash`, sublabel: desc || cmd.slice(0, 100) }
  }
  if (tool_name === 'WebFetch')  return { label: `Fetch`, sublabel: (input.url as string) ?? '' }
  if (tool_name === 'WebSearch') return { label: `Search`, sublabel: (input.query as string) ?? '' }
  if (tool_name === 'NotebookEdit') return { label: `NotebookEdit`, sublabel: (input.notebook_path as string) ?? '' }

  if (tool_name === 'Task') {
    const desc = (input.description as string) ?? (input.subagent_type as string) ?? 'Task'
    const prompt = (input.prompt as string) ?? ''
    return { label: desc.slice(0, 80), sublabel: prompt.slice(0, 100) }
  }
  if (tool_name === 'Skill') {
    const skill = (input.skill as string) ?? ''
    const args = (input.args as string) ?? ''
    return { label: `/${skill}`, sublabel: args.slice(0, 80) }
  }
  if (tool_name.startsWith('mcp__')) {
    const parts = tool_name.split('__')
    const method = parts[2] ?? tool_name
    const issue = (input.issueIdOrKey as string) ?? ''
    const pageId = (input.pageId as string) ?? ''
    const title = (input.title as string) ?? ''
    const cql = (input.cql as string) ?? ''
    const jql = (input.jql as string) ?? ''

    switch (method) {
      case 'getJiraIssue':
      case 'getJiraIssueRemoteIssueLinks':
      case 'getTransitionsForJiraIssue':
        return { label: `${method.replace(/([A-Z])/g, ' $1').trim()} ${issue}`, sublabel: '' }
      case 'transitionJiraIssue':
        return { label: `Transition ${issue}`, sublabel: '' }
      case 'addCommentToJiraIssue':
        return { label: `Add comment ${issue}`, sublabel: '' }
      case 'searchJiraIssuesUsingJql':
        return { label: 'Search Jira', sublabel: jql.slice(0, 80) }
      case 'searchConfluenceUsingCql':
        return { label: 'Search Confluence', sublabel: cql.slice(0, 80) }
      case 'getConfluencePage':
        return { label: `Get page ${pageId}`, sublabel: title }
      case 'updateConfluencePage':
        return { label: `Update page`, sublabel: title || pageId }
      case 'createConfluencePage':
        return { label: `Create page`, sublabel: title }
      case 'getAccessibleAtlassianResources':
        return { label: 'Get cloud ID', sublabel: '' }
      case 'atlassianUserInfo':
        return { label: 'Get user info', sublabel: '' }
      default: {
        const readable = method.replace(/([A-Z])/g, ' $1').trim()
        return { label: readable, sublabel: issue || pageId }
      }
    }
  }
  return { label: tool_name, sublabel: '' }
}

function toolColor(tool_name: string): string {
  if (tool_name === 'Skill') return '#A855F7'
  if (tool_name === 'Task') return '#F59E0B'
  if (tool_name === 'Bash') return '#34D399'
  if (tool_name === 'WebFetch' || tool_name === 'WebSearch') return '#60A5FA'
  if (tool_name === 'Read' || tool_name === 'Write' || tool_name === 'Edit') return '#9CA3AF'
  if (tool_name === 'Glob' || tool_name === 'Grep') return '#6B7280'
  if (tool_name.startsWith('mcp__atlassian')) return '#06B6D4'
  if (tool_name.startsWith('mcp__redshift')) return '#10B981'
  if (tool_name.startsWith('mcp__')) return '#67E8F9'
  return '#4B5563'
}

// ── Main composable ──────────────────────────────────────────────────────────

export function useSessionAnalysis(eventsRef: Ref<ObserverEvent[]>) {
  const sorted = computed(() =>
    [...eventsRef.value].sort((a, b) => a.timestamp - b.timestamp)
  )

  const startTs = computed(() => sorted.value[0]?.timestamp ?? 0)
  const endTs = computed(() => sorted.value[sorted.value.length - 1]?.timestamp ?? 0)
  const durationMs = computed(() => Math.max(endTs.value - startTs.value, 1000))

  // Build causal tree: prompts → droids → tools
  const tree = computed((): TurnNode[] => {
    const evts = sorted.value
    const base = startTs.value
    const turns: TurnNode[] = []
    let currentTurn: TurnNode | null = null
    // Stack of open droid nodes (handles nested droids)
    const droidStack: DroidNode[] = []
    let nodeCounter = 0

    for (const e of evts) {
      const id = `node-${nodeCounter++}`
      const relTimeSec = (e.timestamp - base) / 1000

      if (e.hook_event_type === 'UserPromptSubmit') {
        // Close any lingering droids — they span turns
        // (don't pop stack — droids can outlive prompts)
        currentTurn = {
          type: 'turn',
          id,
          event: e,
          promptPreview: (e.payload?.prompt_preview as string) ?? '',
          relTimeSec,
          children: [],
        }
        turns.push(currentTurn)

      } else if (e.hook_event_type === 'SubagentStart') {
        const droidNode: DroidNode = {
          type: 'droid',
          id,
          droid_name: e.droid_name || '???',
          droid_color: e.droid_color || '#6B7280',
          droid_emoji: e.droid_emoji || '🤖',
          start_ts: e.timestamp,
          end_ts: endTs.value,
          duration_ms: 0,
          relTimeSec,
          tools: [],
        }

        // Attach to current turn (nested droids are uncommon; just add to turn)
        if (currentTurn) {
          currentTurn.children.push(droidNode)
        }
        droidStack.push(droidNode)

      } else if (e.hook_event_type === 'SubagentStop') {
        // Find matching open droid in stack
        const stackIdx = droidStack.map((d, i) => i)
          .filter(i => droidStack[i].droid_name === e.droid_name)
          .pop()

        if (stackIdx !== undefined) {
          const closed = droidStack.splice(stackIdx, 1)[0]
          closed.end_ts = e.timestamp
          closed.duration_ms = e.timestamp - closed.start_ts
        }

      } else if (e.hook_event_type === 'PreToolUse') {
        const input = ((e.payload as Record<string, unknown>)?.tool_input as Record<string, unknown>) ?? {}
        const { label, sublabel } = toolLabel(e.tool_name, input)
        const toolNode: ToolNode = {
          type: 'tool',
          id,
          event: e,
          label,
          sublabel,
          color: toolColor(e.tool_name),
          relTimeSec,
        }

        // Attach to innermost active droid or current turn
        if (droidStack.length > 0) {
          droidStack[droidStack.length - 1].tools.push(toolNode)
        } else if (currentTurn) {
          currentTurn.children.push(toolNode)
        }
      }
    }

    // Post-process: pull orphan tools that immediately precede their spawned droid
    // into that droid's tools list so the whole block collapses together.
    const SPAWN_WINDOW_MS = 5000
    for (const turn of turns) {
      const merged: Array<DroidNode | ToolNode> = []
      let i = 0
      while (i < turn.children.length) {
        const child = turn.children[i]
        const next = turn.children[i + 1]
        if (
          child.type === 'tool' &&
          next?.type === 'droid' &&
          next.start_ts - child.event.timestamp <= SPAWN_WINDOW_MS
        ) {
          next.tools.unshift(child)
          merged.push(next)
          i += 2
        } else {
          merged.push(child)
          i++
        }
      }
      turn.children = merged
    }

    return turns
  })

  // Stats derived from the tree
  const stats = computed((): SessionStats => {
    const droidMap: Record<string, { color: string; emoji: string; count: number; total_ms: number }> = {}
    const mcpMap: Record<string, number> = {}
    const fileOpMap: Record<string, number> = {}
    let skillCount = 0
    let taskCount = 0
    let bashCount = 0
    let webCount = 0
    let totalTools = 0
    const FILE_OPS = new Set(['Read', 'Write', 'Edit', 'Glob', 'Grep', 'NotebookEdit'])

    function walkTools(tools: ToolNode[]) {
      for (const t of tools) {
        totalTools++
        const name = t.event.tool_name
        if (name === 'Skill') skillCount++
        else if (name === 'Task') taskCount++
        else if (name === 'Bash') bashCount++
        else if (name === 'WebFetch' || name === 'WebSearch') webCount++
        else if (FILE_OPS.has(name)) {
          fileOpMap[name] = (fileOpMap[name] ?? 0) + 1
        } else if (name.startsWith('mcp__')) {
          const svc = name.split('__')[1] ?? 'unknown'
          mcpMap[svc] = (mcpMap[svc] ?? 0) + 1
        }
      }
    }

    function walkDroids(nodes: Array<DroidNode | ToolNode>) {
      for (const n of nodes) {
        if (n.type === 'droid') {
          if (!droidMap[n.droid_name]) {
            droidMap[n.droid_name] = { color: n.droid_color, emoji: n.droid_emoji, count: 0, total_ms: 0 }
          }
          droidMap[n.droid_name].count++
          droidMap[n.droid_name].total_ms += n.duration_ms
          walkTools(n.tools)
        } else {
          walkTools([n as ToolNode])
        }
      }
    }

    for (const turn of tree.value) {
      walkDroids(turn.children)
    }

    const droidRows = Object.entries(droidMap)
      .map(([name, d]) => ({ name, ...d }))
      .sort((a, b) => b.count - a.count)

    const totalDroidMs = droidRows.reduce((s, d) => s + d.total_ms, 0)

    return {
      duration_ms: durationMs.value,
      prompt_count: tree.value.length,
      droid_rows: droidRows,
      mcp_services: Object.entries(mcpMap).map(([name, count]) => ({ name, count })).sort((a, b) => b.count - a.count),
      skill_count: skillCount,
      task_count: taskCount,
      bash_count: bashCount,
      web_count: webCount,
      file_ops: Object.entries(fileOpMap).map(([name, count]) => ({ name, count })).sort((a, b) => b.count - a.count),
      total_tool_calls: totalTools,
      total_droid_ms: totalDroidMs,
      parallelism: durationMs.value > 0 ? totalDroidMs / durationMs.value : 0,
    }
  })

  function formatMs(ms: number): string {
    const s = Math.floor(ms / 1000)
    const m = Math.floor(s / 60)
    const h = Math.floor(m / 60)
    if (h > 0) return `${h}h ${m % 60}m`
    if (m > 0) return `${m}m ${s % 60}s`
    return `${s}s`
  }

  function formatRel(sec: number): string {
    const m = Math.floor(sec / 60)
    const s = Math.floor(sec % 60)
    if (m > 0) return `+${m}m${String(s).padStart(2, '0')}s`
    return `+${s.toFixed(1)}s`
  }

  return { sorted, startTs, endTs, durationMs, tree, stats, formatMs, formatRel }
}
