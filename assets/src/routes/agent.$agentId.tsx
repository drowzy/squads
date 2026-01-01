import { createFileRoute, Link } from '@tanstack/react-router'
import { 
  Terminal, 
  Mail, 
  Archive, 
  Activity, 
  Cpu,
  Clock,
  ChevronRight,
  Loader2,
  Inbox,
  Pencil
} from 'lucide-react'
import { useState, useEffect } from 'react'
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
  type Agent
} from '../api/queries'
import { useActiveProject } from './__root'
import { Modal, FormField, Input, Button } from '../components/Modal'
import { useNotifications } from '../components/Notifications'

export const Route = createFileRoute('/agent/$agentId')({
  component: AgentDetail,
})

function AgentDetail() {
  const { agentId } = Route.useParams()
  const { activeProject } = useActiveProject()
  const { data: sessions = [], isLoading: isLoadingSessions } = useSessions()
  const { data: squads = [] } = useSquads(activeProject?.id || '')
  const { data: threads = [] } = useMailThreads(activeProject?.id)
  const stopSession = useStopSession()
  const { addNotification } = useNotifications()
  const [editModalOpen, setEditModalOpen] = useState(false)

  const agentData = squads.flatMap(s => s.agents ?? []).find(a => a.id === agentId)
  
  // Find the active session for this agent
  const activeSession = sessions.find(s => s.agent_id === agentId && s.status === 'running')
  
  // Filter mail threads where this agent is a participant
  const agentThreads = threads.filter(t => t.participants.includes(agentData?.name || agentId))

  const { data: events = [], isLoading: isLoadingEvents } = useEvents({
    agent_id: agentId,
    limit: 50
  })

  const handleStopSession = async () => {
    if (!activeSession) return
    if (!confirm('Are you sure you want to terminate this session? The agent will stop working immediately.')) return

    try {
      await stopSession.mutateAsync({ session_id: activeSession.id })
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

  if (isLoadingSessions || isLoadingEvents) {
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
    model: activeSession?.model || agentData?.model || 'gpt-4o',
    session_id: activeSession?.id || 'NO_ACTIVE_SESSION',
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
              <span className={`text-xs px-2 py-0.5 border font-bold ${agent.status === 'ACTIVE' ? 'border-tui-accent text-tui-accent' : 'border-tui-dim text-tui-dim'}`}>
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
            <p className="text-tui-dim font-bold tracking-widest text-xs mt-1">
              {agent.role} • {agent.model}
            </p>
          </div>
        </div>

        <div className="text-left sm:text-right space-y-1">
          <div className="text-xs text-tui-dim">SESSION_ID</div>
          <div className="text-sm font-bold text-tui-text font-mono truncate max-w-[200px] sm:max-w-none">{agent.session_id}</div>
        </div>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-12 gap-4 md:gap-6">
        {/* Left Column: Logs & Activity */}
        <div className="lg:col-span-8 space-y-4 md:space-y-6">
          <section className="border border-tui-border flex flex-col h-[300px] md:h-[400px]">
            <div className="p-2 border-b border-tui-border bg-tui-dim/10 flex items-center justify-between">
              <div className="flex items-center gap-2 text-xs font-bold">
                <Terminal size={14} />
                AGENT_EVENTS
              </div>
              <span className="text-xs text-tui-dim italic hidden sm:block">tail -f /logs/agent.log</span>
            </div>
            <div className="flex-1 overflow-y-auto p-3 md:p-4 bg-black/40 font-mono text-xs space-y-1">
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
              {agent.status === 'ACTIVE' && (
                <div className="animate-pulse inline-block w-2 h-4 bg-tui-text ml-1 align-middle" />
              )}
            </div>
          </section>

          <section className="border border-tui-border">
            <div className="p-2 border-b border-tui-border bg-tui-dim/10 flex items-center gap-2 text-xs font-bold">
              <Archive size={14} />
              WORKTREE_STATUS
            </div>
            <div className="p-3 md:p-4 space-y-4">
              <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2 border-b border-tui-border/50 pb-2">
                <span className="text-xs text-tui-dim italic">Active Branch:</span>
                <span className="text-sm font-bold text-tui-accent font-mono">
                  {activeSession ? `session/${activeSession.id.slice(0, 8)}` : 'NONE'}
                </span>
              </div>
              <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-2">
                <span className="text-xs text-tui-dim italic">Reservation State:</span>
                <span className="text-xs font-bold text-tui-text font-mono border border-tui-border px-1">
                  {activeSession ? 'RESERVED_EXCLUSIVE' : 'RELEASED'}
                </span>
              </div>
            </div>
          </section>
        </div>

        {/* Right Column: Stats & Mail */}
        <div className="lg:col-span-4 space-y-4 md:space-y-6">
          <section className="border border-tui-border">
            <div className="p-2 border-b border-tui-border bg-tui-dim/10 flex items-center gap-2 text-xs font-bold">
              <Activity size={14} />
              STATISTICS
            </div>
            <div className="p-3 md:p-4 space-y-4">
              <StatItem label="UPTIME" value={agent.uptime} />
              <StatItem label="LAST_ACTIVE" value={agent.last_active} />
              <StatItem label="TOTAL_EVENTS" value={events.length.toString()} />
            </div>
          </section>

          <section className="border border-tui-border">
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

          {activeSession && (
            <button 
              onClick={handleStopSession}
              disabled={stopSession.isPending}
              className="w-full border border-red-900/50 bg-red-950/20 py-3 text-red-500 font-bold text-xs hover:bg-red-900/30 transition-colors uppercase tracking-widest disabled:opacity-50 disabled:cursor-not-allowed"
            >
              {stopSession.isPending ? 'Terminating...' : 'Terminate Session'}
            </button>
          )}
        </div>
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
