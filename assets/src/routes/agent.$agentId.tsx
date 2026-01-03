import { createFileRoute, Link } from '@tanstack/react-router'
import { Terminal, Mail, Archive, Activity, Cpu, ChevronRight, Loader2, Inbox, Pencil, Play, Info, History, X, ListTodo, FileDiff } from 'lucide-react'
import React, { useState, useEffect, useMemo } from 'react'

import { 
  useEvents, 
  useSessions, 
  useMailThreads, 
  useSquads, 
  useStopSession, 
  useUpdateAgent,
  useAgentRolesConfig,
  useModels,
  useSyncProviders,
  useNewSession,
  useSessionTodos,
  useSessionDiff,
  type Agent,
} from '../api/queries'
import { EventTimeline } from '../components/events/EventTimeline'
import { useActiveProject } from './__root'
import { Modal, FormField, Button } from '../components/Modal'
import { useNotifications } from '../components/Notifications'
import { SessionChat, type AgentMode } from '../components/SessionChat'
import { cn } from '../lib/cn'

export const Route = createFileRoute('/agent/$agentId')({
  component: AgentDetail,
})

function TabButton({ 
  active, 
  onClick, 
  icon, 
  label 
}: { 
  active: boolean; 
  onClick: () => void; 
  icon: React.ReactNode; 
  label: string 
}) {
  return (
    <button
      onClick={onClick}
      className={cn(
        "flex items-center gap-1.5 px-3 py-1.5 text-[10px] font-bold tracking-widest transition-colors border-b-2",
        active 
          ? "text-tui-accent border-tui-accent bg-tui-accent/5" 
          : "text-tui-dim border-transparent hover:text-tui-text hover:bg-tui-dim/5"
      )}
    >
      {icon}
      {label}
    </button>
  )
}

function SessionTodos({ sessionId }: { sessionId: string }) {
  const { data: todos, isLoading, error } = useSessionTodos(sessionId)

  if (isLoading) return <div className="animate-pulse text-tui-dim">Loading todos...</div>
  if (error) return <div className="text-red-500">Error loading todos</div>
  if (!todos || todos.length === 0) return <div className="text-tui-dim italic">No todos found for this session.</div>

  return (
    <div className="space-y-2">
      {todos.map((todo: any, idx: number) => (
        <div key={idx} className="flex items-start gap-3 p-2 border border-tui-border bg-black/20">
          <div className={cn(
            "w-4 h-4 mt-0.5 border flex items-center justify-center shrink-0",
            todo.status === 'completed' ? "bg-tui-accent border-tui-accent" : "border-tui-dim"
          )}>
            {todo.status === 'completed' && <X size={12} className="text-tui-bg" />}
          </div>
          <div className="flex-1 min-w-0">
            <div className={cn(
              "text-xs font-bold",
              todo.status === 'completed' ? "text-tui-dim line-through" : "text-tui-text"
            )}>
              {todo.content}
            </div>
            {todo.priority && (
              <div className="text-[9px] text-tui-dim uppercase tracking-tighter mt-1">
                Priority: {todo.priority}
              </div>
            )}
          </div>
        </div>
      ))}
    </div>
  )
}

function SessionDiff({ sessionId }: { sessionId: string }) {
  const { data: diff, isLoading, error } = useSessionDiff(sessionId)

  if (isLoading) return <div className="animate-pulse text-tui-dim">Loading diff...</div>
  if (error) return <div className="text-red-500">Error loading diff</div>
  if (!diff || typeof diff !== 'string' || diff.trim() === '') return <div className="text-tui-dim italic">No changes recorded in this session.</div>

  return (
    <pre className="text-[10px] leading-relaxed overflow-x-auto whitespace-pre-wrap text-tui-text/90">
      {diff}
    </pre>
  )
}

function AgentDetail() {
  const { agentId } = Route.useParams()
  const { activeProject } = useActiveProject()
  const { data: allSessions = [], isLoading: isLoadingSessions } = useSessions({ agent_id: agentId })
  const { data: squads = [] } = useSquads(activeProject?.id || '')
  const { data: threads = [] } = useMailThreads(activeProject?.id)
  const modelsQuery = useModels(activeProject?.id || '') // Fetch models for context limits
  const stopSession = useStopSession()
  const createSession = useNewSession()
  const { addNotification } = useNotifications()
  const [editModalOpen, setEditModalOpen] = useState(false)

  const [historyFilter, setHistoryFilter] = useState<'active' | 'history' | 'all'>('active')
  const [activeTab, setActiveTab] = useState<'chat' | 'todos' | 'diff' | 'history'>('chat')

  const sessions = useMemo(() => {
    let filtered = allSessions
    if (historyFilter === 'active') filtered = allSessions.filter(s => ['running', 'pending', 'paused', 'starting'].includes(s.status))
    if (historyFilter === 'history') filtered = allSessions.filter(s => ['completed', 'failed', 'cancelled'].includes(s.status))
    return filtered.sort((a, b) => new Date(b.inserted_at).getTime() - new Date(a.inserted_at).getTime())
  }, [allSessions, historyFilter])
  
  // Sticky mode state per session (runtime only, not persisted)
  const [sessionModes, setSessionModes] = useState<Record<string, AgentMode>>({})
  const [selectedSessionId, setSelectedSessionId] = useState<string | null>(null)
  const [mobileSidebar, setMobileSidebar] = useState<'history' | 'info' | null>(null)

  const handleModeChange = (sessionId: string, mode: AgentMode) => {


    setSessionModes(prev => ({ ...prev, [sessionId]: mode }))
  }

  const agentData = squads.flatMap(s => s.agents ?? []).find(a => a.id === agentId)
  
  // Find the active session for this agent
  const activeSession = sessions.find(s => ['running', 'starting', 'pending'].includes(s.status))

  // The session we are currently viewing
  const currentSession = useMemo(() => {
    if (selectedSessionId) {
      return allSessions.find(s => s.id === selectedSessionId)
    }
    // Fallback to active session or the latest one
    return allSessions.find(s => ['running', 'starting', 'pending', 'paused'].includes(s.status)) || allSessions[0]
  }, [allSessions, selectedSessionId])

  useEffect(() => {
    if (!selectedSessionId && currentSession) {
      setSelectedSessionId(currentSession.id)
    }
  }, [currentSession, selectedSessionId])
  
  // Find active model info if available
  const activeModelId = currentSession?.model || agentData?.model || ''
  const activeModelInfo = modelsQuery.data?.find(m => m.id === activeModelId || m.model_id === activeModelId || `${m.provider_id}/${m.model_id}` === activeModelId)

  // Filter mail threads where this agent is a participant
  const agentThreads = threads.filter(t => t.participants.includes(agentData?.name || agentId))

  const { data: events = [] } = useEvents({
    agent_id: agentId,
    limit: 50
  })

  const handleStopSession = async () => {
    if (!activeSession) return
    const reason = prompt('Please provide a reason for terminating this session (optional):')
    if (reason === null) return // User cancelled prompt

    try {
      await stopSession.mutateAsync({ session_id: activeSession.id, reason: reason || undefined })
      addNotification({
        type: 'success',
        title: 'Session Terminated',
        message: 'The agent session has been stopped successfully.'
      })
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Action Failed',
        message: error instanceof Error ? error.message : 'Failed to stop session'
      })
    }
  }

  const handleStartSession = async () => {
    if (!agentData) return

    try {
      // Use the dedicated atomic /new endpoint instead of just creating a session
      // This ensures previous sessions are stopped and the new one is started on OpenCode
      const newSession = await createSession.mutateAsync({
        agent_id: agentData.id,
        title: `Session for ${agentData.name}`,
      })
      setSelectedSessionId(newSession.id)
      addNotification({
        type: 'success',
        title: 'Session Started',
        message: `Session started for ${agentData.name}.`
      })
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Start Failed',
        message: error instanceof Error ? error.message : 'Failed to start session'
      })
    }
  }

  if (isLoadingSessions) {
    return (
      <div className="h-full flex items-center justify-center">
        <Loader2 className="animate-spin text-tui-accent" size={32} />
      </div>
    )
  }

  // Use real agent data or fallback
  const agent = {
    id: agentId,
    name: agentData?.name || 'AGENT_' + agentId.slice(0, 4),
    role: agentData?.role || 'CORE_WORKER',
    status: activeSession ? 'ACTIVE' : (agentData?.status === 'working' ? 'WORKING' : 'IDLE'),
    model: currentSession?.model || agentData?.model || 'gpt-4o',
    session_id: currentSession?.id || 'NO_SESSION',
    uptime: 'N/A',
    last_active: events[0]?.occurred_at ? new Date(events[0].occurred_at).toLocaleTimeString() : 'Never'
  }

  return (
    <div className="space-y-4 md:space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start gap-4 border-b border-tui-border pb-4 md:pb-6">
        <div className="flex items-center gap-3 md:gap-4">
          <div className="w-12 h-12 md:w-16 md:h-16 border border-tui-border flex items-center justify-center bg-tui-dim/10 shrink-0">
            <Cpu size={24} className="text-tui-accent md:hidden" />
            <Cpu size={32} className="text-tui-accent hidden md:block" />
          </div>
          <div>
            <div className="flex items-center gap-3 flex-wrap">
              <h2 className="text-2xl md:text-3xl font-bold tracking-tighter uppercase">{agent.name}</h2>
              <span className={`text-xs px-2 py-0.5 border font-bold ${activeSession ? 'border-tui-accent text-tui-accent' : 'border-tui-dim text-tui-dim'}`}>
                {agent.status}
              </span>
              <button 
                onClick={() => setEditModalOpen(true)}
                disabled={!agentData}
                className="p-1 text-tui-dim hover:text-tui-accent transition-colors focus:outline-none"
                title="Edit Agent"
              >
                <Pencil size={14} />
              </button>
            </div>
            <p className="text-tui-dim font-bold tracking-widest text-xs mt-1 flex items-center gap-2 flex-wrap">
              <span>{agent.role}</span>
              <span>•</span>
              <span title={activeModelInfo ? `Context: ${activeModelInfo.context_window || '?'} • Output: ${activeModelInfo.max_output || '?'}` : 'Model details unavailable'}>
                {agent.model}
                {activeModelInfo && (activeModelInfo.context_window || activeModelInfo.max_output) && (
                   <span className="ml-1 text-[10px] opacity-70">
                     ({activeModelInfo.context_window ? `${Math.round(activeModelInfo.context_window / 1000)}k` : '?'} / {activeModelInfo.max_output ? `${Math.round(activeModelInfo.max_output / 1000)}k` : '?'})
                   </span>
                )}
              </span>
            </p>
          </div>
        </div>

        <div className="flex items-start justify-end gap-2 sm:gap-3">
          <div className="flex sm:hidden gap-1">
            <button
              onClick={() => setMobileSidebar('history')}
              className={cn(
                "p-2 border border-tui-border hover:text-tui-accent transition-colors",
                mobileSidebar === 'history' && "text-tui-accent border-tui-accent bg-tui-accent/10"
              )}
              title="Session History"
            >
              <History size={16} />
            </button>
            <button
              onClick={() => setMobileSidebar('info')}
              className={cn(
                "p-2 border border-tui-border hover:text-tui-accent transition-colors",
                mobileSidebar === 'info' && "text-tui-accent border-tui-accent bg-tui-accent/10"
              )}
              title="Agent Info"
            >
              <Info size={16} />
            </button>
          </div>
          <div className="text-left sm:text-right space-y-1 hidden xs:block">
            <div className="text-xs text-tui-dim uppercase tracking-widest">
              {currentSession?.status === 'running' ? 'Active Session' : 'Historical Session'}
            </div>
            <div className="text-sm font-bold text-tui-text font-mono truncate max-w-[200px] sm:max-w-none">
              {currentSession?.id || 'NONE'}
            </div>
          </div>
          <button
            onClick={handleStartSession}
            disabled={!agentData || createSession.isPending}
            className="p-2 border border-tui-accent text-tui-accent hover:bg-tui-accent/10 transition-colors focus:outline-none disabled:opacity-50"
            title="Start New Session"
            aria-label="Start new session"
          >
            {createSession.isPending ? <Loader2 size={16} className="animate-spin" /> : <Play size={16} />}
          </button>
        </div>
      </div>

      <div className="flex flex-col lg:flex-row gap-4 md:gap-6 min-h-0 flex-1 overflow-hidden relative">
        {/* Mobile Sidebar Overlay */}
        {mobileSidebar && (
          <div 
            className="fixed inset-0 bg-black/60 z-40 lg:hidden transition-opacity duration-300"
            onClick={() => setMobileSidebar(null)}
          />
        )}

        {/* Sidebar: Session History */}
        <aside className={cn(
          "w-full sm:w-80 lg:w-72 shrink-0 flex flex-col border border-tui-border lg:h-full transition-transform duration-300 ease-in-out",
          "lg:static lg:translate-x-0",
          "fixed inset-y-0 left-0 z-50 bg-tui-bg lg:bg-transparent",
          mobileSidebar === 'history' 
            ? "translate-x-0" 
            : "-translate-x-full lg:translate-x-0"
        )}>
          <div className="p-2 border-b border-tui-border bg-tui-dim/10 flex flex-col gap-2">
            <div className="flex items-center justify-between">
              <div className="flex items-center gap-2 text-xs font-bold uppercase tracking-widest">
                <Archive size={14} />
                Session History
              </div>
              <div className="flex items-center gap-1">
                <button
                  onClick={handleStartSession}
                  disabled={!agentData || createSession.isPending}
                  className="p-1 hover:text-tui-accent transition-colors disabled:opacity-50"
                  title="New Session"
                >
                  <Pencil size={14} />
                </button>
                <button
                  onClick={() => setMobileSidebar(null)}
                  className="p-1 hover:text-tui-accent transition-colors lg:hidden"
                  title="Close"
                >
                  <X size={16} />
                </button>
              </div>
            </div>
            <div className="flex items-center gap-1 border border-tui-border p-0.5 bg-tui-bg">
               {(['active', 'history', 'all'] as const).map((f) => (
                <button
                  key={f}
                  onClick={() => setHistoryFilter(f)}
                  className={cn(
                    "flex-1 px-1 py-0.5 text-[8px] font-bold uppercase tracking-widest transition-colors",
                    historyFilter === f ? "bg-tui-accent text-tui-bg" : "text-tui-dim hover:text-tui-text"
                  )}
                >
                  {f}
                </button>
              ))}
            </div>
          </div>
          <div className="flex-1 overflow-y-auto divide-y divide-tui-border/50 bg-black/20">
            {sessions
              .map((s) => (
                <button
                  key={s.id}
                  onClick={() => {
                    setSelectedSessionId(s.id)
                    setMobileSidebar(null)
                  }}
                  className={cn(
                    'w-full text-left p-3 transition-colors hover:bg-tui-dim/5',
                    selectedSessionId === s.id ? 'bg-tui-accent/10 border-l-2 border-l-tui-accent' : ''
                  )}
                >
                  <div className="flex justify-between items-start mb-1 gap-2">
                    <span className={cn(
                      "text-[10px] font-bold uppercase px-1 border",
                      s.status === 'running' ? 'border-tui-accent text-tui-accent' : 'border-tui-dim text-tui-dim'
                    )}>
                      {s.status}
                    </span>
                    <span className="text-[9px] text-tui-dim font-mono">{new Date(s.inserted_at).toLocaleDateString()}</span>
                  </div>
                  <div className="text-xs font-bold text-tui-text truncate mb-1">
                    {(s.metadata?.title as string) || s.ticket_key || `Session ${s.id.slice(0, 8)}`}
                  </div>
                  <div className="text-[10px] text-tui-dim font-mono truncate">
                    {new Date(s.inserted_at).toLocaleTimeString()}
                  </div>
                </button>
              ))}
            {sessions.length === 0 && (
              <div className="p-4 text-xs text-tui-dim italic text-center">
                No history found.
              </div>
            )}
          </div>
        </aside>

        {/* Main Content: Chat & Events */}
        <div className="flex-1 flex flex-col gap-4 md:gap-6 min-w-0">
          {/* Chat Panel */}
          <section className="border border-tui-border flex flex-col flex-[2] min-h-[400px] lg:min-h-[500px]">
            {currentSession ? (
              <div className="flex-1 flex flex-col">
                <div className="flex items-center justify-between border-b border-tui-border bg-tui-dim/5 p-1">
                  <div className="flex items-center gap-1">
                    <TabButton 
                      active={activeTab === 'chat'} 
                      onClick={() => setActiveTab('chat')}
                      icon={<Terminal size={12} />}
                      label="CHAT"
                    />
                    <TabButton 
                      active={activeTab === 'todos'} 
                      onClick={() => setActiveTab('todos')}
                      icon={<ListTodo size={12} />}
                      label="TODOS"
                    />
                    <TabButton 
                      active={activeTab === 'diff'} 
                      onClick={() => setActiveTab('diff')}
                      icon={<FileDiff size={12} />}
                      label="DIFF"
                    />
                    <TabButton 
                      active={activeTab === 'history'} 
                      onClick={() => setActiveTab('history')}
                      icon={<History size={12} />}
                      label="HISTORY"
                    />
                  </div>
                  {currentSession.status === 'running' && (
                    <div className="px-2 py-0.5 text-[10px] font-bold text-tui-accent flex items-center gap-1">
                      <div className="w-1.5 h-1.5 rounded-full bg-tui-accent animate-pulse" />
                      RUNNING
                    </div>
                  )}
                </div>

                <div className="flex-1 overflow-hidden relative">
                  {activeTab === 'chat' && (
                    <SessionChat
                      session={currentSession}
                      mode={sessionModes[currentSession.id] || 'plan'}
                      onModeChange={(mode) => handleModeChange(currentSession.id, mode)}
                      onNewSession={handleStartSession}
                      showModeToggle={currentSession.status === 'running'}
                      showHeader={false}
                      className="h-full"
                    />
                  )}
                  {activeTab === 'todos' && (
                    <div className="h-full flex flex-col p-4 bg-black/20 overflow-y-auto">
                      <div className="text-xs font-bold uppercase tracking-widest text-tui-dim mb-4">Session Tasks</div>
                      <SessionTodos sessionId={currentSession.id} />
                    </div>
                  )}
                  {activeTab === 'diff' && (
                    <div className="h-full flex flex-col p-4 bg-black/20 overflow-y-auto font-mono text-xs">
                      <div className="text-xs font-bold uppercase tracking-widest text-tui-dim mb-4">Pending Changes</div>
                      <SessionDiff sessionId={currentSession.id} />
                    </div>
                  )}
                  {activeTab === 'history' && (
                    <div className="h-full flex flex-col p-4 bg-black/20 overflow-y-auto">
                      <div className="text-xs font-bold uppercase tracking-widest text-tui-dim mb-4">Event Timeline</div>
                      <EventTimeline events={events} />
                    </div>
                  )}
                </div>
              </div>
            ) : (
              <div className="flex-1 flex flex-col items-center justify-center text-center text-tui-dim gap-2 bg-black/40 p-4">
                <div className="text-xs uppercase tracking-widest">NO_SESSION_SELECTED</div>
                <div className="text-[10px] italic">Start a session to begin chatting with this agent.</div>
                <button
                  onClick={handleStartSession}
                  className="mt-4 px-4 py-2 border border-tui-accent text-tui-accent hover:bg-tui-accent/10 text-xs font-bold uppercase tracking-widest"
                >
                  Start New Session
                </button>
              </div>
            )}
          </section>

          {/* Events Section */}
          <section className="border border-tui-border flex flex-col flex-1 min-h-[200px] lg:min-h-[250px]">
            <div className="p-2 border-b border-tui-border bg-tui-dim/10 flex items-center justify-between">
              <div className="flex items-center gap-2 text-xs font-bold">
                <Activity size={14} />
                AGENT_EVENTS
              </div>
              <span className="text-xs text-tui-dim italic hidden sm:block">tail -f /logs/agent.log</span>
            </div>
            <div className="flex-1 overflow-y-auto p-3 md:p-4 bg-black/40 font-mono text-[10px] sm:text-xs space-y-1">
              {events.length === 0 && (
                <div className="text-tui-dim italic">No events recorded for this agent.</div>
              )}
              {events.map((event) => (
                <LogEntry 
                  key={event.id}
                  time={new Date(event.occurred_at).toLocaleTimeString()} 
                  level={event.kind.includes('fail') || event.kind.includes('error') ? 'ERROR' : 'INFO'} 
                  msg={`${event.kind.toUpperCase()}: ${JSON.stringify(event.payload)}`} 
                />
              ))}
              {activeSession && (
                <div className="animate-pulse inline-block w-2 h-4 bg-tui-text ml-1 align-middle" />
              )}
            </div>
          </section>
        </div>

        {/* Right Sidebar: Context & Info */}
        <aside className={cn(
          "w-full sm:w-80 lg:w-80 shrink-0 flex flex-col lg:h-full gap-4 md:gap-6 transition-transform duration-300 ease-in-out",
          "lg:static lg:translate-x-0",
          "fixed inset-y-0 right-0 z-50 bg-tui-bg lg:bg-transparent p-4 lg:p-0 overflow-y-auto",
          mobileSidebar === 'info' 
            ? "translate-x-0" 
            : "translate-x-full lg:translate-x-0"
        )}>
          {mobileSidebar === 'info' && (
            <div className="flex justify-between items-center mb-4 lg:hidden">
              <div className="text-xs font-bold uppercase tracking-widest flex items-center gap-2">
                <Info size={16} className="text-tui-accent" />
                Agent Information
              </div>
              <button
                onClick={() => setMobileSidebar(null)}
                className="p-2 border border-tui-border hover:text-tui-accent transition-colors"
              >
                <X size={20} />
              </button>
            </div>
          )}
          <section className="border border-tui-border">
            <div className="p-2 border-b border-tui-border bg-tui-dim/10 flex items-center gap-2 text-xs font-bold">
              <Activity size={14} />
              STATISTICS
            </div>
            <div className="p-3 md:p-4 space-y-4">
              <StatItem label="TOTAL_SESSIONS" value={sessions.length.toString()} />
              <StatItem label="LAST_ACTIVE" value={agent.last_active} />
              <StatItem label="TOTAL_EVENTS" value={events.length.toString()} />
            </div>
          </section>

          <section className="border border-tui-border shrink-0">
            <div className="p-2 border-b border-tui-border bg-tui-dim/10 flex items-center justify-between">
              <div className="flex items-center gap-2 text-xs font-bold">
                <Mail size={14} />
                AGENT_MAILBOX
              </div>
              <Link to="/mail">
                <ChevronRight size={14} className="text-tui-dim hover:text-tui-accent" />
              </Link>
            </div>
            <div className="divide-y divide-tui-border">
              {agentThreads.length === 0 ? (
                <div className="p-4 text-xs text-tui-dim italic text-center">
                  No active mail for this agent.
                </div>
              ) : (
                agentThreads.slice(0, 5).map(thread => (
                  <Link 
                    key={thread.id} 
                    to="/mail" 
                    className="p-3 block hover:bg-tui-dim/5 transition-colors"
                  >
                    <div className="flex justify-between items-start mb-1 gap-2">
                      <span className="text-xs font-bold text-tui-text truncate">{thread.subject}</span>
                      <span className="text-xs text-tui-dim whitespace-nowrap">{new Date(thread.last_message_at).toLocaleTimeString()}</span>
                    </div>
                    <div className="flex items-center gap-2">
                      <Inbox size={12} className={thread.unread_count > 0 ? 'text-tui-accent' : 'text-tui-dim'} />
                      <span className="text-xs text-tui-dim uppercase">{thread.message_count} MSGS</span>
                    </div>
                  </Link>
                ))
              )}
            </div>
          </section>

          {activeSession ? (
            <button 
              onClick={handleStopSession}
              disabled={stopSession.isPending}
              className="w-full border border-red-900/50 bg-red-950/20 py-3 text-red-500 font-bold text-xs hover:bg-red-900/30 transition-colors uppercase tracking-widest disabled:opacity-50 disabled:cursor-not-allowed shrink-0"
            >
              {stopSession.isPending ? 'Terminating...' : 'Terminate Session'}
            </button>
          ) : (
            <button
              onClick={handleStartSession}
              disabled={!agentData || createSession.isPending}
              className="w-full border border-tui-accent bg-tui-accent/10 py-3 text-tui-accent font-bold text-xs hover:bg-tui-accent hover:text-tui-bg transition-colors uppercase tracking-widest disabled:opacity-50 disabled:cursor-not-allowed flex items-center justify-center gap-2 shrink-0"
            >
              {createSession.isPending ? <Loader2 size={14} className="animate-spin" /> : <Play size={14} />}
              {createSession.isPending ? 'Starting...' : 'Start Session'}
            </button>
          )}

          {currentSession?.status !== 'running' && currentSession?.metadata && (
            <section className="border border-tui-border shrink-0">
              <div className="p-2 border-b border-tui-border bg-tui-dim/10 flex items-center gap-2 text-xs font-bold uppercase">
                <Archive size={14} />
                Termination Metadata
              </div>
              <div className="p-3 space-y-2 text-[10px] font-mono">
                {currentSession.metadata.terminated_by ? (
                  <div className="flex justify-between">
                    <span className="text-tui-dim">BY:</span>
                    <span className="text-tui-text font-bold">{(currentSession.metadata.terminated_by as string).toUpperCase()}</span>
                  </div>
                ) : null}
                {currentSession.metadata.terminated_at ? (
                  <div className="flex justify-between">
                    <span className="text-tui-dim">AT:</span>
                    <span className="text-tui-text">{new Date(currentSession.metadata.terminated_at as string).toLocaleString()}</span>
                  </div>
                ) : null}
                {currentSession.metadata.termination_reason ? (
                  <div className="mt-1 border-t border-tui-border/30 pt-1">
                    <div className="text-tui-dim mb-0.5">REASON:</div>
                    <div className="text-tui-text italic">{currentSession.metadata.termination_reason as string}</div>
                  </div>
                ) : null}
              </div>
            </section>
          )}
        </aside>
      </div>

      {agentData && activeProject && (
        <EditAgentModal
          isOpen={editModalOpen}
          onClose={() => setEditModalOpen(false)}
          agent={agentData}
          projectId={activeProject.id}
        />
      )}
    </div>
  )
}


function LogEntry({ time, level, msg }: { time: string; level: string; msg: string }) {
  const levelColors = {
    INFO: 'text-tui-text',
    DEBUG: 'text-tui-dim',
    WARN: 'text-yellow-500',
    ERROR: 'text-red-500',
  }
  return (
    <div className="flex gap-3">
      <span className="text-tui-dim whitespace-nowrap">[{time}]</span>
      <span className={levelColors[level as keyof typeof levelColors]}>{level}</span>
      <span className="text-tui-text/80 break-all">{msg}</span>
    </div>
  )
}

function StatItem({ label, value }: { label: string; value: string }) {
  return (
    <div className="flex justify-between items-center">
      <span className="text-xs text-tui-dim font-bold tracking-widest">{label}</span>
      <span className="text-sm font-bold">{value}</span>
    </div>
  )
}


interface EditAgentModalProps {
  isOpen: boolean
  onClose: () => void
  agent: Agent
  projectId: string
}

function EditAgentModal({ isOpen, onClose, agent, projectId }: EditAgentModalProps) {
  const { data: roleConfig } = useAgentRolesConfig()
  const modelsQuery = useModels(projectId)
  const syncProviders = useSyncProviders()
  const { addNotification } = useNotifications()
  const updateAgent = useUpdateAgent()

  const models = modelsQuery.data ?? []

  const [model, setModel] = useState(agent.model || '')
  const [role, setRole] = useState(agent.role)
  const [level, setLevel] = useState<Agent['level']>(agent.level)
  const [systemInstruction, setSystemInstruction] = useState(agent.system_instruction || '')
  
  // Reset form when modal opens or agent changes
  useEffect(() => {
    if (isOpen) {
      setModel(agent.model || '')
      setRole(agent.role)
      setLevel(agent.level)
      setSystemInstruction(agent.system_instruction || '')
    }
  }, [isOpen, agent])

  const defaultSystemInstruction = roleConfig?.system_instructions?.[role]?.[level] ?? ''

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    try {
      await updateAgent.mutateAsync({
        id: agent.id,
        squad_id: agent.squad_id,
        model: model || undefined,
        role,
        level,
        system_instruction: systemInstruction.trim() || undefined,
      })
      
      addNotification({
        type: 'success',
        title: 'Agent Updated',
        message: `Agent "${agent.name}" has been updated`,
      })
      onClose()
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Update Failed',
        message: err instanceof Error ? err.message : 'Failed to update agent',
      })
    }
  }

  return (
    <Modal isOpen={isOpen} onClose={onClose} title={`Edit Agent: ${agent.name}`} size="md">
      <form onSubmit={handleSubmit} className="space-y-4">
        <FormField
          label="Role"
          hint={
            roleConfig?.roles.find((r) => r.id === role)?.description ||
            'Select what this agent is best suited for'
          }
        >
          <select
            value={role}
            onChange={(e) => setRole(e.target.value)}
            className="w-full px-3 py-2 bg-tui-bg border border-tui-border text-tui-text focus:border-tui-accent focus:outline-none"
            disabled={!roleConfig}
          >
            {roleConfig ? (
              roleConfig.roles.map((r) => (
                <option key={r.id} value={r.id}>
                  {r.label}
                </option>
              ))
            ) : (
              <option value={role}>Loading roles...</option>
            )}
          </select>
        </FormField>

        <FormField label="Level" hint="Seniority influences default system instruction">
          <select
            value={level}
            onChange={(e) => setLevel(e.target.value as Agent['level'])}
            className="w-full px-3 py-2 bg-tui-bg border border-tui-border text-tui-text focus:border-tui-accent focus:outline-none"
            disabled={!roleConfig}
          >
            {roleConfig ? (
              roleConfig.levels.map((l) => (
                <option key={l.id} value={l.id}>
                  {l.label}
                </option>
              ))
            ) : (
              <option value={level}>Loading levels...</option>
            )}
          </select>
        </FormField>

        <FormField label="Default System Instruction" hint="Derived from role + level">
          <textarea
            value={defaultSystemInstruction || 'Loading...'}
            readOnly
            rows={6}
            className="w-full px-3 py-2 bg-tui-bg border border-tui-border rounded text-xs text-tui-text focus:outline-none"
          />
        </FormField>

        <FormField label="System Instruction Override" hint="Optional: overrides the default system instruction">
          <textarea
            value={systemInstruction}
            onChange={(e) => setSystemInstruction(e.target.value)}
            rows={6}
            placeholder="Optional override (leave blank to use the default)"
            className="w-full px-3 py-2 bg-tui-bg border border-tui-border rounded text-xs text-tui-text focus:border-tui-accent focus:outline-none"
          />
        </FormField>

        <FormField label="Model" hint="Available models from configured providers">
          <div className="space-y-2">
            <div className="flex items-center gap-2">
              <select
                value={model}
                onChange={(e) => setModel(e.target.value)}
                className="flex-1 px-3 py-2 bg-tui-bg border border-tui-border text-tui-text focus:border-tui-accent focus:outline-none"
                disabled={modelsQuery.isLoading || models.length === 0}
              >
                {models.length === 0 ? (
                  <option value="">No providers configured</option>
                ) : (
                  <>
                    <option value="">Default (Auto)</option>
                    {models.map((m) => (
                      <option key={m.id} value={m.id}>
                        {m.id}
                      </option>
                    ))}
                  </>
                )}
              </select>
              <Button
                type="button"
                variant="secondary"
                size="sm"
                onClick={() => syncProviders.mutate({ project_id: projectId })}
                disabled={!projectId || syncProviders.isPending}
              >
                {syncProviders.isPending ? 'Syncing...' : 'Sync'}
              </Button>
            </div>
            
            {!modelsQuery.isLoading && models.length === 0 && (
              <div className="text-xs text-tui-dim">no providers configured</div>
            )}
          </div>
        </FormField>

        <div className="flex justify-end gap-3 pt-2">
          <Button type="button" variant="secondary" onClick={onClose}>
            Cancel
          </Button>
          <Button 
            type="submit" 
            variant="primary"
            disabled={updateAgent.isPending}
          >
            {updateAgent.isPending ? 'Updating...' : 'Save Changes'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
