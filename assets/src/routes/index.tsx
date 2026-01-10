import { createFileRoute } from '@tanstack/react-router'
import { useNavigate } from '@tanstack/react-router'
import type { ReactNode } from 'react'
import { Play, ClipboardList, Mail } from 'lucide-react'
import { useSessions, useEvents } from '../api/queries'
import { useActiveProject } from './__root'
import { cn } from '../lib/cn'
import { EventTimeline } from '../components/events/EventTimeline'

export const Route = createFileRoute('/')({
  component: Dashboard,
})

function Dashboard() {
  const { activeProject, projects, isLoading: projectsLoading } = useActiveProject()
  const navigate = useNavigate()
  const { data: sessions, isLoading: sessionsLoading } = useSessions()
  const { data: events = [], isLoading: eventsLoading } = useEvents({ 
    project_id: activeProject?.id,
    limit: 10 
  })

  const activeSessions = sessions?.filter(s => s.status === 'running').length ?? 0
  const totalProjects = projects?.length ?? 0
  const actionsDisabled = !activeProject
  const actions = [
    {
      label: 'Start Session',
      description: activeProject
        ? `Spin up a new session in ${activeProject.name}`
        : 'Select a project to start a session',
      icon: <Play size={18} className="text-tui-accent" />,
      onClick: () => navigate({ to: '/sessions' }),
    },
    {
      label: 'New Card',
      description: activeProject
        ? `Add a build request for ${activeProject.name}`
        : 'Select a project to add a card',
      icon: <ClipboardList size={18} className="text-ctp-blue" />,
      onClick: () => navigate({ to: '/board' }),
    },
    {
      label: 'Compose Message',
      description: activeProject
        ? 'Send a message to your squad'
        : 'Select a project to message agents',
      icon: <Mail size={18} className="text-ctp-mauve" />,
      onClick: () => navigate({ to: '/mail' }),
    },
  ]

  return (
    <div className="space-y-4 md:space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-end gap-2">
        <div>
          <h2 className="text-xl md:text-2xl font-bold tracking-tighter">Mission Control / Dashboard</h2>
          <p className="text-tui-dim text-xs md:text-sm italic">System status and overview</p>
        </div>
        <div className="text-left sm:text-right text-[10px] text-tui-dim font-bold">
          Last sync: {new Date().toLocaleTimeString()}
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-3 gap-3">
        {actions.map((action) => (
          <ActionCard
            key={action.label}
            label={action.label}
            description={action.description}
            icon={action.icon}
            onClick={action.onClick}
            disabled={actionsDisabled}
          />
        ))}
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
        <StatCard 
          label="Active Sessions" 
          value={sessionsLoading ? '...' : activeSessions.toString()} 
          color="text-tui-text" 
        />
        <StatCard 
          label="Managed Projects" 
          value={projectsLoading ? '...' : totalProjects.toString()} 
          color="text-tui-accent" 
        />
        <StatCard label="System Load" value="1.24" color="text-tui-dim" />
      </div>

      <div className="border border-tui-border p-4 bg-ctp-mantle/50">
        <div className="flex items-center gap-2 mb-4">
          <span className="w-2 h-2 bg-tui-accent" />
          <h3 className="font-bold text-[10px] text-tui-dim">Recent activity</h3>
        </div>
        <EventTimeline events={events} isLoading={eventsLoading} />
      </div>
    </div>
  )
}

function ActionCard({
  label,
  description,
  icon,
  onClick,
  disabled,
}: {
  label: string
  description: string
  icon: ReactNode
  onClick: () => void
  disabled: boolean
}) {
  return (
    <button
      type="button"
      onClick={onClick}
      disabled={disabled}
      className={cn(
        "border border-tui-border p-4 bg-ctp-mantle/50 flex items-start justify-between gap-4 text-left transition-colors",
        disabled
          ? "opacity-50 cursor-not-allowed"
          : "hover:border-tui-accent hover:bg-tui-dim/10"
      )}
    >
      <div className="flex items-start gap-3">
        <div className="mt-0.5">{icon}</div>
        <div>
          <div className="text-[10px] font-bold text-tui-dim">
            {label}
          </div>
          <div className="text-[11px] text-tui-dim mt-1">{description}</div>
        </div>
      </div>
      <span className="text-[10px] font-bold text-tui-dim">
        {disabled ? 'Wait' : 'Open'}
      </span>
    </button>
  )
}

function StatCard({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <div className="border border-tui-border p-4 bg-ctp-mantle/50">
      <div className="text-[10px] text-tui-dim mb-1 font-bold">{label}</div>
      <div className={cn("text-2xl md:text-3xl font-bold tracking-tighter", color)}>{value}</div>
    </div>
  )
}
