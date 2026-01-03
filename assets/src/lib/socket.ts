import { useState, useEffect, useRef } from 'react'
import { WS_BASE } from '../api/client'

interface UseProjectEventsOptions {
  projectId?: string
  onEvent?: (event: any) => void
}

export function useProjectEvents({ projectId, onEvent }: UseProjectEventsOptions) {
  const [isConnected, setIsConnected] = useState(false)
  const socketRef = useRef<WebSocket | null>(null)
  const reconnectTimeoutRef = useRef<ReturnType<typeof setTimeout> | null>(null)
  // Store onEvent in a ref to avoid re-connecting when callback changes
  const onEventRef = useRef(onEvent)
  
  // Keep the ref up to date
  useEffect(() => {
    onEventRef.current = onEvent
  }, [onEvent])

  useEffect(() => {
    if (!projectId) return

    // Prevent multiple connections
    if (socketRef.current?.readyState === WebSocket.OPEN || 
        socketRef.current?.readyState === WebSocket.CONNECTING) {
      return
    }

    const connect = () => {
      // Clean up any existing socket first
      if (socketRef.current) {
        socketRef.current.onclose = null // Prevent reconnect loop
        socketRef.current.close()
        socketRef.current = null
      }

      const wsUrl = WS_BASE.endsWith('/socket/websocket')
        ? WS_BASE
        : `${WS_BASE}/socket/websocket`
      
      const ws = new WebSocket(wsUrl)
      socketRef.current = ws

      ws.onopen = () => {
        setIsConnected(true)
        // Send join message
        ws.send(JSON.stringify({
          type: 'join',
          project_id: projectId
        }))
      }

      ws.onmessage = (event) => {
        try {
          const data = JSON.parse(event.data)
          if (data.type === 'event') {
            onEventRef.current?.(data.data)
          } else if (data.type === 'joined') {
            console.log(`Joined project ${data.project_id}`)
          }
        } catch (err) {
          console.error('Failed to parse websocket message', err)
        }
      }

      ws.onclose = () => {
        setIsConnected(false)
        socketRef.current = null
        // Try to reconnect in 3 seconds
        reconnectTimeoutRef.current = setTimeout(connect, 3000)
      }

      ws.onerror = (err) => {
        console.error('WebSocket error:', err)
        // Don't close here - onclose will be called automatically
      }
    }

    connect()

    return () => {
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current)
        reconnectTimeoutRef.current = null
      }
      if (socketRef.current) {
        socketRef.current.onclose = null // Prevent reconnect on cleanup
        socketRef.current.close()
        socketRef.current = null
      }
    }
  }, [projectId]) // Only re-connect when projectId changes, NOT onEvent

  return { isConnected }
}
