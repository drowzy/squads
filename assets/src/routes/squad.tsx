import { useNavigate, createFileRoute, Link } from '@tanstack/react-router'
import { Users, Shield, Cpu, Activity, ChevronRight, ChevronDown, Plus, MoreVertical, Pencil, Trash2, UserPlus, Play, StopCircle, MessageSquare, Eye, Radio, Server, Search } from 'lucide-react'
import { useEffect, useState } from 'react'
import {
  useSquads,
  useCreateSquad,
  useDeleteSquad,
  useCreateAgent,
  useDeleteAgent,
  useModels,
  useSyncProviders,
  useAgentRolesConfig,
  useSessions,
  useCreateSession,
  useStopSession,
  useSquadConnections,
  useMessageSquad,
  useMcpServers,
  useMcpCatalog,
  useMcpCliStatus,
  useCreateMcpServer,
  useEnableMcpServer,
  useDisableMcpServer,
  type Squad,
  type Agent,
  type SquadConnection,
  type McpServer,
  type McpCatalogEntry,
} from '../api/queries'
import { useActiveProject } from './__root'
import { Modal, FormField, Input, Button } from '../components/Modal'
import { useNotifications } from '../components/Notifications'
import { cn } from '../lib/cn'


export const Route = createFileRoute('/squad')({
  component: SquadOverview,
})

function SquadOverview() {
  const { activeProject, isLoading: projectsLoading } = useActiveProject()
  const projectId = activeProject?.id ?? ''
  const { data: squads, isLoading: squadsLoading } = useSquads(projectId)
  const { data: sessions = [] } = useSessions()
  const [createModalOpen, setCreateModalOpen] = useState(false)

  const isLoading = projectsLoading || (projectId && squadsLoading)

  return (
    <div className="space-y-4 md:space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
        <div>
          <h2 className="text-xl md:text-2xl font-bold tracking-tighter uppercase">Squad Command</h2>
          <p className="text-tui-dim text-xs md:text-sm italic">Manage squads and their agents</p>
        </div>
        <div className="flex items-center gap-3">
          {activeProject && (
            <div className="text-xs text-tui-dim font-bold tracking-widest border border-tui-border px-2 py-1">
              PROJECT: {activeProject.name.toUpperCase()}
            </div>
          )}
          <button
            onClick={() => setCreateModalOpen(true)}
            disabled={!projectId}
            aria-label="Create new squad"
            className={cn(
              "flex items-center gap-2 px-3 py-1.5 text-xs font-bold tracking-widest uppercase",
              "border border-tui-accent text-tui-accent",
              "hover:bg-tui-accent hover:text-tui-bg transition-colors",
              "disabled:opacity-50 disabled:cursor-not-allowed",
              "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-tui-bg focus:ring-tui-accent"
            )}
          >
            <Plus size={14} aria-hidden="true" />
            <span>New Squad</span>
          </button>
        </div>
      </div>

      {isLoading ? (
        <div className="p-12 border border-tui-border border-dashed text-center space-y-4 bg-ctp-mantle/50">
          <div className="text-tui-dim animate-pulse uppercase tracking-widest text-xs">
            Scanning neural networks...
          </div>
        </div>
      ) : !projectId ? (
        <div className="p-12 border border-tui-border border-dashed text-center space-y-4 bg-ctp-mantle/50">
          <div className="text-tui-dim uppercase tracking-widest text-xs">
            Select a project first
          </div>
        </div>
      ) : squads && squads.length > 0 ? (
        <div className="space-y-4">
          {squads.map((squad) => (
            <SquadCard key={squad.id} squad={squad} projectId={projectId} sessions={sessions} />
          ))}
        </div>
      ) : (
        <div className="p-16 border border-tui-border border-dashed text-center space-y-6 bg-ctp-mantle/50">
          <div className="flex justify-center">
            <div className="w-16 h-16 border border-tui-border-dim flex items-center justify-center bg-ctp-crust/40 text-tui-dim">
              <Users size={32} />
            </div>
          </div>
          <div className="space-y-2">
            <h3 className="text-lg font-bold uppercase tracking-widest">No Squads Deployed</h3>
            <p className="text-tui-dim text-sm max-w-md mx-auto italic">
              Deploy your first squad to begin coordinating agent operations.
            </p>
          </div>
          <button
            onClick={() => setCreateModalOpen(true)}
            className={cn(
              "inline-flex items-center gap-2 px-4 py-2 text-xs font-bold tracking-widest uppercase",
              "border border-tui-accent text-tui-accent",
              "hover:bg-tui-accent hover:text-tui-bg transition-colors",
              "focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-tui-bg focus:ring-tui-accent"
            )}
          >
            <Plus size={14} aria-hidden="true" />
            <span>Create First Squad</span>
          </button>
        </div>
      )}

      <CreateSquadModal
        isOpen={createModalOpen}
        onClose={() => setCreateModalOpen(false)}
        projectId={projectId}
      />
    </div>
  )
}

function SquadCard({ squad, projectId, sessions }: { squad: Squad; projectId: string; sessions: any[] }) {
  const [expanded, setExpanded] = useState(true)
  const [menuOpen, setMenuOpen] = useState(false)
  const [createAgentModalOpen, setCreateAgentModalOpen] = useState(false)
  const [messageModalOpen, setMessageModalOpen] = useState(false)
  const deleteSquad = useDeleteSquad()
  const { addNotification } = useNotifications()

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setMenuOpen(false)
      }
    }
    if (menuOpen) {
      window.addEventListener('keydown', handleKeyDown)
    }
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [menuOpen])

  const agents = squad.agents ?? []
  const activeAgents = agents.filter(a => a.status !== 'offline')
  const workingAgents = agents.filter(a => a.status === 'working')
  const opencodeStatus = squad.opencode_status ?? 'provisioning'
  const opencodeLabel =
    {
      idle: 'Idle',
      provisioning: 'Provisioning',
      running: 'OpenCode Online',
      error: 'OpenCode Error',
    }[opencodeStatus] ?? 'Provisioning'
  const opencodeTone =
    {
      idle: 'border-tui-border text-tui-dim',
      provisioning: 'border-ctp-peach text-ctp-peach',
      running: 'border-ctp-green text-ctp-green',
      error: 'border-ctp-red text-ctp-red',
    }[opencodeStatus] ?? 'border-ctp-peach text-ctp-peach'

  const handleDelete = async () => {
    if (!confirm(`Delete squad "${squad.name}"? This cannot be undone.`)) return
    
    try {
      await deleteSquad.mutateAsync({ id: squad.id, project_id: projectId })
      addNotification({
        type: 'success',
        title: 'Squad Deleted',
        message: `Squad "${squad.name}" has been removed`,
      })
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Delete Failed',
        message: err instanceof Error ? err.message : 'Failed to delete squad',
      })
    }
  }

  return (
    <div className="border border-tui-border bg-ctp-mantle/50">
      {/* Squad Header */}
      <div 
        className="flex items-center gap-3 p-3 md:p-4 cursor-pointer hover:bg-tui-dim/10 transition-colors"
        onClick={() => setExpanded(!expanded)}
      >
        <button 
          className="p-1 -m-1 text-tui-dim hover:text-tui-text focus:outline-none focus:ring-1 focus:ring-tui-accent rounded"
          aria-expanded={expanded}
          aria-label={expanded ? "Collapse squad details" : "Expand squad details"}
        >
          <ChevronDown 
            size={18} 
            aria-hidden="true"
            className={cn("transition-transform", !expanded && "-rotate-90")} 
          />
        </button>
        
        <div className="w-10 h-10 border border-tui-border flex items-center justify-center bg-ctp-crust/40 shrink-0">
          <Users className="text-tui-accent" size={18} />
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3">
            <h3 className="font-bold text-lg uppercase truncate">{squad.name}</h3>
            <span className="text-xs px-2 py-0.5 border border-tui-border text-tui-dim">
              {agents.length} agent{agents.length !== 1 ? 's' : ''}
            </span>
            <span className={cn("text-[10px] px-2 py-0.5 border uppercase tracking-widest", opencodeTone)}>
              {opencodeLabel}
            </span>
          </div>
          {squad.description && (
            <p className="text-xs text-tui-dim mt-0.5 truncate">{squad.description}</p>
          )}
        </div>

        <div className="flex items-center gap-4 shrink-0">
          <div className="text-right text-xs">
            <div className="text-tui-dim">
              {activeAgents.length}/{agents.length} online
            </div>
            {workingAgents.length > 0 && (
              <div className="text-tui-accent">
                {workingAgents.length} working
              </div>
            )}
          </div>

          <button
            onClick={(e) => {
              e.stopPropagation()
              setMessageModalOpen(true)
            }}
            className="p-2 text-tui-dim hover:text-tui-accent hover:bg-tui-dim/20 rounded focus:outline-none focus:ring-1 focus:ring-tui-accent"
            title="Message Connected Squads"
            aria-label={`Message squads connected to ${squad.name}`}
          >
            <Radio size={16} aria-hidden="true" />
          </button>

          <button
            onClick={(e) => {
              e.stopPropagation()
              setCreateAgentModalOpen(true)
            }}
            className="p-2 text-tui-dim hover:text-tui-accent hover:bg-tui-dim/20 rounded focus:outline-none focus:ring-1 focus:ring-tui-accent"
            title="Add Agent"
            aria-label={`Add agent to ${squad.name}`}
          >
            <UserPlus size={16} aria-hidden="true" />
          </button>

          <div className="relative">
            <button
              onClick={(e) => {
                e.stopPropagation()
                setMenuOpen(!menuOpen)
              }}
              className="p-2 text-tui-dim hover:text-tui-text hover:bg-tui-dim/20 rounded focus:outline-none focus:ring-1 focus:ring-tui-accent"
              aria-label="More squad actions"
              aria-expanded={menuOpen}
              aria-haspopup="true"
            >
              <MoreVertical size={16} aria-hidden="true" />
            </button>

            {menuOpen && (
              <>
                <div 
                  className="fixed inset-0 z-10" 
                  onClick={(e) => {
                    e.stopPropagation()
                    setMenuOpen(false)
                  }}
                  aria-hidden="true"
                />
                <div 
                  role="menu"
                  className="absolute right-0 mt-1 z-20 bg-ctp-mantle border border-tui-border rounded shadow-lg min-w-[140px]"
                >
            <button
              onClick={(e) => {
                e.stopPropagation()
                setMenuOpen(false)
                // TODO: Open edit modal
              }}
              className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-ctp-crust/40 focus:outline-none focus:bg-ctp-crust/40"
            >
              <Pencil size={14} aria-hidden="true" />
              Edit
            </button>
            <button
              role="menuitem"
              onClick={(e) => {
                e.stopPropagation()
                setMenuOpen(false)
                setMessageModalOpen(true)
              }}
              className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-ctp-crust/40 focus:outline-none focus:bg-ctp-crust/40"
            >
              <MessageSquare size={14} aria-hidden="true" />
              Message Squad
            </button>
            <button
              role="menuitem"
              onClick={(e) => {
                e.stopPropagation()
                setMenuOpen(false)
                handleDelete()
              }}
                    className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left text-ctp-red hover:bg-tui-dim/20 focus:outline-none focus:bg-tui-dim/20"
                  >
                    <Trash2 size={14} aria-hidden="true" />
                    Delete
                  </button>
                </div>
              </>
            )}
          </div>
        </div>
      </div>

      {/* Agents List */}
      {expanded && (
        <div className="border-t border-tui-border">
          {agents.length > 0 ? (
            agents.map((agent) => {
              const activeSession = sessions.find(s => s.agent_id === agent.id && s.status === 'running')
              return (
                <AgentRow 
                  key={agent.id} 
                  agent={agent} 
                  squadId={squad.id} 
                  activeSession={activeSession}
                />
              )
            })
          ) : (
            <div className="p-4 text-center text-xs text-tui-dim space-y-2">
              <div className="uppercase tracking-widest">No agents in this squad</div>
              <button
                onClick={() => setCreateAgentModalOpen(true)}
                className="text-tui-accent hover:underline"
              >
                Add first agent
              </button>
            </div>
          )}
          <SquadMcpPanel squadId={squad.id} />
        </div>
      )}

      <CreateAgentModal
        isOpen={createAgentModalOpen}
        onClose={() => setCreateAgentModalOpen(false)}
        projectId={projectId}
        squadId={squad.id}
        squadName={squad.name}
      />

      <MessageSquadModal
        isOpen={messageModalOpen}
        onClose={() => setMessageModalOpen(false)}
        squadId={squad.id}
        squadName={squad.name}
      />
    </div>
  )
}

function AgentRow({ agent, squadId, activeSession }: { agent: Agent; squadId: string; activeSession?: any }) {
  const [menuOpen, setMenuOpen] = useState(false)
  const deleteAgent = useDeleteAgent()
  const createSession = useCreateSession()
  const stopSession = useStopSession()
  const { addNotification } = useNotifications()
  const navigate = useNavigate()

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setMenuOpen(false)
      }
    }
    if (menuOpen) {
      window.addEventListener('keydown', handleKeyDown)
    }
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [menuOpen])

  const statusColors: Record<Agent['status'], string> = {
    idle: 'text-tui-dim',
    working: 'text-tui-accent',
    blocked: 'text-ctp-peach',
    offline: 'text-tui-border',
  }

  const statusLabels: Record<Agent['status'], string> = {
    idle: 'IDLE',
    working: 'WORKING',
    blocked: 'BLOCKED',
    offline: 'OFFLINE',
  }

  const handleStartSession = async (e: React.MouseEvent) => {
    e.preventDefault()
    e.stopPropagation()
    
    try {
      await createSession.mutateAsync({
        agent_id: agent.id,
        title: `Session for ${agent.name}`,
      })
      addNotification({
        type: 'success',
        title: 'Session Started',
        message: `Session started for ${agent.name}.`
      })
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Start Failed',
        message: error instanceof Error ? error.message : 'Failed to start session'
      })
    }
  }

  const handleStopSession = async (e: React.MouseEvent) => {
    e.preventDefault()
    e.stopPropagation()
    
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

  const handleDelete = async () => {
    if (!confirm(`Delete agent "${agent.name}"? This cannot be undone.`)) return
    
    try {
      await deleteAgent.mutateAsync({ id: agent.id, squad_id: squadId })
      addNotification({
        type: 'success',
        title: 'Agent Deleted',
        message: `Agent "${agent.name}" has been removed`,
      })
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Delete Failed',
        message: err instanceof Error ? err.message : 'Failed to delete agent',
      })
    }
  }

  return (
    <div className="flex items-center gap-3 px-3 md:px-4 py-3 md:pl-14 pl-3 hover:bg-tui-dim/10 transition-colors group border-b border-tui-border-dim last:border-b-0">
      <div className="flex items-center gap-3 flex-1 min-w-0">
        <div className="w-8 h-8 md:w-8 md:h-8 w-10 h-10 border border-tui-border-dim flex items-center justify-center bg-ctp-crust/40 shrink-0 group-hover:border-tui-accent">
          <Cpu className="text-tui-text" size={14} />
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex flex-col md:flex-row md:items-center gap-0 md:gap-2">
            <span className="font-bold uppercase truncate text-sm md:text-base">{agent.name}</span>
            <span className="text-xs text-tui-dim truncate">({agent.slug})</span>
          </div>
          {agent.model && (
            <div className="text-xs text-tui-dim truncate hidden md:block">{agent.model}</div>
          )}
        </div>
      </div>

      <div className="flex items-center gap-3 shrink-0">
        {activeSession ? (
          <>
            <div className="text-xs font-bold tracking-widest text-tui-accent animate-pulse hidden md:block">
              ACTIVE
            </div>
            <Link
              to="/agent/$agentId"
              params={{ agentId: agent.id }}
              className="p-1.5 md:p-1.5 p-2 text-tui-dim hover:text-tui-accent hover:bg-tui-dim/20 rounded focus:outline-none focus:ring-1 focus:ring-tui-accent z-10"
              title="Open Chat"
              onClick={(e) => e.stopPropagation()}
            >
              <MessageSquare size={16} className="md:w-4 md:h-4 w-5 h-5" />
            </Link>
            <button
              onClick={handleStopSession}
              disabled={stopSession.isPending}
              className="p-1.5 md:p-1.5 p-2 text-ctp-red hover:bg-ctp-red/10 rounded focus:outline-none focus:ring-1 focus:ring-ctp-red"
              title="Stop Session"
            >
              <StopCircle size={16} className="md:w-4 md:h-4 w-5 h-5" />
            </button>
          </>
        ) : (
          <>
            <div className={cn("text-xs font-bold tracking-widest hidden md:block", statusColors[agent.status])}>
              {statusLabels[agent.status]}
            </div>
            <button
              onClick={handleStartSession}
              disabled={createSession.isPending}
              className="p-1.5 md:p-1.5 p-2 text-tui-accent hover:bg-tui-accent/10 rounded focus:outline-none focus:ring-1 focus:ring-tui-accent opacity-0 group-hover:opacity-100 transition-opacity"
              title="Start Session"
            >
              <Play size={16} className="md:w-4 md:h-4 w-5 h-5" />
            </button>
          </>
        )}
      </div>

      <div className="relative shrink-0">
        <button
          onClick={(e) => {
            e.stopPropagation()
            setMenuOpen(!menuOpen)
          }}
          className="p-1.5 text-tui-dim hover:text-tui-text hover:bg-tui-dim/20 rounded opacity-0 group-hover:opacity-100 transition-opacity focus:opacity-100 focus:outline-none focus:ring-1 focus:ring-tui-accent"
          aria-label={`Actions for ${agent.name}`}
          aria-expanded={menuOpen}
          aria-haspopup="true"
        >
          <MoreVertical size={14} aria-hidden="true" />
        </button>

        {menuOpen && (
          <>
            <div 
              className="fixed inset-0 z-10" 
              onClick={(e) => {
                e.stopPropagation()
                setMenuOpen(false)
              }}
              aria-hidden="true"
            />
            <div 
              role="menu"
              className="absolute right-0 mt-1 z-20 bg-ctp-mantle border border-tui-border rounded shadow-lg min-w-[120px]"
            >
              <button
                role="menuitem"
                onClick={(e) => {
                  e.stopPropagation()
                  setMenuOpen(false)
                  navigate({ to: '/agent/$agentId', params: { agentId: agent.id } })
                }}
                className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-ctp-crust/40 focus:outline-none focus:bg-ctp-crust/40"
              >
                <Eye size={14} aria-hidden="true" />
                Details
              </button>
              <button
                role="menuitem"
                onClick={(e) => {
                  e.stopPropagation()
                  setMenuOpen(false)
                  // TODO: Implement edit agent
                }}
                className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-ctp-crust/40 focus:outline-none focus:bg-ctp-crust/40"
              >
                <Pencil size={14} aria-hidden="true" />
                Edit
              </button>
              <button
                role="menuitem"
                onClick={(e) => {
                  e.stopPropagation()
                  setMenuOpen(false)
                  handleDelete()
                }}
                className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left text-ctp-red hover:bg-tui-dim/20 focus:outline-none focus:bg-tui-dim/20"
              >
                <Trash2 size={14} aria-hidden="true" />
                Delete
              </button>
            </div>
          </>
        )}
      </div>
    </div>
  )
}


interface MessageSquadModalProps {
  isOpen: boolean
  onClose: () => void
  squadId: string
  squadName: string
}

function MessageSquadModal({ isOpen, onClose, squadId, squadName }: MessageSquadModalProps) {
  const [toSquadId, setToSquadId] = useState('')
  const [subject, setSubject] = useState('')
  const [body, setBody] = useState('')
  const [errors, setErrors] = useState<{ toSquadId?: string; subject?: string; body?: string }>({})

  const { data: connections = [] } = useSquadConnections({ squad_id: squadId })
  const messageSquad = useMessageSquad()
  const { addNotification } = useNotifications()

  // Filter for valid target squads
  const targetSquads = connections
    .map(c => {
      // Determine which squad is the "other" one
      if (c.from_squad_id === squadId) return c.to_squad
      if (c.to_squad_id === squadId) return c.from_squad
      return null
    })
    .filter((s): s is Squad => s !== null && s !== undefined)

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    const newErrors: typeof errors = {}
    if (!toSquadId) newErrors.toSquadId = 'Recipient squad is required'
    if (!subject.trim()) newErrors.subject = 'Subject is required'
    if (!body.trim()) newErrors.body = 'Message body is required'
    
    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors)
      return
    }

    try {
      await messageSquad.mutateAsync({
        from_squad_id: squadId,
        to_squad_id: toSquadId,
        subject: subject.trim(),
        body: body.trim(),
        sender_name: `Squad ${squadName}`
      })
      
      addNotification({
        type: 'success',
        title: 'Message Sent',
        message: `Message sent to squad.`
      })
      handleClose()
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Send Failed',
        message: err instanceof Error ? err.message : 'Failed to send message'
      })
    }
  }

  const handleClose = () => {
    setToSquadId('')
    setSubject('')
    setBody('')
    setErrors({})
    onClose()
  }

  return (
    <Modal isOpen={isOpen} onClose={handleClose} title="Message Squad" size="lg">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="text-xs text-tui-dim">
          Sending from <span className="text-tui-accent font-bold">{squadName}</span>
        </div>

        <FormField label="To Squad" error={errors.toSquadId}>
           <select
            value={toSquadId}
            onChange={(e) => {
              setToSquadId(e.target.value)
              setErrors(prev => ({ ...prev, toSquadId: undefined }))
            }}
            className="w-full px-3 py-2 bg-ctp-crust border border-tui-border-dim text-tui-text focus:border-tui-accent focus:outline-none"
            disabled={targetSquads.length === 0}
          >
            <option value="">Select recipient...</option>
            {targetSquads.map(s => (
              <option key={s.id} value={s.id}>
                {s.name} {s.project_name ? `(${s.project_name})` : ''}
              </option>
            ))}
          </select>
          {targetSquads.length === 0 && (
             <div className="text-xs text-ctp-peach mt-1">No connected squads found. Connect squads in Fleet Command first.</div>
          )}
        </FormField>

        <FormField label="Subject" error={errors.subject}>
          <Input
            value={subject}
            onChange={(e) => {
              setSubject(e.target.value)
              setErrors(prev => ({ ...prev, subject: undefined }))
            }}
            placeholder="Regarding deployment..."
            error={!!errors.subject}
          />
        </FormField>

        <FormField label="Message Body" hint="Markdown supported" error={errors.body}>
          <textarea
            value={body}
            onChange={(e) => {
              setBody(e.target.value)
              setErrors(prev => ({ ...prev, body: undefined }))
            }}
            rows={8}
            className="w-full px-3 py-2 bg-ctp-crust border border-tui-border-dim rounded text-sm text-tui-text focus:border-tui-accent focus:outline-none font-mono placeholder:text-tui-dim/30"
            placeholder="Write your message here..."
          />
        </FormField>

        <div className="flex justify-end gap-3 pt-2">
          <Button type="button" variant="secondary" onClick={handleClose}>
            Cancel
          </Button>
          <Button 
            type="submit" 
            variant="primary"
            disabled={messageSquad.isPending || targetSquads.length === 0}
          >
            {messageSquad.isPending ? 'Sending...' : 'Send Message'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}

function SquadMcpPanel({ squadId }: { squadId: string }) {
  const { data: servers = [], isLoading } = useMcpServers(squadId)
  const { data: cliStatus } = useMcpCliStatus()
  const createMcpServer = useCreateMcpServer()
  const enableMcpServer = useEnableMcpServer()
  const disableMcpServer = useDisableMcpServer()
  const { addNotification } = useNotifications()
  const [catalogOpen, setCatalogOpen] = useState(false)
  const [pendingName, setPendingName] = useState<string | null>(null)

  const cliAvailable = cliStatus?.available ?? true
  const cliMessage = cliStatus?.message

  const existingNames = new Set(servers.map(server => server.name))

  const handleAdd = async (entry: McpCatalogEntry) => {
    try {
      await createMcpServer.mutateAsync({
        squad_id: squadId,
        name: entry.name,
        source: 'registry',
        type: 'container',
        image: entry.image,
        catalog_meta: entry as Record<string, unknown>,
      })
      addNotification({
        type: 'success',
        title: 'MCP Added',
        message: `${entry.title || entry.name} has been added to the squad.`,
      })
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Add Failed',
        message: err instanceof Error ? err.message : 'Failed to add MCP server',
      })
    }
  }

  const handleToggle = async (server: McpServer) => {
    if (!cliAvailable) {
      addNotification({
        type: 'error',
        title: 'Docker MCP Unavailable',
        message: cliMessage || 'Install Docker MCP Toolkit to enable MCP servers.',
      })
      return
    }

    setPendingName(server.name)

    try {
      if (server.enabled) {
        await disableMcpServer.mutateAsync({ squad_id: squadId, name: server.name })
        addNotification({
          type: 'success',
          title: 'MCP Disabled',
          message: `${server.name} has been disabled.`,
        })
      } else {
        await enableMcpServer.mutateAsync({ squad_id: squadId, name: server.name })
        addNotification({
          type: 'success',
          title: 'MCP Enabled',
          message: `${server.name} has been enabled.`,
        })
      }
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'MCP Action Failed',
        message: err instanceof Error ? err.message : 'Failed to update MCP server',
      })
    } finally {
      setPendingName(null)
    }
  }

  return (
    <div className="border-t border-tui-border">
        <div className="flex items-center justify-between px-3 md:px-4 py-3 bg-ctp-crust/40">
          <div className="flex items-center gap-2 text-xs uppercase tracking-tui text-tui-dim font-bold">
          <Server size={14} aria-hidden="true" />
          MCP Servers
        </div>
        <button
          onClick={() => setCatalogOpen(true)}
          className={cn(
            "flex items-center gap-2 px-3 py-1.5 text-xs font-bold tracking-widest uppercase",
            "border border-tui-border text-tui-text",
            "hover:bg-tui-dim/20 transition-colors"
          )}
        >
          <Plus size={12} aria-hidden="true" />
          Add MCP
        </button>
      </div>

      {!cliAvailable && (
        <div className="px-3 md:px-4 py-2 text-xs text-ctp-peach border-t border-ctp-peach/40 bg-ctp-peach/10">
          Docker MCP Toolkit not detected. Enable/disable actions are disabled.
          {cliMessage ? ` ${cliMessage}` : ''}
        </div>
      )}

      {isLoading ? (
        <div className="p-4 text-xs text-tui-dim uppercase tracking-widest">Loading MCP status...</div>
      ) : servers.length > 0 ? (
        <div>
          {servers.map(server => {
            const meta = server.catalog_meta as {
              title?: string
              icon?: string
              tags?: string[]
              category?: string
              secrets?: unknown[]
              oauth?: unknown[]
              raw?: {
                oauth?: unknown[]
                config?: { secrets?: unknown[] }
              }
            } | null
            const displayTitle = meta?.title || server.name
            const iconUrl = meta?.icon
            const tags = Array.isArray(meta?.tags) ? meta?.tags.slice(0, 3) : []
            const oauth = Array.isArray(meta?.oauth)
              ? meta?.oauth
              : Array.isArray(meta?.raw?.oauth)
                ? meta?.raw?.oauth
                : []
            const secrets = Array.isArray(meta?.secrets)
              ? meta?.secrets
              : Array.isArray(meta?.raw?.config?.secrets)
                ? meta?.raw?.config?.secrets
                : []
            const authBadges = [oauth.length > 0 ? 'OAUTH' : null, secrets.length > 0 ? 'SECRET' : null]
              .filter(Boolean) as string[]
            const statusLabel = (server.status || 'unknown').toUpperCase()

            return (
              <div
                key={server.id}
                className="flex items-center gap-3 px-3 md:px-4 py-3 border-t border-tui-border-dim"
              >
                <div className="w-9 h-9 border border-tui-border-dim flex items-center justify-center bg-ctp-crust/40 shrink-0">
                  {iconUrl ? (
                    <img
                      src={iconUrl}
                      alt={`${displayTitle} icon`}
                      className="w-5 h-5 object-contain"
                      loading="lazy"
                      referrerPolicy="no-referrer"
                    />
                  ) : (
                    <Server size={14} className="text-tui-text" />
                  )}
                </div>

                <div className="flex-1 min-w-0">
                  <div className="flex items-center gap-2">
                    <span className="font-bold uppercase text-sm truncate">{displayTitle}</span>
                    {meta?.category && (
                      <span className="text-xs text-tui-dim">{meta.category}</span>
                    )}
                  </div>
                  <div className="text-xs text-tui-dim truncate">ID: {server.name}</div>
                  <div className="flex items-center gap-2 text-xs text-tui-dim mt-1">
                    <span className={server.enabled ? 'text-tui-accent' : 'text-tui-dim'}>
                      {server.enabled ? 'ENABLED' : 'DISABLED'}
                    </span>
                    <span className="text-tui-border">•</span>
                    <span>STATUS: {statusLabel}</span>
                  </div>
                  {(tags.length > 0 || authBadges.length > 0) && (
                    <div className="flex items-center flex-wrap gap-2 mt-2">
                      {authBadges.map(badge => (
                        <span
                          key={badge}
                          className="text-[10px] uppercase tracking-widest px-2 py-0.5 border border-ctp-peach text-ctp-peach"
                        >
                          {badge}
                        </span>
                      ))}
                      {tags.map(tag => (
                        <span
                          key={tag}
                          className="text-[10px] uppercase tracking-widest px-2 py-0.5 border border-tui-border text-tui-dim"
                        >
                          {tag}
                        </span>
                      ))}
                    </div>
                  )}
                  {server.last_error && (
                    <div className="text-xs text-ctp-red mt-2 truncate">
                      Last error: {server.last_error}
                    </div>
                  )}
                </div>

                <button
                  onClick={() => handleToggle(server)}
                  disabled={!cliAvailable || pendingName === server.name}
                  title={
                    !cliAvailable
                      ? cliMessage || 'Docker MCP Toolkit not detected.'
                      : undefined
                  }
                  className={cn(
                    "flex items-center gap-2 px-3 py-1.5 text-xs font-bold tracking-widest uppercase",
                    "border border-tui-border",
                    server.enabled
                      ? "text-ctp-red hover:bg-ctp-red/10"
                      : "text-tui-accent hover:bg-tui-accent/10",
                    (!cliAvailable || pendingName === server.name) && "opacity-60 cursor-not-allowed"
                  )}
                >
                  {server.enabled ? (
                    <StopCircle size={12} aria-hidden="true" />
                  ) : (
                    <Play size={12} aria-hidden="true" />
                  )}
                  {server.enabled ? 'Disable' : 'Enable'}
                </button>
              </div>
            )
          })}
        </div>
      ) : (
        <div className="p-4 text-center text-xs text-tui-dim space-y-2">
          <div className="uppercase tracking-widest">No MCP servers configured</div>
          <button
            onClick={() => setCatalogOpen(true)}
            className="text-tui-accent hover:underline"
          >
            Add MCP from catalog
          </button>
        </div>
      )}

      <McpCatalogModal
        isOpen={catalogOpen}
        onClose={() => setCatalogOpen(false)}
        existingNames={existingNames}
        onAdd={handleAdd}
      />
    </div>
  )
}

interface McpCatalogModalProps {
  isOpen: boolean
  onClose: () => void
  existingNames: Set<string>
  onAdd: (entry: McpCatalogEntry) => Promise<void>
}

function McpCatalogModal({ isOpen, onClose, existingNames, onAdd }: McpCatalogModalProps) {
  const [query, setQuery] = useState('')
  const [addingName, setAddingName] = useState<string | null>(null)
  const filters = query.trim() ? { query: query.trim() } : undefined
  const { data: entries = [], isLoading } = useMcpCatalog(filters)

  useEffect(() => {
    if (!isOpen) {
      setQuery('')
    }
  }, [isOpen])

  const handleAdd = async (entry: McpCatalogEntry) => {
    setAddingName(entry.name)
    try {
      await onAdd(entry)
    } catch {
      // Errors are surfaced via notifications in the parent.
    } finally {
      setAddingName(null)
    }
  }

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Docker MCP Catalog" size="lg">
      <div className="space-y-4">
        <FormField label="Search Catalog" hint="Search by name or title">
          <div className="relative">
            <Search size={14} className="absolute left-3 top-3 text-tui-dim" aria-hidden="true" />
            <Input
              value={query}
              onChange={(e) => setQuery(e.target.value)}
              placeholder="notion, github, slack..."
              className="pl-8"
            />
          </div>
        </FormField>

        {isLoading ? (
          <div className="text-xs text-tui-dim uppercase tracking-widest">Loading catalog...</div>
        ) : entries.length > 0 ? (
          <div className="max-h-[380px] overflow-y-auto space-y-2">
            {entries.map(entry => {
              const isAdded = existingNames.has(entry.name)
              const displayTitle = entry.title || entry.name
              const tags = Array.isArray(entry.tags) ? entry.tags.slice(0, 3) : []
              const oauth = Array.isArray(entry.oauth)
                ? entry.oauth
                : Array.isArray((entry.raw as { oauth?: unknown[] } | undefined)?.oauth)
                  ? (entry.raw as { oauth?: unknown[] }).oauth
                  : []
              const secrets = Array.isArray(entry.secrets)
                ? entry.secrets
                : Array.isArray((entry.raw as { config?: { secrets?: unknown[] } } | undefined)?.config?.secrets)
                  ? (entry.raw as { config?: { secrets?: unknown[] } }).config?.secrets
                  : []
              const authBadges = [oauth.length > 0 ? 'OAUTH' : null, secrets.length > 0 ? 'SECRET' : null]
                .filter(Boolean) as string[]

              return (
                <div key={entry.name} className="border border-tui-border bg-ctp-mantle/50">
                  <div className="flex items-center gap-3 p-3">
                    <div className="w-10 h-10 border border-tui-border-dim bg-ctp-crust/40 flex items-center justify-center shrink-0">
                      {entry.icon ? (
                        <img
                          src={entry.icon}
                          alt={`${displayTitle} icon`}
                          className="w-6 h-6 object-contain"
                          loading="lazy"
                          referrerPolicy="no-referrer"
                        />
                      ) : (
                        <Server size={16} className="text-tui-text" />
                      )}
                    </div>
                    <div className="flex-1 min-w-0">
                      <div className="flex items-center gap-2">
                        <span className="font-bold uppercase text-sm truncate">{displayTitle}</span>
                        {entry.category && (
                          <span className="text-xs text-tui-dim">{entry.category}</span>
                        )}
                      </div>
                      <div className="text-xs text-tui-dim truncate">{entry.name}</div>
                      {(tags.length > 0 || authBadges.length > 0) && (
                        <div className="flex items-center flex-wrap gap-2 mt-2">
                          {authBadges.map(badge => (
                            <span
                              key={badge}
                              className="text-[10px] uppercase tracking-widest px-2 py-0.5 border border-ctp-peach text-ctp-peach"
                            >
                              {badge}
                            </span>
                          ))}
                          {tags.map(tag => (
                            <span
                              key={tag}
                              className="text-[10px] uppercase tracking-widest px-2 py-0.5 border border-tui-border text-tui-dim"
                            >
                              {tag}
                            </span>
                          ))}
                        </div>
                      )}
                    </div>
                    <Button
                      type="button"
                      variant="secondary"
                      size="sm"
                      disabled={isAdded || addingName === entry.name}
                      onClick={() => handleAdd(entry)}
                    >
                      {isAdded ? 'Added' : addingName === entry.name ? 'Adding...' : 'Add'}
                    </Button>
                  </div>
                </div>
              )
            })}
          </div>
        ) : (
          <div className="text-xs text-tui-dim uppercase tracking-widest">No catalog entries found.</div>
        )}
      </div>
    </Modal>
  )
}

interface CreateSquadModalProps {
  isOpen: boolean
  onClose: () => void
  projectId: string
}

function CreateSquadModal({ isOpen, onClose, projectId }: CreateSquadModalProps) {
  const [name, setName] = useState('')
  const [description, setDescription] = useState('')
  const [errors, setErrors] = useState<{ name?: string }>({})
  
  const createSquad = useCreateSquad()
  const { addNotification } = useNotifications()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    if (!name.trim()) {
      setErrors({ name: 'Name is required' })
      return
    }
    
    try {
      await createSquad.mutateAsync({
        project_id: projectId,
        name: name.trim(),
        description: description.trim() || undefined,
      })
      addNotification({
        type: 'success',
        title: 'Squad Created',
        message: `Squad "${name}" has been created`,
      })
      setName('')
      setDescription('')
      setErrors({})
      onClose()
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Creation Failed',
        message: err instanceof Error ? err.message : 'Failed to create squad',
      })
    }
  }

  const handleClose = () => {
    setName('')
    setDescription('')
    setErrors({})
    onClose()
  }

  return (
    <Modal isOpen={isOpen} onClose={handleClose} title="Create Squad" size="md">
      <form onSubmit={handleSubmit} className="space-y-4">
        <FormField label="Squad Name" error={errors.name}>
          <Input
            type="text"
            value={name}
            onChange={(e) => {
              setName(e.target.value)
              setErrors({})
            }}
            placeholder="Alpha Team"
            error={!!errors.name}
          />
        </FormField>

        <FormField label="Description" hint="Optional description for this squad">
          <Input
            type="text"
            value={description}
            onChange={(e) => setDescription(e.target.value)}
            placeholder="Backend API specialists"
          />
        </FormField>

        <div className="flex justify-end gap-3 pt-2">
          <Button type="button" variant="secondary" onClick={handleClose}>
            Cancel
          </Button>
          <Button 
            type="submit" 
            variant="primary"
            disabled={createSquad.isPending}
          >
            {createSquad.isPending ? 'Creating...' : 'Create Squad'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}

interface CreateAgentModalProps {
  isOpen: boolean
  onClose: () => void
  projectId: string
  squadId: string
  squadName: string
}

function CreateAgentModal({ isOpen, onClose, projectId, squadId, squadName }: CreateAgentModalProps) {
  const { data: roleConfig } = useAgentRolesConfig()
  const modelsQuery = useModels(projectId)
  const syncProviders = useSyncProviders()

  const models = modelsQuery.data ?? []

  const [model, setModel] = useState<string>('')
  const [role, setRole] = useState('fullstack_engineer')
  const [level, setLevel] = useState<Agent['level']>('senior')
  const [systemInstruction, setSystemInstruction] = useState('')

  const [autoName, setAutoName] = useState(true)
  const [customName, setCustomName] = useState('')
  const [customSlug, setCustomSlug] = useState('')
  const [errors, setErrors] = useState<{ name?: string; slug?: string }>({})

  const createAgent = useCreateAgent()
  const { addNotification } = useNotifications()

  const defaultSystemInstruction = roleConfig?.system_instructions?.[role]?.[level] ?? ''

  useEffect(() => {
    if (!isOpen || !projectId) return
    syncProviders.mutate({ project_id: projectId })
  }, [isOpen, projectId])

  useEffect(() => {
    if (!isOpen) return
    if (model || models.length === 0) return
    setModel(models[0].id)
  }, [isOpen, model, models])

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    const newErrors: typeof errors = {}
    
    if (!autoName) {
      if (!customName.trim()) {
        newErrors.name = 'Name is required'
      } else if (!/^[A-Z][a-z]+[A-Z][a-z]+$/.test(customName.trim())) {
        newErrors.name = 'Must be AdjectiveNoun format (e.g. BluePanda)'
      }
      
      if (!customSlug.trim()) {
        newErrors.slug = 'Slug is required'
      } else if (!/^[a-z]+-[a-z]+$/.test(customSlug.trim())) {
        newErrors.slug = 'Must be lowercase hyphenated (e.g. blue-panda)'
      }
    }
    
    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors)
      return
    }
    
    try {
      const data: {
        squad_id: string
        model?: string
        role?: string
        level?: Agent['level']
        system_instruction?: string
        name?: string
        slug?: string
      } = {
        squad_id: squadId,
        model: model || undefined,
        role,
        level,
        system_instruction: systemInstruction.trim() || undefined,
      }
      
      if (!autoName) {
        data.name = customName.trim()
        data.slug = customSlug.trim()
      }
      
      const agent = await createAgent.mutateAsync(data)
      addNotification({
        type: 'success',
        title: 'Agent Created',
        message: `Agent "${agent.name}" has been added to ${squadName}`,
      })
      resetForm()
      onClose()
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Creation Failed',
        message: err instanceof Error ? err.message : 'Failed to create agent',
      })
    }
  }

  const resetForm = () => {
    setModel('')
    setRole('fullstack_engineer')
    setLevel('senior')
    setSystemInstruction('')
    setAutoName(true)
    setCustomName('')
    setCustomSlug('')
    setErrors({})
  }

  const handleClose = () => {
    resetForm()
    onClose()
  }

  // Auto-generate slug from name
  const handleNameChange = (value: string) => {
    setCustomName(value)
    setErrors({})
    
    // Convert AdjectiveNoun to adjective-noun
    const slugified = value
      .replace(/([A-Z])/g, '-$1')
      .toLowerCase()
      .replace(/^-/, '')
    setCustomSlug(slugified)
  }

  return (
    <Modal isOpen={isOpen} onClose={handleClose} title="Add Agent" size="md">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div className="text-xs text-tui-dim">
          Adding agent to <span className="text-tui-accent font-bold">{squadName}</span>
        </div>

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

        <FormField label="Level" hint="Seniority influences default system instruction">
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

        <FormField label="Default System Instruction" hint="Derived from role + level">
          <textarea
            value={defaultSystemInstruction || 'Loading...'}
            readOnly
            rows={6}
            className="w-full px-3 py-2 bg-ctp-crust border border-tui-border-dim rounded text-xs text-tui-text focus:outline-none"
          />
        </FormField>

        <FormField label="System Instruction Override" hint="Optional: overrides the default system instruction">
          <textarea
            value={systemInstruction}
            onChange={(e) => setSystemInstruction(e.target.value)}
            rows={6}
            placeholder="Optional override (leave blank to use the default)"
            className="w-full px-3 py-2 bg-ctp-crust border border-tui-border-dim rounded text-xs text-tui-text focus:border-tui-accent focus:outline-none"
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
                  models.map((m) => (
                    <option key={m.id} value={m.id}>
                      {m.id}
                    </option>
                  ))
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

        <FormField label="Agent Name">
          <div className="space-y-2">
            <label className="flex items-center gap-2 text-sm cursor-pointer">
              <input
                type="checkbox"
                checked={autoName}
                onChange={(e) => setAutoName(e.target.checked)}
                className="accent-tui-accent"
              />
              <span>Auto-generate name</span>
            </label>
            
            {!autoName && (
              <div className="space-y-3 pt-2">
                <div>
                  <Input
                    type="text"
                    value={customName}
                    onChange={(e) => handleNameChange(e.target.value)}
                    placeholder="BluePanda"
                    error={!!errors.name}
                  />
                  {errors.name && (
                    <div className="text-xs text-ctp-red mt-1">{errors.name}</div>
                  )}
                </div>
                <div>
                  <Input
                    type="text"
                    value={customSlug}
                    onChange={(e) => {
                      setCustomSlug(e.target.value)
                      setErrors(prev => ({ ...prev, slug: undefined }))
                    }}
                    placeholder="blue-panda"
                    error={!!errors.slug}
                  />
                  {errors.slug && (
                    <div className="text-xs text-ctp-red mt-1">{errors.slug}</div>
                  )}
                </div>
              </div>
            )}
          </div>
        </FormField>

        <div className="flex justify-end gap-3 pt-2">
          <Button type="button" variant="secondary" onClick={handleClose}>
            Cancel
          </Button>
          <Button 
            type="submit" 
            variant="primary"
            disabled={createAgent.isPending}
          >
            {createAgent.isPending ? 'Creating...' : 'Add Agent'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}


