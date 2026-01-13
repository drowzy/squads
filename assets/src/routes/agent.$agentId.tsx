import { createFileRoute, Link } from '@tanstack/react-router'
import { Mail, Archive, Activity, Cpu, ChevronDown, Loader2, Inbox, Pencil, Play, X } from 'lucide-react'
import React, { useState, useEffect, useMemo } from 'react'

import {
  useEvents,
  useSessions,
  useMailThreads,
  useSquads,
  useStopSession,
  useAbortSession,
  useArchiveSession,
  useUpdateAgent,
  useAgentRolesConfig,
  useModels,
  useSyncProviders,
  useNewSession,
  useSessionMessages,
  useSessionTodos,
  useSessionDiff,
  type Agent,
} from '../api/queries'
import { EventTimeline } from '../components/events/EventTimeline'
import { useActiveProject } from './__root'
import { Modal, FormField, Button } from '../components/Modal'
import { useNotifications } from '../components/Notifications'
import { SessionChat, type AgentMode } from '../components/SessionChat'
import { AgentLayout } from '../components/AgentLayout'
import { cn } from '../lib/cn'

export const Route = createFileRoute('/agent/$agentId')({
  component: AgentDetail,
})

function SessionTodos({ sessionId }: { sessionId: string }) {
  const { data: todos, isLoading, error } = useSessionTodos(sessionId)

  if (isLoading) return <div className="animate-pulse text-tui-dim">Loading todos...</div>
  if (error) return <div className="text-red-500">Error loading todos</div>
  if (!todos || todos.length === 0) return <div className="text-tui-dim italic">No todos found for this session.</div>

  return (
    <div className="space-y-2">
      {todos.map((todo: any, idx: number) => (
        <div key={idx} className="flex items-start gap-3 p-2 border border-tui-border bg-ctp-crust/40">
          <div className={cn(
            "w-4 h-4 mt-0.5 border flex items-center justify-center shrink-0",
            todo.status === 'completed' ? "bg-tui-accent border-tui-accent" : "border-tui-border-dim"
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

function AgentDetail() {
  const { agentId } = Route.useParams()
  const { activeProject } = useActiveProject()
  const { data: allSessions = [], isLoading: isLoadingSessions } = useSessions({ agent_id: agentId })
  const { data: squads = [] } = useSquads(activeProject?.id || '')
  const { data: threads = [] } = useMailThreads(activeProject?.id)
  const modelsQuery = useModels(activeProject?.id || '') // Fetch models for context limits
  const stopSession = useStopSession()
  const abortSession = useAbortSession()
  const archiveSession = useArchiveSession()
  const createSession = useNewSession()
  const { addNotification } = useNotifications()
  const [editModalOpen, setEditModalOpen] = useState(false)

  const sessions = useMemo(() => {
    return allSessions.sort((a, b) => new Date(b.inserted_at).getTime() - new Date(a.inserted_at).getTime())
  }, [allSessions])
  
  // Sticky mode state per session (runtime only, not persisted)
  const [sessionModes, setSessionModes] = useState<Record<string, AgentMode>>({})
  const [selectedSessionId, setSelectedSessionId] = useState<string | null>(null)

  const handleModeChange = (sessionId: string, mode: AgentMode) => {


    setSessionModes(prev => ({ ...prev, [sessionId]: mode }))
  }

  const agentData = squads.flatMap(s => s.agents ?? []).find(a => a.id === agentId)
  
  // Find the active session for this agent
  const activeSession = allSessions.find(s => ['running', 'starting', 'pending'].includes(s.status))

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

  const { data: messages = [] } = useSessionMessages(currentSession?.id || '', {
    enabled: !!currentSession?.id,
    limit: 100,
  })

  const { data: sessionDiff } = useSessionDiff(currentSession?.id || '')

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

  const handleArchiveSession = async () => {
    if (!currentSession || currentSession.status === 'archived') return

    if (!confirm('Archive this session? You can still view it later from history.')) return

    try {
      await archiveSession.mutateAsync({ session_id: currentSession.id })
      addNotification({
        type: 'success',
        title: 'Session Archived',
        message: 'The session has been archived successfully.'
      })
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Archive Failed',
        message: error instanceof Error ? error.message : 'Failed to archive session'
      })
    }
  }

  const handleSelectSession = async (sessionId: string) => {
    if (currentSession && currentSession.id !== sessionId) {
      const shouldAbort = ['running', 'starting', 'pending'].includes(currentSession.status)

      if (shouldAbort) {
        try {
          await abortSession.mutateAsync({ session_id: currentSession.id })
        } catch (error) {
          console.warn('Failed to abort session before switching', error)
        }
      }
    }

    setSelectedSessionId(sessionId)
  }

  const handleStartSession = async () => {
    if (!agentData) return

    const sessionToAbort =
      currentSession && ['running', 'starting', 'pending'].includes(currentSession.status)
        ? currentSession
        : null

    try {
      if (sessionToAbort) {
        try {
          await abortSession.mutateAsync({ session_id: sessionToAbort.id })
        } catch (error) {
          console.warn('Failed to abort session before starting a new one', error)
        }
      }

      // Use the dedicated /new endpoint to start a fresh session on OpenCode
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
    name: agentData?.name || 'Agent ' + agentId.slice(0, 4),
    role: agentData?.role || 'Core Worker',
    status: activeSession ? 'Active' : (agentData?.status === 'working' ? 'Working' : 'Idle'),
    model: currentSession?.model || agentData?.model || 'gpt-4o',
    session_id: currentSession?.id || 'NO SESSION',
    uptime: 'N/A',
    last_active: events[0]?.occurred_at ? new Date(events[0].occurred_at).toLocaleTimeString() : 'Never'
  }

  return (
    <div className="h-full flex flex-col min-h-0 gap-3">
      {/* Header */}
      <div className="border border-tui-border bg-ctp-crust/20">
        <div className="p-3 md:p-4 space-y-3">
          <div className="flex flex-col lg:flex-row lg:items-start lg:justify-between gap-3">
            <div className="flex items-center gap-3 md:gap-4 min-w-0">
              <div className="w-12 h-12 md:w-16 md:h-16 border border-tui-border-dim flex items-center justify-center bg-ctp-crust/40 shrink-0">
                <Cpu size={24} className="text-tui-accent md:hidden" />
                <Cpu size={32} className="text-tui-accent hidden md:block" />
              </div>
              <div className="min-w-0">
                <div className="flex items-center gap-3 flex-wrap">
                  <h2 className="text-2xl md:text-3xl font-bold tracking-tighter truncate">{agent.name}</h2>
                  <span
                    className={`text-[10px] px-2 py-0.5 border font-bold uppercase tracking-widest ${activeSession ? 'border-tui-accent text-tui-accent bg-tui-accent/5' : 'border-tui-border-dim text-tui-dim'}`}
                  >
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
                <p className="text-tui-dim font-bold tracking-widest text-[10px] mt-1 flex items-center gap-2 flex-wrap">
                  <span className="truncate">{agent.role}</span>
                  <span>•</span>
                  <span
                    className="truncate"
                    title={
                      activeModelInfo
                        ? `Context: ${activeModelInfo.context_window || '?'} • Output: ${activeModelInfo.max_output || '?'}`
                        : 'Model details unavailable'
                    }
                  >
                    {agent.model}
                    {activeModelInfo && (activeModelInfo.context_window || activeModelInfo.max_output) && (
                      <span className="ml-1 text-[10px] opacity-70">
                        ({activeModelInfo.context_window ? `${Math.round(activeModelInfo.context_window / 1000)}k` : '?'} /{' '}
                        {activeModelInfo.max_output ? `${Math.round(activeModelInfo.max_output / 1000)}k` : '?'})
                      </span>
                    )}
                  </span>
                </p>
              </div>
            </div>

            <div className="flex flex-wrap items-start justify-end gap-2 shrink-0">
              <div className="text-left lg:text-right space-y-1 hidden sm:block">
                <div className="text-[10px] text-tui-dim tracking-widest uppercase font-bold">
                  {currentSession?.status === 'running' ? 'Active session' : currentSession ? 'Historical session' : 'No session'}
                </div>
                <div className="text-[10px] font-bold text-tui-text font-mono truncate max-w-[240px]">
                  {currentSession?.id || 'NONE'}
                </div>
              </div>

              {activeSession ? (
                <button
                  onClick={handleStopSession}
                  disabled={stopSession.isPending}
                  className="px-3 py-2 border border-red-900/50 bg-red-950/20 text-red-500 font-bold text-[10px] hover:bg-red-900/30 transition-colors uppercase tracking-widest disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {stopSession.isPending ? 'Terminating...' : 'Terminate'}
                </button>
              ) : (
                <button
                  onClick={handleStartSession}
                  disabled={!agentData || createSession.isPending}
                  className="px-3 py-2 border border-tui-accent bg-tui-accent/10 text-tui-accent font-bold text-[10px] hover:bg-tui-accent hover:text-tui-bg transition-colors uppercase tracking-widest disabled:opacity-50 disabled:cursor-not-allowed flex items-center gap-2"
                >
                  {createSession.isPending ? <Loader2 size={14} className="animate-spin" /> : <Play size={14} />}
                  {createSession.isPending ? 'Starting...' : 'Start session'}
                </button>
              )}

              {currentSession && currentSession.status !== 'archived' && (
                <button
                  onClick={handleArchiveSession}
                  disabled={archiveSession.isPending}
                  className="px-3 py-2 border border-tui-border bg-ctp-crust/40 text-tui-dim font-bold text-[10px] hover:text-tui-text hover:border-tui-accent transition-colors uppercase tracking-tui disabled:opacity-50 disabled:cursor-not-allowed"
                >
                  {archiveSession.isPending ? 'Archiving...' : 'Archive'}
                </button>
              )}
            </div>
          </div>

          <div className="flex flex-col xl:flex-row xl:items-end justify-between gap-3">
            <div className="flex items-center gap-2 min-w-0">
              <div className="text-[10px] text-tui-dim font-mono truncate">
                {currentSession ? `${currentSession.status.toUpperCase()} • ${currentSession.id.slice(0, 8)}` : 'No session'}
              </div>
            </div>

            <div className="flex flex-wrap gap-2">
              <HeaderStat label="Total sessions" value={allSessions.length.toString()} />
              <HeaderStat label="Total events" value={events.length.toString()} />
              <HeaderStat label="Last active" value={agent.last_active} />
            </div>
          </div>
        </div>
      </div>

      {/* Main View */}
      <section className="border border-tui-border flex flex-col flex-1 min-h-0 overflow-hidden">
        {currentSession ? (
          <AgentLayout
            agentId={agentId}
            currentSession={currentSession}
            sessions={allSessions}
            selectedSessionId={selectedSessionId || ''}
            onSessionSelect={handleSelectSession}
            onNewSession={handleStartSession}
            messages={messages}
            diffs={sessionDiff}
            onViewDiff={() => {}}
            logsContent={
              <div className="h-full flex flex-col">
                <div className="p-3 border-b border-tui-border bg-ctp-crust/40">
                  <div className="flex items-center gap-2 text-xs font-bold">
                    <Activity size={14} />
                    Agent events
                  </div>
                  <span className="text-xs text-tui-dim italic ml-auto">tail -f /logs/agent.log</span>
                </div>

                <div className="flex-1 overflow-y-auto p-3 md:p-4 font-mono text-[10px] sm:text-xs space-y-1">
                  {currentSession.status !== 'running' && currentSession.metadata && (
                    <div className="mb-4 border border-tui-border bg-ctp-crust/20">
                      <div className="p-2 border-b border-tui-border bg-ctp-crust/40 flex items-center gap-2 text-xs font-bold">
                        <Archive size={14} />
                        Termination metadata
                      </div>
                      <div className="p-3 space-y-2 text-[10px] font-mono">
                        {currentSession.metadata.terminated_by ? (
                          <div className="flex justify-between">
                            <span className="text-tui-dim">By:</span>
                            <span className="text-tui-text font-bold">{currentSession.metadata.terminated_by as string}</span>
                          </div>
                        ) : null}
                        {currentSession.metadata.terminated_at ? (
                          <div className="flex justify-between">
                            <span className="text-tui-dim">At:</span>
                            <span className="text-tui-text">{new Date(currentSession.metadata.terminated_at as string).toLocaleString()}</span>
                          </div>
                        ) : null}
                        {currentSession.metadata.termination_reason ? (
                          <div className="mt-1 border-t border-tui-border/30 pt-1">
                            <div className="text-tui-dim mb-0.5">Reason:</div>
                            <div className="text-tui-text italic">{currentSession.metadata.termination_reason as string}</div>
                          </div>
                        ) : null}
                      </div>
                    </div>
                  )}

                  {events.length === 0 && <div className="text-tui-dim italic">No events recorded for this agent.</div>}
                  {events.map((event) => (
                    <LogEntry
                      key={event.id}
                      time={new Date(event.occurred_at).toLocaleTimeString()}
                      level={event.kind.includes('fail') || event.kind.includes('error') ? 'ERROR' : 'INFO'}
                      msg={`${event.kind.charAt(0).toUpperCase() + event.kind.slice(1)}: ${JSON.stringify(event.payload)}`}
                    />
                  ))}

                  {activeSession && <div className="animate-pulse inline-block w-2 h-4 bg-tui-text ml-1 align-middle" />}
                </div>
              </div>
            }
            statsContent={
              <div className="p-4">
                <div className="text-xs font-bold text-tui-dim mb-4 uppercase tracking-widest">Session Stats</div>
                <div className="space-y-2">
                  <div className="border border-tui-border bg-ctp-crust/20 p-3">
                    <div className="text-[10px] text-tui-dim uppercase tracking-widest mb-1">Status</div>
                    <div className="text-sm font-bold text-tui-text">{currentSession.status.toUpperCase()}</div>
                  </div>
                  <div className="border border-tui-border bg-ctp-crust/20 p-3">
                    <div className="text-[10px] text-tui-dim uppercase tracking-widest mb-1">Model</div>
                    <div className="text-sm font-bold text-tui-text">{currentSession.model}</div>
                  </div>
                  <div className="border border-tui-border bg-ctp-crust/20 p-3">
                    <div className="text-[10px] text-tui-dim uppercase tracking-widest mb-1">Created</div>
                    <div className="text-sm font-bold text-tui-text">{new Date(currentSession.inserted_at).toLocaleString()}</div>
                  </div>
                </div>
              </div>
            }
            timelineContent={
              <div className="p-4">
                <div className="text-xs font-bold text-tui-dim mb-4 uppercase tracking-widest">Event Timeline</div>
                <EventTimeline events={events} />
              </div>
            }
            todosContent={
              <div className="p-4">
                <div className="text-xs font-bold text-tui-dim mb-4 uppercase tracking-widest">Session Tasks</div>
                <SessionTodos sessionId={currentSession.id} />
              </div>
            }
          >
            <SessionChat
              session={currentSession}
              mode={sessionModes[currentSession.id] || 'plan'}
              onModeChange={(mode) => handleModeChange(currentSession.id, mode)}
              onNewSession={handleStartSession}
              showModeToggle={currentSession.status === 'running'}
              showHeader={false}
              className="h-full"
            />
          </AgentLayout>
        ) : (
          <div className="flex-1 flex flex-col items-center justify-center text-center text-tui-dim gap-2 bg-ctp-mantle/50 p-4">
            <div className="text-xs uppercase tracking-tui font-bold">No session selected</div>
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

function HeaderStat({ label, value }: { label: string; value: string }) {
  return (
    <div className="border border-tui-border bg-ctp-crust/40 px-2 py-1">
      <div className="text-[8px] text-tui-dim font-bold uppercase tracking-widest">{label}</div>
      <div className="text-[10px] font-mono font-bold text-tui-text">{value}</div>
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
  const [advancedOpen, setAdvancedOpen] = useState(false)
  
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
            className="w-full px-3 py-2 bg-ctp-crust border border-tui-border-dim text-tui-text focus:border-tui-accent focus:outline-none"
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

        <FormField label="Level" hint="Seniority level of the agent">
          <select
            value={level}
            onChange={(e) => setLevel(e.target.value as Agent['level'])}
            className="w-full px-3 py-2 bg-ctp-crust border border-tui-border-dim text-tui-text focus:border-tui-accent focus:outline-none"
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

        <div className="border border-tui-border-dim bg-ctp-crust/20 overflow-hidden">
          <button
            type="button"
            onClick={() => setAdvancedOpen(!advancedOpen)}
            className="w-full flex items-center justify-between px-3 py-2 text-xs font-bold uppercase tracking-widest hover:bg-ctp-crust/40 transition-colors"
          >
            <span>Advanced Configuration</span>
            <ChevronDown size={14} className={cn("transition-transform", advancedOpen && "rotate-180")} />
          </button>
          
          {advancedOpen && (
            <div className="p-3 space-y-4 border-t border-tui-border-dim">
              <FormField 
                label="System Instruction" 
                hint="Leave blank to use the default instruction for this role and level"
              >
                <textarea
                  value={systemInstruction}
                  onChange={(e) => setSystemInstruction(e.target.value)}
                  rows={8}
                  placeholder={defaultSystemInstruction || "System instructions..."}
                  className="w-full px-3 py-2 bg-ctp-crust border border-tui-border-dim rounded text-xs text-tui-text focus:border-tui-accent focus:outline-none font-mono"
                />
              </FormField>

              <FormField label="Model" hint="Available models from configured providers">
                <div className="space-y-2">
                  <div className="flex items-center gap-2">
                    <select
                      value={model}
                      onChange={(e) => setModel(e.target.value)}
                      className="flex-1 px-3 py-2 bg-ctp-crust border border-tui-border-dim text-tui-text focus:border-tui-accent focus:outline-none"
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
            </div>
          )}
        </div>

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
