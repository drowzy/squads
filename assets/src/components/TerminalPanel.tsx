import { useState, useEffect, useRef } from 'react'
import { Terminal, Minus, Maximize2, X } from 'lucide-react'
import { useProjectEvents } from '../lib/socket'
import { cn } from '../lib/cn'

interface SystemEvent {
  id: string
  kind: string
  payload: Record<string, any>
  occurred_at: string
}

interface TerminalPanelProps {
  projectId: string
}

export function TerminalPanel({ projectId }: TerminalPanelProps) {
  const [isOpen, setIsOpen] = useState(false)
  const [isMinimized, setIsMinimized] = useState(false)
  const [events, setEvents] = useState<SystemEvent[]>([])
  const scrollRef = useRef<HTMLDivElement>(null)

  const { isConnected } = useProjectEvents({
    projectId,
    onEvent: (event) => {
      setEvents(prev => [...prev.slice(-49), event])
      // Auto-scroll to bottom if near bottom
      if (scrollRef.current) {
        const { scrollTop, scrollHeight, clientHeight } = scrollRef.current
        if (scrollHeight - scrollTop - clientHeight < 100) {
          setTimeout(() => {
            scrollRef.current?.scrollTo({ top: scrollRef.current.scrollHeight, behavior: 'smooth' })
          }, 100)
        }
      }
    }
  })

  // Mock initial connection event
  useEffect(() => {
    if (isConnected) {
      setEvents(prev => [...prev, {
        id: 'sys-init',
        kind: 'system.connected',
        payload: { message: 'Uplink established. Monitoring system events...' },
        occurred_at: new Date().toISOString()
      }])
    }
  }, [isConnected])

  if (!isOpen) {
    return (
      <button
        onClick={() => setIsOpen(true)}
        className="fixed bottom-20 right-4 md:bottom-4 bg-tui-bg border border-tui-accent text-tui-accent p-3 md:p-2 rounded-full shadow-lg hover:bg-tui-accent hover:text-tui-bg transition-colors z-40"
        title="Open System Terminal"
      >
        <Terminal size={24} className="md:w-5 md:h-5" />
      </button>
    )
  }

  if (isMinimized) {
    return (
      <div className="fixed bottom-20 right-4 md:bottom-4 w-auto md:w-64 bg-tui-bg border border-tui-border shadow-lg z-40 flex items-center justify-between p-2 rounded md:rounded-none">
        <div className="flex items-center gap-2 text-xs text-tui-accent font-mono mr-2">
          <Terminal size={14} />
          <span className="hidden md:inline">System Stream</span>
          {isConnected && <span className="w-1.5 h-1.5 bg-tui-accent rounded-full animate-pulse" />}
        </div>
        <div className="flex items-center gap-1">
          <button 
            onClick={() => setIsMinimized(false)}
            className="p-1 hover:text-tui-accent"
          >
            <Maximize2 size={12} />
          </button>
          <button 
            onClick={() => setIsOpen(false)}
            className="p-1 hover:text-ctp-red"
          >
            <X size={12} />
          </button>
        </div>
      </div>
    )
  }

  return (
    <div className="fixed bottom-0 left-0 right-0 h-[40vh] md:left-auto md:right-4 md:bottom-4 md:w-[400px] md:h-[300px] bg-tui-bg border-t md:border border-tui-border shadow-xl z-50 flex flex-col font-mono text-xs">
      {/* Header */}
      <div className="flex items-center justify-between p-2 border-b border-tui-border bg-tui-dim/5">
        <div className="flex items-center gap-2 text-tui-accent">
          <Terminal size={14} />
          <span className="font-bold tracking-wider">SYSTEM STREAM</span>
        </div>
        <div className="flex items-center gap-1 text-tui-dim">
          <button 
            onClick={() => setIsMinimized(true)}
            className="p-1 hover:text-tui-text hover:bg-tui-dim/10 rounded"
          >
            <Minus size={12} />
          </button>
          <button 
            onClick={() => setIsOpen(false)}
            className="p-1 hover:text-ctp-red hover:bg-tui-dim/10 rounded"
          >
            <X size={12} />
          </button>
        </div>
      </div>

      {/* Content */}
      <div 
        ref={scrollRef}
        className="flex-1 overflow-y-auto p-3 space-y-2 bg-black/50"
      >
        {events.length === 0 ? (
          <div className="text-tui-dim italic">Waiting for signal...</div>
        ) : (
          events.map((event, i) => (
            <EventLine key={event.id || i} event={event} />
          ))
        )}
        <div className="h-4" /> {/* Spacer */}
      </div>

      {/* Footer status */}
      <div className="p-1 border-t border-tui-border flex justify-between text-[10px] text-tui-dim bg-tui-dim/5">
        <span>{isConnected ? 'CONNECTED' : 'CONNECTING...'}</span>
        <span>{events.length} EVENTS</span>
      </div>
    </div>
  )
}

function EventLine({ event }: { event: SystemEvent }) {
  const time = new Date(event.occurred_at).toLocaleTimeString([], { hour12: false })
  
  const getKindColor = (k: string) => {
    if (k.startsWith('error') || k.includes('fail')) return 'text-ctp-red'
    if (k.startsWith('warn')) return 'text-ctp-peach'
    if (k.includes('success') || k.includes('complete')) return 'text-tui-accent'
    return 'text-tui-text'
  }

  return (
    <div className="font-mono">
      <span className="text-tui-dim mr-2">[{time}]</span>
      <span className={cn("font-bold mr-2", getKindColor(event.kind))}>
        {event.kind}
      </span>
      <span className="text-tui-dim break-all">
        {JSON.stringify(event.payload)}
      </span>
    </div>
  )
}
