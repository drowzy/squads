import { ChevronLeft, ChevronRight, History, Plus, Archive, Play } from 'lucide-react'
import { cn } from '../lib/cn'
import type { Session } from '../api/queries'

type HistoryFilter = 'active' | 'history' | 'all'

interface SessionSidebarProps {
  isOpen: boolean
  onClose: () => void
  currentSession?: Session | null
  sessions: Session[]
  selectedSessionId: string
  onSelectSession: (sessionId: string) => void
  historyFilter: HistoryFilter
  onHistoryFilterChange: (filter: HistoryFilter) => void
  onNewSession: () => void
}

export function SessionSidebar({
  isOpen,
  onClose,
  currentSession,
  sessions,
  selectedSessionId,
  onSelectSession,
  historyFilter,
  onHistoryFilterChange,
  onNewSession,
}: SessionSidebarProps) {
  const filteredSessions = sessions.filter((session) => {
    if (historyFilter === 'active') {
      return session.status === 'running'
    }
    if (historyFilter === 'history') {
      return session.status !== 'running' && session.status !== 'starting' && session.status !== 'pending'
    }
    return true
  })

  const formatSessionTitle = (session: Session) => {
    const metadata = session.metadata as Record<string, unknown> | undefined
    return (metadata?.title as string) || session.ticket_key || `Session ${session.id.slice(0, 8)}`
  }

  const formatSessionTime = (session: Session) => {
    const date = new Date(session.inserted_at)
    const now = new Date()
    const diffMs = now.getTime() - date.getTime()
    const diffMins = Math.floor(diffMs / 60000)
    const diffHours = Math.floor(diffMins / 60)
    const diffDays = Math.floor(diffHours / 24)

    if (diffMins < 1) return 'Just now'
    if (diffMins < 60) return `${diffMins}m ago`
    if (diffHours < 24) return `${diffHours}h ago`
    if (diffDays < 7) return `${diffDays}d ago`
    return date.toLocaleDateString()
  }

  const getStatusColor = (status: string) => {
    switch (status) {
      case 'running':
      case 'starting':
      case 'pending':
        return 'text-tui-success'
      case 'completed':
      case 'done':
        return 'text-tui-accent'
      case 'failed':
      case 'error':
        return 'text-tui-error'
      case 'archived':
        return 'text-tui-dim'
      default:
        return 'text-tui-text'
    }
  }

  const getStatusBadge = (status: string) => {
    const isRunning = ['running', 'starting', 'pending'].includes(status)
    return (
      <span className={cn(
        'flex items-center gap-1 text-[9px] font-mono uppercase',
        getStatusColor(status)
      )}>
        {isRunning && <div className="w-1 h-1 rounded-full bg-current animate-pulse" />}
        {status}
      </span>
    )
  }

  if (!isOpen) return null

  return (
    <div className="h-full flex flex-col border-r border-tui-border bg-ctp-mantle/50 animate-in slide-in-from-left duration-200 w-72">
      <div className="flex items-center justify-between px-3 py-2 border-b border-tui-border bg-ctp-crust/40 shrink-0">
        <div className="flex items-center gap-2">
          <History size={14} className="text-tui-dim" />
          <div className="text-xs font-bold text-tui-text">Sessions</div>
        </div>
        <button
          onClick={onClose}
          className="p-1 text-tui-dim hover:text-tui-accent transition-colors"
          title="Close session list"
        >
          <ChevronLeft size={14} />
        </button>
      </div>

      <div className="p-2 border-b border-tui-border bg-ctp-crust/20 shrink-0">
        <div className="flex items-center gap-1 border border-tui-border p-0.5 bg-ctp-crust/40 shrink-0 mb-2">
          {(['active', 'history', 'all'] as const).map((filter) => (
            <button
              key={filter}
              onClick={() => onHistoryFilterChange(filter)}
              className={cn(
                'flex-1 px-2 py-1 text-[9px] font-bold uppercase tracking-widest transition-colors rounded-sm',
                historyFilter === filter ? 'bg-tui-accent text-tui-bg' : 'text-tui-dim hover:text-tui-text'
              )}
            >
              {filter}
            </button>
          ))}
        </div>

        <button
          onClick={onNewSession}
          className="w-full flex items-center justify-center gap-2 px-2 py-1.5 bg-tui-accent/10 border border-tui-accent text-tui-accent font-bold text-[10px] hover:bg-tui-accent hover:text-tui-bg transition-colors uppercase tracking-widest"
        >
          <Plus size={12} />
          New Session
        </button>
      </div>

      <div className="flex-1 overflow-y-auto custom-scrollbar">
        {filteredSessions.length === 0 ? (
          <div className="h-full flex items-center justify-center text-tui-dim text-sm p-4">
            {historyFilter === 'active' ? 'No active sessions' : 'No sessions found'}
          </div>
        ) : (
          <div className="p-2 space-y-1">
            {filteredSessions.map((session) => (
              <button
                key={session.id}
                onClick={() => onSelectSession(session.id)}
                className={cn(
                  'w-full text-left p-2 rounded-sm border transition-colors',
                  selectedSessionId === session.id
                    ? 'bg-tui-accent/10 border-tui-accent text-tui-text'
                    : 'bg-ctp-crust/20 border-tui-border hover:border-tui-border-dim hover:bg-ctp-crust/40'
                )}
              >
                <div className="flex items-start justify-between gap-2 mb-1">
                  <div className="text-[11px] font-bold truncate flex-1" title={formatSessionTitle(session)}>
                    {formatSessionTitle(session)}
                  </div>
                  {getStatusBadge(session.status)}
                </div>
                <div className="flex items-center justify-between gap-2">
                  <div className="text-[9px] text-tui-dim font-mono truncate">
                    {formatSessionTime(session)}
                  </div>
                  {session.status === 'archived' && (
                    <Archive size={10} className="text-tui-dim shrink-0" />
                  )}
                  {['running', 'starting', 'pending'].includes(session.status) && (
                    <Play size={10} className="text-tui-success shrink-0" />
                  )}
                </div>
              </button>
            ))}
          </div>
        )}
      </div>

      <div className="border-t border-tui-border p-2 bg-ctp-crust/40 shrink-0">
        <div className="text-[9px] text-tui-dim">
          Press <kbd className="px-1 py-0.5 rounded border border-tui-border bg-tui-dim/10">[</kbd> to close
        </div>
      </div>
    </div>
  )
}
