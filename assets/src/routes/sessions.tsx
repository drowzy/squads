import { createFileRoute, Link } from '@tanstack/react-router'
import { useQueries } from '@tanstack/react-query'
import { useState, useMemo } from 'react'
import {
  Terminal,
  Loader2,
  MessageSquare,
  Users,
  Play,
  Pause,
  Clock,
  StopCircle,
} from 'lucide-react'
import {
  useSessions,
  useProjects,
  useStopSession,
  type Session,
  type Squad,
  type Agent,
} from '../api/queries'
import { fetcher } from '../api/client'
import { cn } from '../lib/cn'
import { SessionChatFlyout } from '../components/SessionChatFlyout'
import { useNotifications } from '../components/Notifications'

export const Route = createFileRoute('/sessions')({
  component: SessionsPage,
})

// Status filter options
const STATUS_FILTERS = ['running', 'starting', 'pending', 'paused', 'completed', 'failed', 'cancelled'] as const
type StatusFilter = (typeof STATUS_FILTERS)[number]

function SessionsPage() {
  const [filter, setFilter] = useState<'active' | 'history' | 'all'>('active')
  const { data: sessions = [], isLoading: sessionsLoading } = useSessions(
    filter === 'active' ? { status: 'running,starting,pending,paused' } : 
    filter === 'history' ? { status: 'completed,failed,cancelled' } : 
    undefined
  )
  const { data: projects = [], isLoading: projectsLoading } = useProjects()

  const squadQueries = useQueries({
    queries: projects.map((project) => ({
      queryKey: ['projects', project.id, 'squads'],
      queryFn: () => fetcher<Squad[]>(`/projects/${project.id}/squads`),
      enabled: !!project.id,
    })),
  })

  const allSquads = useMemo(() => {
    return squadQueries.flatMap((query, index) => {
      const project = projects[index]
      if (!project || !query.data) return []
      return query.data.map((squad) => ({
        ...squad,
        projectName: project.name,
        projectId: project.id,
      }))
    })
  }, [projects, squadQueries])

  const squadsLoading = squadQueries.some((query) => query.isLoading)

  // Flyout state
  const [flyoutSession, setFlyoutSession] = useState<Session | null>(null)

  // Build agent lookup: agent_id -> { agent, squad, projectName }
  const agentLookup = useMemo(() => {
    const lookup: Record<
      string,
      { agent: Agent; squad: Squad; projectName: string }
    > = {}
    for (const squad of allSquads) {
      for (const agent of squad.agents || []) {
        lookup[agent.id] = {
          agent,
          squad,
          projectName: squad.projectName,
        }
      }
    }
    return lookup
  }, [allSquads])

  // flyoutSession re-lookup to get fresh data
  const currentFlyoutSession = useMemo(() => {
    if (!flyoutSession) return null
    return sessions.find(s => s.id === flyoutSession.id) || flyoutSession
  }, [sessions, flyoutSession])

  const filteredSessions = sessions // backend already filtered

  // ...

  // Group sessions by squad
  const groupedSessions = useMemo(() => {
    const groups: Record<
      string,
      {
        squadName: string
        squadId: string
        projectName: string
        sessions: (Session & { agent?: Agent })[]
      }
    > = {}

    const unassigned: (Session & { agent?: Agent })[] = []

    for (const session of filteredSessions) {
      const info = agentLookup[session.agent_id]
      if (info) {
        const key = info.squad.id
        if (!groups[key]) {
          groups[key] = {
            squadId: info.squad.id,
            squadName: info.squad.name,
            projectName: info.projectName,
            sessions: [],
          }
        }
        groups[key].sessions.push({ ...session, agent: info.agent })
      } else {
        unassigned.push(session)
      }
    }

    // Sort groups by project name, then squad name
    const sortedGroups = Object.values(groups).sort((a, b) => {
      const projectCompare = a.projectName.localeCompare(b.projectName)
      if (projectCompare !== 0) return projectCompare
      return a.squadName.localeCompare(b.squadName)
    })

    if (unassigned.length > 0) {
      sortedGroups.push({
        squadId: 'unassigned',
        squadName: 'Unassigned',
        projectName: '',
        sessions: unassigned,
      })
    }

    return sortedGroups
  }, [filteredSessions, agentLookup])

  const isLoading = sessionsLoading || projectsLoading || squadsLoading

  return (
    <div className="space-y-6">
      {/* Header */}
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-4 border-b border-tui-border pb-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tighter uppercase flex items-center gap-3">
            <Terminal className="text-tui-accent" size={24} />
            {filter === 'active' ? 'ACTIVE_SESSIONS' : filter === 'history' ? 'SESSION_HISTORY' : 'ALL_SESSIONS'}
          </h1>
          <p className="text-xs text-tui-dim mt-1 uppercase tracking-widest">
            {filter === 'active' ? 'Running, pending, and paused sessions across all projects' : 
             filter === 'history' ? 'Completed, failed, and cancelled sessions' :
             'All recorded sessions across all projects'}
          </p>
        </div>
        <div className="flex flex-col items-end gap-2">
          <div className="flex items-center gap-1 border border-tui-border p-1 bg-tui-bg">
            {(['active', 'history', 'all'] as const).map((f) => (
              <button
                key={f}
                onClick={() => setFilter(f)}
                className={cn(
                  "px-3 py-1 text-[10px] font-bold uppercase tracking-widest transition-colors",
                  filter === f ? "bg-tui-accent text-tui-bg" : "text-tui-dim hover:text-tui-text"
                )}
              >
                {f}
              </button>
            ))}
          </div>
          <div className="text-[10px] text-tui-dim uppercase tracking-widest">
            Total: {filteredSessions.length}
          </div>
        </div>
      </div>

      {/* Loading State */}
      {isLoading && (
        <div className="flex items-center justify-center py-20">
          <Loader2 className="animate-spin text-tui-accent" size={32} />
        </div>
      )}

      {/* Empty State */}
       {!isLoading && filteredSessions.length === 0 && (
         <div className="text-center py-20 border border-tui-border bg-black/20">
           <Terminal className="mx-auto text-tui-dim mb-4" size={48} />
           <h3 className="text-lg font-bold uppercase tracking-widest mb-2">
             {filter === 'active' ? 'NO_ACTIVE_SESSIONS' : filter === 'history' ? 'NO_SESSION_HISTORY' : 'NO_SESSIONS_FOUND'}
           </h3>
           <p className="text-sm text-tui-dim">
             {filter === 'active' ? 'No running, pending, or paused sessions found.' : 
              filter === 'history' ? 'No completed, failed, or cancelled sessions found.' :
              'No sessions found in the system.'}
           </p>
           <div className="mt-6 flex justify-center">
             <Link
               to="/agent"
               className="px-4 py-2 border border-tui-accent text-tui-accent text-xs font-bold uppercase tracking-widest hover:bg-tui-accent hover:text-tui-bg transition-colors"
             >
               Start_New_Session
             </Link>
           </div>
         </div>
       )}


      {/* Sessions grouped by squad */}
      {!isLoading && groupedSessions.length > 0 && (
        <div className="space-y-6">
          {groupedSessions.map((group) => (
            <section
              key={group.squadId}
              className="border border-tui-border bg-black/20"
            >
              {/* Group Header */}
              <div className="p-3 border-b border-tui-border bg-tui-dim/10 flex items-center justify-between">
                <div className="flex items-center gap-3">
                  <Users size={16} className="text-tui-accent" />
                  <div>
                    <span className="font-bold uppercase tracking-widest text-sm">
                      {group.squadName}
                    </span>
                    {group.projectName && (
                      <span className="text-xs text-tui-dim ml-2">
                        ({group.projectName})
                      </span>
                    )}
                  </div>
                </div>
                <span className="text-xs text-tui-dim uppercase tracking-widest">
                  {group.sessions.length} session
                  {group.sessions.length !== 1 ? 's' : ''}
                </span>
              </div>

              {/* Sessions List */}
              <div className="divide-y divide-tui-border/50">
                {group.sessions.map((session) => (
                  <SessionRow
                    key={session.id}
                    session={session}
                    agent={session.agent}
                    onOpenChat={() => setFlyoutSession(session)}
                  />
                ))}
              </div>
            </section>
          ))}
        </div>
      )}

      {/* Chat Flyout */}
      {currentFlyoutSession && (
        <SessionChatFlyout
          session={currentFlyoutSession}
          agent={agentLookup[currentFlyoutSession.agent_id]?.agent}
          onClose={() => setFlyoutSession(null)}
        />
      )}
    </div>
  )
}

interface SessionRowProps {
  session: Session
  agent?: Agent
  onOpenChat: () => void
}

function SessionRow({ session, agent, onOpenChat }: SessionRowProps) {
  const stopSession = useStopSession()
  const { addNotification } = useNotifications()

  const statusConfig = {
    running: {
      icon: Play,
      color: 'text-green-400 border-green-500/30',
      bg: 'bg-green-500/10',
    },
    starting: {
      icon: Clock,
      color: 'text-yellow-400 border-yellow-500/30',
      bg: 'bg-yellow-500/10',
    },
    pending: {
      icon: Clock,
      color: 'text-yellow-400 border-yellow-500/30',
      bg: 'bg-yellow-500/10',
    },
    paused: {
      icon: Pause,
      color: 'text-blue-400 border-blue-500/30',
      bg: 'bg-blue-500/10',
    },
    completed: {
      icon: Clock,
      color: 'text-ctp-green border-ctp-green/30',
      bg: 'bg-ctp-green/5',
    },
    failed: {
      icon: StopCircle,
      color: 'text-ctp-red border-ctp-red/30',
      bg: 'bg-ctp-red/5',
    },
    cancelled: {
      icon: StopCircle,
      color: 'text-tui-dim border-tui-dim/30',
      bg: 'bg-tui-dim/5',
    },
  }

  const config = statusConfig[session.status as keyof typeof statusConfig] || {
    icon: Terminal,
    color: 'text-tui-dim border-tui-border',
    bg: 'bg-tui-dim/10',
  }

  const StatusIcon = config.icon

  const handleStopSession = async (e: React.MouseEvent) => {
    e.preventDefault()
    e.stopPropagation()
    
    if (!confirm('Are you sure you want to terminate this session? The agent will stop working immediately.')) return

    try {
      await stopSession.mutateAsync({ session_id: session.id })
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

  return (
    <div className="p-3 hover:bg-tui-dim/5 transition-colors flex items-center gap-4">
      {/* Status Badge */}
      <div
        className={cn(
          'flex items-center gap-1.5 px-2 py-1 border text-[10px] font-bold uppercase tracking-widest shrink-0',
          config.color,
          config.bg
        )}
      >
        <StatusIcon size={12} />
        <span>{session.status}</span>
      </div>

      {/* Agent Info */}
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          {agent ? (
            <Link
              to="/agent/$agentId"
              params={{ agentId: agent.id }}
              className="font-bold text-sm text-tui-accent hover:underline truncate"
            >
              {agent.name}
            </Link>
          ) : (
            <span className="font-bold text-sm text-tui-dim truncate">
              Unknown Agent
            </span>
          )}
          {agent?.role && (
            <span className="text-[10px] text-tui-dim uppercase tracking-widest hidden sm:inline">
              {agent.role}
            </span>
          )}
        </div>
        <div className="text-xs text-tui-dim font-mono truncate mt-0.5">
          session/{session.id.slice(0, 8)}
          {session.model && (
            <span className="ml-2 hidden md:inline">• {session.model}</span>
          )}
        </div>
      </div>

      {/* Session Details: Ticket & Worktree */}
      <div className="flex-1 hidden md:flex flex-col text-xs text-tui-dim min-w-0 px-4">
        {session.ticket_key && (
          <div className="flex items-center gap-1.5 truncate text-tui-text/80">
            <span className="text-tui-dim uppercase tracking-wider text-[10px]">Ticket:</span>
            <span className="font-mono">{session.ticket_key}</span>
          </div>
        )}
        {(session.branch || session.worktree_path) && (
          <div className="flex items-center gap-1.5 truncate mt-0.5">
            <span className="text-tui-dim uppercase tracking-wider text-[10px]">Context:</span>
            <span className="font-mono truncate" title={session.worktree_path || session.branch}>
               {session.branch || session.worktree_path?.split('/').pop()}
            </span>
          </div>
        )}
      </div>

      {/* Timestamp */}
      <div className="text-xs text-tui-dim hidden lg:block shrink-0">
        {session.started_at 
          ? `Started ${new Date(session.started_at).toLocaleString()}` 
          : `Created ${new Date(session.inserted_at).toLocaleString()}`
        }
      </div>

      <div className="flex items-center gap-2 shrink-0">
        {session.status === 'running' && (
          <button
            onClick={handleStopSession}
            disabled={stopSession.isPending}
            className="p-2 border border-tui-border hover:border-ctp-red hover:text-ctp-red transition-colors shrink-0 rounded"
            title="Terminate Session"
          >
            <StopCircle size={16} />
          </button>
        )}
        {/* Chat Button */}
        <button
          onClick={onOpenChat}
          className="p-2 border border-tui-border hover:border-tui-accent hover:text-tui-accent transition-colors shrink-0 rounded"
          title="Open chat"
        >
          <MessageSquare size={16} />
        </button>
      </div>
    </div>
  )
}
