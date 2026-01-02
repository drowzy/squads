import { Socket, Channel } from 'phoenix'
import { useEffect, useState, useRef } from 'react'

const socket = new Socket('/socket')
socket.connect()

interface UseProjectEventsOptions {
  projectId?: string
  onEvent?: (event: any) => void
}

export function useProjectEvents({ projectId, onEvent }: UseProjectEventsOptions) {
  const channelRef = useRef<Channel | null>(null)
  const [isConnected, setIsConnected] = useState(false)

  useEffect(() => {
    if (!projectId) return

    // Create channel
    const channel = socket.channel(`project:${projectId}:events`, {})
    channelRef.current = channel

    // Setup event listener
    const ref = channel.on('event', (payload) => {
      onEvent?.(payload)
    })

    // Join channel
    channel.join()
      .receive('ok', () => {
        setIsConnected(true)
        console.log(`Joined project:${projectId}:events`)
      })
      .receive('error', (resp) => {
        console.error('Unable to join', resp)
        setIsConnected(false)
      })

    // Cleanup
    return () => {
      channel.off('event', ref)
      channel.leave()
      channelRef.current = null
      setIsConnected(false)
    }
  }, [projectId, onEvent]) // Re-connect if projectId changes

  return { isConnected }
}
