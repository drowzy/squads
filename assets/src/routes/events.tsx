import { createFileRoute } from '@tanstack/react-router'
import { useActiveProject } from './__root'
import { useEvents } from '../api/queries'
import { EventTimeline } from '../components/events/EventTimeline'
import { Terminal, Filter, RefreshCcw, Search } from 'lucide-react'
import { useState, useMemo } from 'react'
import { cn } from '../lib/cn'

export const Route = createFileRoute('/events')({
  component: EventsPage,
})

const normalizeEventKind = (kind: string) => kind.replace(/^(\w+)\./, '$1:')

function EventsPage() {
  const { activeProject } = useActiveProject()
  const [limit, setLimit] = useState(50)
  const [filterText, setFilterText] = useState('')
  const [kindFilter, setKindFilter] = useState<string>('all')

  const { data: events, isLoading, refetch, isRefetching } = useEvents({
    project_id: activeProject?.id,
    limit: limit
  })

  const filteredEvents = useMemo(() => {
    if (!events) return []
    return events.filter((event) => {
      const normalizedKind = normalizeEventKind(event.kind)
      const matchesKind = kindFilter === 'all' || normalizedKind.startsWith(kindFilter)
      const matchesSearch = !filterText || 
        normalizedKind.toLowerCase().includes(filterText.toLowerCase()) ||
        JSON.stringify(event.payload).toLowerCase().includes(filterText.toLowerCase())
      return matchesKind && matchesSearch
    })
  }, [events, kindFilter, filterText])

  const eventKinds = [
    { id: 'all', label: 'ALL_EVENTS' },
    { id: 'session:', label: 'SESSIONS' },
    { id: 'message:', label: 'MESSAGES' },
    { id: 'ticket:', label: 'TICKETS' },
    { id: 'mail:', label: 'MAIL' },
    { id: 'agent:', label: 'AGENTS' },
  ]

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
            <Terminal className="text-tui-accent" />
            EVENT_LOG
          </h1>
          <p className="text-tui-dim text-sm mt-1 uppercase tracking-widest">
            Audit trail for {activeProject?.name || 'active project'}
          </p>
        </div>
        <div className="flex items-center gap-2">
           <button
            onClick={() => refetch()}
            disabled={isLoading || isRefetching}
            className="p-2 border border-tui-border hover:bg-tui-dim/10 text-tui-dim hover:text-tui-text transition-colors disabled:opacity-50"
            title="Refresh events"
          >
            <RefreshCcw size={18} className={cn(isRefetching && "animate-spin")} />
          </button>
          <select 
            value={limit}
            onChange={(e) => setLimit(Number(e.target.value))}
            className="bg-black/40 border border-tui-border text-xs font-bold py-2 px-3 focus:outline-none focus:ring-1 focus:ring-tui-accent"
          >
            <option value={20}>LIMIT: 20</option>
            <option value={50}>LIMIT: 50</option>
            <option value={100}>LIMIT: 100</option>
            <option value={500}>LIMIT: 500</option>
          </select>
        </div>
      </div>

      <div className="grid grid-cols-1 md:grid-cols-4 gap-6">
        <aside className="space-y-6">
          <div className="space-y-2">
            <label className="text-[10px] font-bold uppercase tracking-[0.2em] text-tui-dim">
              Filter_By_Kind
            </label>
            <div className="flex flex-col gap-1">
              {eventKinds.map((kind) => (
                <button
                  key={kind.id}
                  onClick={() => setKindFilter(kind.id)}
                  className={cn(
                    "flex items-center justify-between px-3 py-2 text-xs font-bold transition-all border",
                    kindFilter === kind.id 
                      ? "bg-tui-accent/10 border-tui-accent text-tui-accent" 
                      : "border-tui-border text-tui-dim hover:bg-tui-dim/5 hover:text-tui-text"
                  )}
                >
                  <span>{kind.label}</span>
                  {kindFilter === kind.id && <Filter size={12} />}
                </button>
              ))}
            </div>
          </div>

          <div className="space-y-2">
            <label className="text-[10px] font-bold uppercase tracking-[0.2em] text-tui-dim">
              Search_Payload
            </label>
            <div className="relative">
              <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-tui-dim" size={14} />
              <input 
                type="text"
                placeholder="KEYWORDS..."
                value={filterText}
                onChange={(e) => setFilterText(e.target.value)}
                className="w-full bg-black/40 border border-tui-border py-2 pl-9 pr-3 text-xs font-mono focus:outline-none focus:ring-1 focus:ring-tui-accent"
              />
            </div>
          </div>
        </aside>

        <div className="md:col-span-3">
          <div className="bg-black/20 border border-tui-border overflow-hidden">
            <div className="p-3 border-b border-tui-border bg-black/40 flex items-center justify-between">
              <span className="text-[10px] font-bold uppercase tracking-widest text-tui-dim">
                {filteredEvents.length} MATCHING_EVENTS
              </span>
            </div>
            <div className="p-4">
              <EventTimeline events={filteredEvents} isLoading={isLoading} showSessionLink />
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}
