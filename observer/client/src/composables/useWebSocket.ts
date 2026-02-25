import { ref, onMounted, onUnmounted } from 'vue'
import { useEventsStore } from '../stores/events'
import type { ObserverEvent } from '../types/events'

const WS_URL = 'ws://localhost:4001/stream'
const RECONNECT_DELAY_MS = 3000

export function useWebSocket() {
  const connected = ref(false)
  let ws: WebSocket | null = null
  let reconnectTimer: ReturnType<typeof setTimeout> | null = null

  function connect() {
    const store = useEventsStore()

    ws = new WebSocket(WS_URL)

    ws.onopen = () => {
      connected.value = true
      if (reconnectTimer) {
        clearTimeout(reconnectTimer)
        reconnectTimer = null
      }
    }

    ws.onmessage = (msg) => {
      try {
        const data = JSON.parse(msg.data)
        if (data.type === 'ping') return
        store.pushEvent(data as ObserverEvent)
      } catch {
        // ignore malformed messages
      }
    }

    ws.onclose = () => {
      connected.value = false
      reconnectTimer = setTimeout(connect, RECONNECT_DELAY_MS)
    }

    ws.onerror = () => {
      ws?.close()
    }
  }

  onMounted(connect)

  onUnmounted(() => {
    if (reconnectTimer) clearTimeout(reconnectTimer)
    ws?.close()
  })

  return { connected }
}
