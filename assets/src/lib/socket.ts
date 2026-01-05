import { useState, useEffect, useRef } from 'react'

interface UseProjectEventsOptions {
  projectId?: string
  onEvent?: (event: any) => void
}

export function useProjectEvents({ projectId, onEvent }: UseProjectEventsOptions) {
  const [isConnected, setIsConnected] = useState(true) // SSE is always "connected" if the app is up
  const onEventRef = useRef(onEvent)
  
  useEffect(() => {
    onEventRef.current = onEvent
  }, [onEvent])

  useEffect(() => {
    if (!projectId) return

    const handler = (e: any) => {
      const event = e.detail
      // SSE sends events for the project it's connected to.
      // We can also verify if needed, but __root.tsx already filters by activeProjectId.
      onEventRef.current?.(event)
    }

    window.addEventListener('project-event', handler)
    return () => window.removeEventListener('project-event', handler)
  }, [projectId])

  return { isConnected }
}
