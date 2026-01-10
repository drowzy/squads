import { useState, useEffect } from 'react'
import { X, Terminal, Loader2 } from 'lucide-react'
import { cn } from '../lib/cn'
import { SessionChat, type AgentMode } from './SessionChat'
import { type Session, type Agent, useSession, useAgents } from '../api/queries'

interface SessionChatFlyoutProps {
  sessionId?: string
  session?: Session // For backward compat if full object is passed
  agent?: Agent
  open?: boolean
  onOpenChange?: (open: boolean) => void
  onClose?: () => void // Deprecated, use onOpenChange
}

export function SessionChatFlyout({
  sessionId,
  session: initialSession,
  agent: initialAgent,
  open,
  onOpenChange,
  onClose,
}: SessionChatFlyoutProps) {
  // Sticky mode per session (runtime only)
  const [mode, setMode] = useState<AgentMode>('plan')
  
  // Handle both controlled (open prop) and uncontrolled (internal state + onClose) usage
  const isOpen = open !== undefined ? open : true
  const handleClose = () => {
      onOpenChange?.(false)
      onClose?.()
  }

  // Fetch session details if we only have an ID
  const { data: fetchedSession, isLoading: isSessionLoading } = useSession(sessionId || '')
  
  // Resolve session and agent
  const session = initialSession || fetchedSession
  
  // We might need to fetch the agent if not provided
  const { data: agents = [] } = useAgents()
  const agent = initialAgent || (session ? agents.find(a => a.id === session.agent_id) : undefined)

  // Close on ESC key
  useEffect(() => {
    if (!isOpen) return
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        handleClose()
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [isOpen, handleClose])

  // Prevent body scroll when flyout is open
  useEffect(() => {
    if (!isOpen) return
    document.body.style.overflow = 'hidden'
    return () => {
      document.body.style.overflow = ''
    }
  }, [isOpen])

  if (!isOpen) return null
  
  if (isSessionLoading) {
      return (
        <div className="fixed inset-0 z-50 flex items-center justify-center bg-black/60">
             <div className="p-4 bg-tui-bg border border-tui-border rounded flex flex-col items-center gap-2">
                 <Loader2 className="animate-spin text-tui-accent" size={24} />
                 <span className="text-sm text-tui-dim">Loading session...</span>
             </div>
        </div>
      )
  }

  if (!session) {
      return null // Should handle error state better in real app
  }

  const isActive = session.status === 'running' || session.status === 'pending'

  return (
    <>
      {/* Backdrop */}
      <div
        className="fixed inset-0 bg-black/60 z-40"
        onClick={handleClose}
        aria-hidden="true"
      />

      {/* Flyout Panel */}
      <div
        className={cn(
          'fixed inset-y-0 right-0 z-50 w-full sm:w-[480px] md:w-[560px] lg:w-[640px]',
          'bg-tui-bg border-l border-tui-border',
          'flex flex-col',
          'animate-in slide-in-from-right duration-200'
        )}
        role="dialog"
        aria-modal="true"
        aria-labelledby="flyout-title"
      >
        {/* Header */}
        <div className="p-3 border-b border-tui-border bg-tui-dim/10 flex items-center justify-between shrink-0">
          <div className="flex items-center gap-3 min-w-0">
            <Terminal size={16} className="text-tui-accent shrink-0" />
            <div className="min-w-0">
              <h2
                id="flyout-title"
                className="font-bold text-sm uppercase tracking-widest truncate"
              >
                {agent?.name || 'SESSION CHAT'}
              </h2>
              <div className="text-[10px] text-tui-dim font-mono truncate">
                session/{session.id.slice(0, 8)}
                {session.model && <span className="ml-2">• {session.model}</span>}
              </div>
            </div>
          </div>

          <div className="flex items-center gap-2 shrink-0">
            {/* Status Badge */}
            <span
              className={cn(
                'px-2 py-0.5 border text-[10px] font-bold uppercase tracking-widest',
                isActive
                  ? 'border-green-500/30 text-green-400'
                  : 'border-tui-border text-tui-dim'
              )}
            >
              {isActive ? 'LIVE' : session.status.toUpperCase()}
            </span>

            {/* Close Button */}
            <button
              onClick={handleClose}
              className="p-1.5 text-tui-dim hover:text-tui-text transition-colors"
              aria-label="Close chat"
            >
              <X size={18} />
            </button>
          </div>
        </div>

        {/* Chat Content */}
        <div className="flex-1 overflow-hidden">
          <SessionChat
            session={session}
            mode={mode}
            onModeChange={setMode}
            showModeToggle={true}
            showHeader={false}
            className="h-full"
          />
        </div>
      </div>
    </>
  )
}
