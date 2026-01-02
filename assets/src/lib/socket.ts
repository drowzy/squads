import { useState, useEffect, useRef } from 'react'

interface UseProjectEventsOptions {
  projectId?: string
  onEvent?: (event: any) => void
}

export function useProjectEvents({ projectId, onEvent }: UseProjectEventsOptions) {
  const [isConnected, setIsConnected] = useState(false)
  const socketRef = useRef<WebSocket | null>(null)
  const reconnectTimeoutRef = useRef<NodeJS.Timeout>()

  useEffect(() => {
    if (!projectId) return

    const connect = () => {
      // Use wss for https, ws for http
      const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:'
      const wsUrl = `${protocol}//${window.location.host}/socket/websocket`
      
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
            onEvent?.(data.data)
          } else if (data.type === 'joined') {
            console.log(`Joined project ${data.project_id}`)
          }
        } catch (err) {
          console.error('Failed to parse websocket message', err)
        }
      }

      ws.onclose = () => {
        setIsConnected(false)
        // Try to reconnect in 3 seconds
        reconnectTimeoutRef.current = setTimeout(connect, 3000)
      }

      ws.onerror = (err) => {
        console.error('WebSocket error:', err)
        ws.close()
      }
    }

    connect()

    return () => {
      if (socketRef.current) {
        socketRef.current.close()
      }
      if (reconnectTimeoutRef.current) {
        clearTimeout(reconnectTimeoutRef.current)
      }
    }
  }, [projectId, onEvent]) // Re-connect if projectId changes

  return { isConnected }
}
