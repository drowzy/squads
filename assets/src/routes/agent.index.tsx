import { createFileRoute, Link } from '@tanstack/react-router'
import { Cpu, UserCircle, ChevronRight, Search, LayoutGrid, List } from 'lucide-react'
import { useState, useMemo } from 'react'
import { useAgents, type Agent } from '../api/queries'
import { useActiveProject } from './__root'
import { cn } from '../lib/cn'
import { ListToolbar } from '../components/ui/ListToolbar'

export const Route = createFileRoute('/agent/')({
  component: AgentOverview,
})

export function AgentOverview() {
  const { activeProject, isLoading: projectsLoading } = useActiveProject()
  const projectId = activeProject?.id ?? ''
  const { data: agents, isLoading: agentsLoading } = useAgents(projectId)
  const [search, setSearch] = useState('')
  const [viewMode, setViewMode] = useState<'grid' | 'list'>('grid')

  const filteredAgents = useMemo(() => {
    if (!agents) return []
    return agents.filter(a => 
      a.name.toLowerCase().includes(search.toLowerCase()) || 
      a.role.toLowerCase().includes(search.toLowerCase()) ||
      a.slug.toLowerCase().includes(search.toLowerCase())
    )
  }, [agents, search])

  const isLoading = projectsLoading || (projectId && agentsLoading)

  return (
    <div className="space-y-4 md:space-y-6">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-center gap-3">
        <div>
          <h2 className="text-xl md:text-2xl font-bold tracking-tighter uppercase flex items-center gap-2">
            <UserCircle className="text-tui-accent" />
            Agent Registry
          </h2>
          <p className="text-tui-dim text-xs md:text-sm italic">Inventory of all active nodes in the project</p>
        </div>
        
        {activeProject && (
          <div className="text-xs text-tui-dim font-bold tracking-widest border border-tui-border px-2 py-1">
            PROJECT: {activeProject.name.toUpperCase()}
          </div>
        )}
      </div>

      <ListToolbar
        searchQuery={search}
        onSearchChange={setSearch}
        searchPlaceholder="Search agents by name, role, or slug..."
      >
        <div className="flex items-center gap-1 border border-tui-border p-1 bg-ctp-crust/40">
          <button 
            onClick={() => setViewMode('grid')}
            className={cn("p-1.5 transition-colors", viewMode === 'grid' ? "bg-tui-accent text-tui-bg" : "text-tui-dim hover:text-tui-text")}
            title="Grid View"
          >
            <LayoutGrid size={16} />
          </button>
          <button 
            onClick={() => setViewMode('list')}
            className={cn("p-1.5 transition-colors", viewMode === 'list' ? "bg-tui-accent text-tui-bg" : "text-tui-dim hover:text-tui-text")}
            title="List View"
          >
            <List size={16} />
          </button>
        </div>
      </ListToolbar>

      {isLoading ? (
        <div className="p-8 border border-tui-border border-dashed text-center text-tui-dim animate-pulse uppercase tracking-widest text-xs">
          Loading Agent Registry...
        </div>
      ) : !projectId ? (
        <div className="p-8 border border-tui-border border-dashed text-center text-tui-dim uppercase tracking-widest text-xs">
          Select a project first
        </div>
      ) : filteredAgents.length > 0 ? (
        viewMode === 'grid' ? (
          <div className="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 xl:grid-cols-4 gap-4">
            {filteredAgents.map(agent => (
              <AgentCard key={agent.id} agent={agent} />
            ))}
          </div>
        ) : (
          <div className="border border-tui-border divide-y divide-tui-border bg-ctp-mantle/50">
            {filteredAgents.map(agent => (
              <AgentRow key={agent.id} agent={agent} />
            ))}
          </div>
        )
      ) : (
        <div className="p-12 border border-tui-border border-dashed text-center space-y-3">
          <div className="text-tui-dim uppercase tracking-widest text-xs">
            No agents match your search
          </div>
          <button
            onClick={() => setSearch('')}
            className="text-tui-accent text-sm hover:underline"
          >
            Clear search filters
          </button>
        </div>
      )}
    </div>
  )
}

function AgentCard({ agent }: { agent: Agent }) {
  const statusColors = {
    idle: 'text-tui-dim',
    working: 'text-tui-accent',
    blocked: 'text-ctp-peach',
    offline: 'text-tui-border',
  }

  return (
    <Link 
      to="/agent/$agentId" 
      params={{ agentId: agent.id }}
      className="border border-tui-border bg-ctp-mantle/50 p-4 hover:border-tui-accent transition-colors group flex flex-col gap-3"
    >
      <div className="flex justify-between items-start">
        <div className="w-10 h-10 border border-tui-border-dim flex items-center justify-center bg-ctp-crust/40 group-hover:border-tui-accent transition-colors">
          <Cpu className="text-tui-accent" size={20} />
        </div>
        <div className={cn("text-[10px] font-bold tracking-widest uppercase px-1.5 py-0.5 border border-current", statusColors[agent.status])}>
          {agent.status}
        </div>
      </div>
      
      <div>
        <h3 className="font-bold text-lg uppercase truncate group-hover:text-tui-accent transition-colors">{agent.name}</h3>
        <p className="text-xs text-tui-dim font-mono">{agent.slug}</p>
      </div>

      <div className="pt-2 border-t border-tui-border-dim">
        <div className="text-[10px] text-tui-dim uppercase tracking-widest mb-1">Role</div>
        <div className="text-xs font-bold truncate">{agent.role.replace(/_/g, ' ').toUpperCase()}</div>
      </div>

      <div className="flex items-center justify-between mt-auto pt-2">
        <div className="text-[10px] text-tui-dim font-mono">{agent.model || 'gpt-4o'}</div>
        <ChevronRight size={14} className="text-tui-dim group-hover:text-tui-accent translate-x-0 group-hover:translate-x-1 transition-all" />
      </div>
    </Link>
  )
}

function AgentRow({ agent }: { agent: Agent }) {
  const statusColors = {
    idle: 'text-tui-dim',
    working: 'text-tui-accent',
    blocked: 'text-ctp-peach',
    offline: 'text-tui-border',
  }

  return (
    <Link 
      to="/agent/$agentId" 
      params={{ agentId: agent.id }}
      className="flex items-center gap-4 p-3 hover:bg-tui-dim/5 transition-colors group"
    >
      <div className="w-8 h-8 border border-tui-border-dim flex items-center justify-center bg-ctp-crust/40 shrink-0 group-hover:border-tui-accent transition-colors">
        <Cpu className="text-tui-accent" size={16} />
      </div>
      
      <div className="flex-1 min-w-0">
        <div className="flex items-center gap-2">
          <span className="font-bold uppercase truncate group-hover:text-tui-accent transition-colors">{agent.name}</span>
          <span className="text-[10px] text-tui-dim font-mono">({agent.slug})</span>
        </div>
        <div className="text-[10px] text-tui-dim uppercase tracking-widest">{agent.role.replace(/_/g, ' ')}</div>
      </div>

      <div className="hidden md:block text-xs font-mono text-tui-dim px-4">
        {agent.model || 'gpt-4o'}
      </div>

      <div className={cn("text-[10px] font-bold tracking-widest uppercase px-2 py-0.5 border border-current shrink-0", statusColors[agent.status])}>
        {agent.status}
      </div>

      <ChevronRight size={16} className="text-tui-dim group-hover:text-tui-accent transition-colors" />
    </Link>
  )
}
