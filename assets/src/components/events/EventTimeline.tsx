import { type Event } from '../../api/queries'
import type { MouseEvent } from 'react'
import { cn } from '../../lib/cn'
import { Zap, Terminal, MessageSquare, Ticket, Mail, User, Clock } from 'lucide-react'

interface EventTimelineProps {
  events: Event[]
  isLoading?: boolean
  className?: string
  showSessionLink?: boolean
}

const normalizeEventKind = (kind: string) => kind.replace(/^(\w+)\./, '$1:')

export function EventTimeline({ events, isLoading, className, showSessionLink }: EventTimelineProps) {
  if (isLoading) {
    return (
      <div className={cn("space-y-4 animate-pulse", className)}>
        {[1, 2, 3].map((i) => (
          <div key={i} className="h-16 bg-tui-dim/10 border border-tui-border" />
        ))}
      </div>
    )
  }

  if (events.length === 0) {
    return (
      <div className={cn("py-12 text-center border border-tui-border bg-black/20", className)}>
        <p className="text-xs text-tui-dim uppercase tracking-widest">No events found</p>
      </div>
    )
  }

  return (
    <div className={cn("space-y-2", className)}>
      {events.map((event) => (
        <EventItem key={event.id} event={event} showSessionLink={showSessionLink} />
      ))}
    </div>
  )
}

function EventItem({ event, showSessionLink }: { event: Event, showSessionLink?: boolean }) {
  const kind = normalizeEventKind(event.kind)
  const payload = event.payload
  const timestamp = new Date(event.occurred_at).toLocaleTimeString()
  const date = new Date(event.occurred_at).toLocaleDateString()

  const config = getEventConfig(kind)
  const Icon = config.icon

  const handleCopy = (event: MouseEvent<HTMLButtonElement>) => {
    event.preventDefault()
    event.stopPropagation()
    navigator.clipboard?.writeText(JSON.stringify(payload, null, 2))
  }

  return (
    <div className="group border border-tui-border bg-black/20 hover:border-tui-accent/50 transition-colors">
      <div className="p-3 flex items-start gap-4">
        <div className={cn("p-2 border shrink-0", config.color, config.bg)}>
          <Icon size={16} />
        </div>
        <div className="flex-1 min-w-0">
          <div className="flex items-center justify-between gap-2 mb-1">
            <div className="flex items-center gap-2">
              <span className="text-[10px] font-bold uppercase tracking-widest text-tui-text">
                {kind.replace(/[:.]/g, '_')}
              </span>
              {showSessionLink && event.session_id && (
                <span className="text-[9px] text-tui-accent font-mono bg-tui-accent/10 px-1 border border-tui-accent/30">
                  SESSION:{event.session_id.slice(0, 8)}
                </span>
              )}
            </div>
            <div className="flex items-center gap-1.5 text-tui-dim">
              <Clock size={10} />
              <span className="text-[10px] font-mono whitespace-nowrap">{date} {timestamp}</span>
            </div>
          </div>
          <div className="text-sm text-tui-dim line-clamp-2">
            {formatPayload(kind, payload)}
          </div>
          
          <details className="mt-2 group/details">
            <summary className="text-[9px] uppercase tracking-[0.2em] text-tui-dim hover:text-tui-text cursor-pointer list-none flex items-center gap-1 transition-colors">
              <span className="group-open/details:rotate-90 transition-transform">▶</span>
              Inspect_Payload
            </summary>
            <div className="mt-2 flex justify-end">
              <button
                type="button"
                onClick={handleCopy}
                className="text-[9px] uppercase tracking-[0.2em] text-tui-dim hover:text-tui-text"
              >
                Copy_Payload
              </button>
            </div>
            <pre className="mt-2 p-2 bg-black/40 border border-tui-border/50 text-[10px] text-tui-accent/80 font-mono overflow-x-auto max-h-40">
              {JSON.stringify(payload, null, 2)}
            </pre>
          </details>
        </div>
      </div>
    </div>
  )
}

function getEventConfig(kind: string) {
  if (kind.startsWith('session:')) {
    return { icon: Terminal, color: 'text-tui-accent', bg: 'bg-tui-accent/10' }
  }
  if (kind.startsWith('message:')) {
    return { icon: MessageSquare, color: 'text-ctp-peach', bg: 'bg-ctp-peach/10' }
  }
  if (kind.startsWith('ticket:')) {
    return { icon: Ticket, color: 'text-ctp-blue', bg: 'bg-ctp-blue/10' }
  }
  if (kind.startsWith('mail:')) {
    return { icon: Mail, color: 'text-ctp-mauve', bg: 'bg-ctp-mauve/10' }
  }
  if (kind.startsWith('agent:')) {
    return { icon: User, color: 'text-ctp-green', bg: 'bg-ctp-green/10' }
  }
  return { icon: Zap, color: 'text-tui-dim', bg: 'bg-tui-dim/10' }
}

function formatPayload(kind: string, payload: any): string {
  switch (kind) {
    case 'session:status_changed':
      return `Session status changed to ${payload.status}`
    case 'message:created':
      return `New message from ${payload.role}`
    case 'ticket:created':
      return `Ticket created: ${payload.title}`
    case 'ticket:status_changed':
      return `Ticket ${payload.ticket_key || 'key'} status changed to ${payload.status}`
    case 'mail:received':
      return `Mail received from ${payload.sender_name}: ${payload.subject}`
    case 'agent:status_changed':
      return `Agent ${payload.name || 'agent'} is now ${payload.status}`
    default:
      return JSON.stringify(payload).slice(0, 100)
  }
}
