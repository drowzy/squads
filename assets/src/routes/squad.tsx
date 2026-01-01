import { createFileRoute, Link } from '@tanstack/react-router'
import { Users, Shield, Cpu, Activity, ChevronRight, ChevronDown, Plus, MoreVertical, Pencil, Trash2, UserPlus } from 'lucide-react'
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
  type Squad,
  type Agent,
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
  const [createModalOpen, setCreateModalOpen] = useState(false)

  const isLoading = projectsLoading || (projectId && squadsLoading)

  return (
    <div className="space-y-4 md:space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
        <div>
          <h2 className="text-xl md:text-2xl font-bold tracking-tighter uppercase">Squad_Command</h2>
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
        <div className="p-12 border border-tui-border border-dashed text-center space-y-4 bg-tui-dim/5">
          <div className="text-tui-dim animate-pulse uppercase tracking-widest text-xs">
            Scanning_Neural_Networks...
          </div>
        </div>
      ) : !projectId ? (
        <div className="p-12 border border-tui-border border-dashed text-center space-y-4 bg-tui-dim/5">
          <div className="text-tui-dim uppercase tracking-widest text-xs">
            Select_A_Project_First
          </div>
        </div>
      ) : squads && squads.length > 0 ? (
        <div className="space-y-4">
          {squads.map((squad) => (
            <SquadCard key={squad.id} squad={squad} projectId={projectId} />
          ))}
        </div>
      ) : (
        <div className="p-16 border border-tui-border border-dashed text-center space-y-6 bg-tui-dim/5">
          <div className="flex justify-center">
            <div className="w-16 h-16 border border-tui-border flex items-center justify-center bg-tui-bg text-tui-dim">
              <Users size={32} />
            </div>
          </div>
          <div className="space-y-2">
            <h3 className="text-lg font-bold uppercase tracking-widest">No_Squads_Deployed</h3>
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

function SquadCard({ squad, projectId }: { squad: Squad; projectId: string }) {
  const [expanded, setExpanded] = useState(true)
  const [menuOpen, setMenuOpen] = useState(false)
  const [createAgentModalOpen, setCreateAgentModalOpen] = useState(false)
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
    <div className="border border-tui-border bg-tui-dim/5">
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
        
        <div className="w-10 h-10 border border-tui-border flex items-center justify-center bg-tui-bg shrink-0">
          <Users className="text-tui-accent" size={18} />
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-3">
            <h3 className="font-bold text-lg uppercase truncate">{squad.name}</h3>
            <span className="text-xs px-2 py-0.5 border border-tui-border text-tui-dim">
              {agents.length} agent{agents.length !== 1 ? 's' : ''}
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
                  className="absolute right-0 mt-1 z-20 bg-tui-bg border border-tui-border rounded shadow-lg min-w-[140px]"
                >
                  <button
                    role="menuitem"
                    onClick={(e) => {
                      e.stopPropagation()
                      setMenuOpen(false)
                      // TODO: Open edit modal
                    }}
                    className="w-full flex items-center gap-2 px-3 py-2 text-sm text-left hover:bg-tui-dim/20 focus:outline-none focus:bg-tui-dim/20"
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
      </div>

      {/* Agents List */}
      {expanded && (
        <div className="border-t border-tui-border">
          {agents.length > 0 ? (
            agents.map((agent) => (
              <AgentRow key={agent.id} agent={agent} squadId={squad.id} />
            ))
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
        </div>
      )}

      <CreateAgentModal
        isOpen={createAgentModalOpen}
        onClose={() => setCreateAgentModalOpen(false)}
        projectId={projectId}
        squadId={squad.id}
        squadName={squad.name}
      />
    </div>
  )
}

function AgentRow({ agent, squadId }: { agent: Agent; squadId: string }) {
  const [menuOpen, setMenuOpen] = useState(false)
  const deleteAgent = useDeleteAgent()
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
    <div className="flex items-center gap-3 px-4 py-3 pl-14 hover:bg-tui-dim/10 transition-colors group border-b border-tui-border/50 last:border-b-0">
      <Link
        to="/agent/$agentId"
        params={{ agentId: agent.id }}
        className="flex items-center gap-3 flex-1 min-w-0"
      >
        <div className="w-8 h-8 border border-tui-border flex items-center justify-center bg-tui-bg shrink-0 group-hover:border-tui-accent">
          <Cpu className="text-tui-text" size={14} />
        </div>

        <div className="flex-1 min-w-0">
          <div className="flex items-center gap-2">
            <span className="font-bold uppercase truncate">{agent.name}</span>
            <span className="text-xs text-tui-dim">({agent.slug})</span>
          </div>
          {agent.model && (
            <div className="text-xs text-tui-dim truncate">{agent.model}</div>
          )}
        </div>

        <div className="flex items-center gap-3 shrink-0">
          <div className={cn("text-xs font-bold tracking-widest", statusColors[agent.status])}>
            {statusLabels[agent.status]}
          </div>
          <ChevronRight size={14} className="text-tui-dim group-hover:text-tui-accent" />
        </div>
      </Link>

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
              className="absolute right-0 mt-1 z-20 bg-tui-bg border border-tui-border rounded shadow-lg min-w-[120px]"
            >
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


