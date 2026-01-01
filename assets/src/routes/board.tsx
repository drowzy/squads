import { createFileRoute } from '@tanstack/react-router'
import { ClipboardList, Clock, AlertCircle, CheckCircle2, Loader2, Layout, Network, Search, Filter, X } from 'lucide-react'
import { useTickets, Ticket, useCreateTicket } from '../api/queries'
import { useState, useMemo } from 'react'
import { TicketFlow } from '../components/board/TicketFlow'
import { ReactFlowProvider } from '@xyflow/react'
import { useActiveProject } from './__root'
import { CreateTicketModal } from '../components/board/CreateTicketModal'

export const Route = createFileRoute('/board')({
  component: TicketBoardWrapper,
})

function TicketBoardWrapper() {
  return (
    <ReactFlowProvider>
      <TicketBoard />
    </ReactFlowProvider>
  )
}

function TicketBoard() {
  const { activeProject } = useActiveProject()
  const { data: tickets = [], isLoading, error } = useTickets(activeProject?.id)
  const [viewMode, setViewMode] = useState<'kanban' | 'flow'>('kanban')
  const [searchQuery, setSearchQuery] = useState('')
  const [assigneeFilter, setAssigneeFilter] = useState<string | null>(null)
  const [isCreateModalOpen, setIsCreateModalOpen] = useState(false)

  const assignees = useMemo(() => {
    const set = new Set<string>()
    tickets.forEach(t => t.assignee && set.add(t.assignee))
    return Array.from(set).sort()
  }, [tickets])

  const filteredTickets = useMemo(() => {
    return tickets.filter(t => {
      const matchesSearch = t.title.toLowerCase().includes(searchQuery.toLowerCase()) || 
                           t.id.toLowerCase().includes(searchQuery.toLowerCase())
      const matchesAssignee = !assigneeFilter || t.assignee === assigneeFilter
      return matchesSearch && matchesAssignee
    })
  }, [tickets, searchQuery, assigneeFilter])

  const columns: { label: string; status: Ticket['status']; icon: React.ReactNode; color: string }[] = [
    { label: 'READY', status: 'open', icon: <ClipboardList size={16} />, color: 'text-ctp-blue' },
    { label: 'ACTIVE', status: 'in_progress', icon: <Clock size={16} />, color: 'text-ctp-peach' },
    { label: 'BLOCKED', status: 'blocked', icon: <AlertCircle size={16} />, color: 'text-ctp-red' },
    { label: 'DONE', status: 'closed', icon: <CheckCircle2 size={16} />, color: 'text-ctp-green' },
  ]

  if (isLoading) {
    return (
      <div className="h-full flex items-center justify-center">
        <Loader2 className="animate-spin text-tui-accent" size={32} />
      </div>
    )
  }

  if (error) {
    return (
      <div className="h-full flex flex-col items-center justify-center text-tui-accent">
        <AlertCircle size={48} className="mb-4" />
        <h3 className="text-xl font-bold">
          {error.message === 'BEADS_NOT_INITIALIZED' ? 'BEADS_PROJECT_NOT_FOUND' : 'FAILED_TO_LOAD_BOARD'}
        </h3>
        <p className="text-sm opacity-70">
          {error.message === 'BEADS_NOT_INITIALIZED' 
            ? 'No .beads directory found in this project. Please run "bd init" in the CLI.'
            : (error instanceof Error ? error.message : 'Check backend connection')}
        </p>
        <p className="text-xs text-tui-dim mt-2 max-w-md text-center">
           {error.message === 'BEADS_NOT_INITIALIZED' 
             ? 'This view requires the Beads issue tracker to be initialized.'
             : 'Possible causes: Backend offline, proxy error, or missing Beads init (.beads folder) in project.'}
        </p>
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col space-y-4 md:space-y-6">
      <div className="flex flex-col gap-4">
        <div>
          <h2 className="text-xl md:text-2xl font-bold tracking-tighter uppercase">Mission_Control / Board</h2>
          <p className="text-tui-dim text-xs md:text-sm italic">Status of all active and pending tickets</p>
        </div>
        
        <div className="flex flex-wrap gap-2 md:gap-4 items-center">
          {/* Filters */}
          <div className="flex items-center gap-2 bg-tui-bg border border-tui-border px-3 py-2 flex-1 min-w-0 md:flex-none">
            <Search size={14} className="text-tui-dim shrink-0" />
            <input 
              type="text" 
              placeholder="SEARCH..."
              value={searchQuery}
              onChange={e => setSearchQuery(e.target.value)}
              className="bg-transparent border-none outline-none text-xs uppercase font-mono w-full md:w-40 placeholder:text-tui-dim/30"
            />
            {searchQuery && (
              <button onClick={() => setSearchQuery('')} className="text-tui-dim hover:text-tui-accent shrink-0">
                <X size={14} />
              </button>
            )}
          </div>

          <div className="flex items-center gap-2 bg-tui-bg border border-tui-border px-3 py-2 flex-1 min-w-0 md:flex-none">
            <Filter size={14} className="text-tui-dim shrink-0" />
            <select 
              value={assigneeFilter || ''}
              onChange={e => setAssigneeFilter(e.target.value || null)}
              className="bg-transparent border-none outline-none text-xs uppercase font-mono w-full md:w-32 cursor-pointer"
            >
              <option value="">ALL_ASSIGNEES</option>
              {assignees.map(a => (
                <option key={a} value={a}>{a.toUpperCase()}</option>
              ))}
            </select>
          </div>

          <div className="flex border border-tui-border shrink-0">
            <button 
              onClick={() => setIsCreateModalOpen(true)}
              className="px-3 md:px-4 py-2 bg-tui-accent text-tui-bg text-xs font-bold uppercase hover:bg-white transition-colors"
            >
              New_Ticket
            </button>
            <div className="w-[1px] bg-tui-border"></div>
            <button 
              onClick={() => setViewMode('kanban')}
              className={`p-2.5 md:p-2 transition-colors ${viewMode === 'kanban' ? 'bg-tui-accent text-tui-bg' : 'text-tui-dim hover:text-tui-text'}`}
            >
              <Layout size={18} />
            </button>
            <button 
              onClick={() => setViewMode('flow')}
              className={`p-2.5 md:p-2 transition-colors ${viewMode === 'flow' ? 'bg-tui-accent text-tui-bg' : 'text-tui-dim hover:text-tui-text'}`}
            >
              <Network size={18} />
            </button>
          </div>
        </div>
      </div>

      <div className="flex-1 min-h-0">
        {viewMode === 'kanban' ? (
          <div className="h-full flex flex-col md:flex-row gap-4 md:gap-6 overflow-y-auto md:overflow-y-hidden md:overflow-x-auto pb-4 custom-scrollbar">
            {columns.map((col) => (
              <div key={col.status} className="md:w-80 flex flex-col border border-tui-border bg-tui-bg/50 md:shrink-0">
                <div className={`p-3 border-b border-tui-border flex items-center justify-between bg-ctp-mantle ${col.color}`}>
                  <div className="flex items-center gap-2">
                    {col.icon}
                    <span className="font-bold tracking-widest text-xs uppercase">{col.label}</span>
                  </div>
                  <span className="text-xs bg-ctp-surface0 px-1.5 py-0.5 rounded font-mono text-ctp-text">
                    {filteredTickets.filter(t => t.status === col.status).length}
                  </span>
                </div>
                
                <div className="flex-1 md:overflow-y-auto p-3 space-y-3 custom-scrollbar">
                  {filteredTickets
                    .filter((t) => t.status === col.status)
                    .map((ticket) => (
                      <TicketCard key={ticket.id} ticket={ticket} />
                    ))}
                  {filteredTickets.filter(t => t.status === col.status).length === 0 && (
                    <div className="h-16 md:h-20 flex items-center justify-center border border-dashed border-tui-border/30 opacity-20">
                      <span className="text-xs uppercase italic tracking-widest">No_Matches</span>
                    </div>
                  )}
                </div>
              </div>
            ))}
          </div>
        ) : (
          <TicketFlow tickets={filteredTickets} />
        )}
      </div>

      {activeProject && (
        <CreateTicketModal
          isOpen={isCreateModalOpen}
          onClose={() => setIsCreateModalOpen(false)}
          projectId={activeProject.id}
        />
      )}
    </div>
  )
}

function TicketCard({ ticket }: { ticket: Ticket }) {
  return (
    <div className="border border-tui-border p-3 bg-tui-bg hover:border-tui-accent transition-colors group cursor-pointer">
      <div className="flex justify-between items-start gap-2 mb-2">
        <span className="text-xs font-bold text-tui-dim group-hover:text-tui-accent">
          {ticket.id}
        </span>
        <div className="flex gap-1">
          {Array.from({ length: 3 - (ticket.priority > 3 ? 3 : ticket.priority) + 1 }).map((_, i) => (
            <div key={i} className="w-1 h-3 bg-tui-accent/40" />
          ))}
        </div>
      </div>
      
      <h4 className="text-sm font-bold leading-tight mb-3 line-clamp-2">
        {ticket.title}
      </h4>

      {ticket.assignee && (
        <div className="flex items-center gap-2 mt-auto">
          <div className="w-5 h-5 md:w-4 md:h-4 border border-tui-border flex items-center justify-center bg-tui-dim/20">
            <span className="text-[10px] font-bold">{ticket.assignee[0].toUpperCase()}</span>
          </div>
          <span className="text-xs text-tui-dim">{ticket.assignee}</span>
        </div>
      )}
    </div>
  )
}
