import { createFileRoute } from '@tanstack/react-router'
import { useSessions } from '../api/queries'
import { useActiveProject } from './__root'
import { cn } from '../lib/cn'

export const Route = createFileRoute('/')({
  component: Dashboard,
})

function Dashboard() {
  const { data: sessions, isLoading: sessionsLoading } = useSessions()
  const { projects, isLoading: projectsLoading } = useActiveProject()

  const activeSessions = sessions?.filter(s => s.status === 'running').length ?? 0
  const totalProjects = projects?.length ?? 0

  return (
    <div className="space-y-4 md:space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-end gap-2">
        <div>
          <h2 className="text-xl md:text-2xl font-bold tracking-tighter uppercase">Mission_Control / Dashboard</h2>
          <p className="text-tui-dim text-xs md:text-sm italic">System status and overview</p>
        </div>
        <div className="text-left sm:text-right text-xs text-tui-dim font-mono">
          LAST_SYNC: {new Date().toLocaleTimeString()}
        </div>
      </div>

      <div className="grid grid-cols-1 sm:grid-cols-2 md:grid-cols-3 gap-4">
        <StatCard 
          label="ACTIVE_SESSIONS" 
          value={sessionsLoading ? '...' : activeSessions.toString()} 
          color="text-tui-text" 
        />
        <StatCard 
          label="MANAGED_PROJECTS" 
          value={projectsLoading ? '...' : totalProjects.toString()} 
          color="text-tui-accent" 
        />
        <StatCard label="SYSTEM_LOAD" value="1.24" color="text-tui-dim" />
      </div>

      <div className="border border-tui-border p-4 bg-tui-dim/5">
        <div className="flex items-center gap-2 mb-4">
          <span className="w-2 h-2 bg-tui-accent" />
          <h3 className="font-bold uppercase tracking-widest text-xs">Recent_Activity</h3>
        </div>
        <div className="space-y-2 font-mono text-sm">
          <ActivityItem timestamp="14:04:22" message="Integration service initialized" />
          <ActivityItem timestamp="14:02:10" message="System bind to 0.0.0.0 successful" />
          <ActivityItem timestamp="13:58:45" message="Vite HMR client connected" />
        </div>
      </div>
    </div>
  )
}

function StatCard({ label, value, color }: { label: string; value: string; color: string }) {
  return (
    <div className="border border-tui-border p-4 bg-tui-bg">
      <div className="text-xs text-tui-dim mb-1 font-bold tracking-widest">{label}</div>
      <div className={cn("text-2xl md:text-3xl font-bold tracking-tighter", color)}>{value}</div>
    </div>
  )
}

function ActivityItem({ timestamp, message }: { timestamp: string; message: string }) {
  return (
    <div className="flex flex-col sm:flex-row gap-1 sm:gap-4">
      <span className="text-tui-dim text-xs sm:text-sm">[{timestamp}]</span>
      <span className="text-tui-text text-sm">{message}</span>
    </div>
  )
}

