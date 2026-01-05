import { createFileRoute } from '@tanstack/react-router'
import { useActiveProject } from './__root'
import { useEvents } from '../api/queries'
import { EventTimeline } from '../components/events/EventTimeline'
import { Terminal, Filter, RefreshCcw, Search, Hash } from 'lucide-react'
import { useState, useMemo } from 'react'
import { cn } from '../lib/cn'
import { ListToolbar } from '../components/ui/ListToolbar'

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
    { value: 'all', label: 'All Events' },
    { value: 'session:', label: 'Sessions' },
    { value: 'message:', label: 'Messages' },
    { value: 'ticket:', label: 'Tickets' },
    { value: 'mail:', label: 'Mail' },
    { value: 'agent:', label: 'Agents' },
  ]

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
            <Terminal className="text-tui-accent" />
            Event Log
          </h1>
          <p className="text-tui-dim text-sm mt-1 uppercase tracking-widest">
            Audit trail for {activeProject?.name || 'active project'}
          </p>
        </div>
      </div>

      <ListToolbar
        searchQuery={filterText}
        onSearchChange={setFilterText}
        searchPlaceholder="Keywords..."
        filters={[
          {
            icon: <Filter size={14} className="text-tui-dim shrink-0" />,
            value: kindFilter,
            onChange: setKindFilter,
            options: eventKinds,
          },
          {
            icon: <Hash size={14} className="text-tui-dim shrink-0" />,
            value: limit.toString(),
            onChange: (val) => setLimit(Number(val)),
            options: [
              { value: '20', label: 'Limit: 20' },
              { value: '50', label: 'Limit: 50' },
              { value: '100', label: 'Limit: 100' },
              { value: '500', label: 'Limit: 500' },
            ]
          }
        ]}
      >
        <button
          onClick={() => refetch()}
          disabled={isLoading || isRefetching}
          className="p-2 border border-tui-border bg-tui-bg hover:bg-tui-dim/10 text-tui-dim hover:text-tui-text transition-colors disabled:opacity-50"
          title="Refresh events"
        >
          <RefreshCcw size={18} className={cn(isRefetching && "animate-spin")} />
        </button>
      </ListToolbar>

      <div className="bg-black/20 border border-tui-border overflow-hidden">
        <div className="p-3 border-b border-tui-border bg-black/40 flex items-center justify-between">
          <span className="text-[10px] font-bold uppercase tracking-widest text-tui-dim">
            {filteredEvents.length} matching events
          </span>
        </div>
        <div className="p-4">
          <EventTimeline events={filteredEvents} isLoading={isLoading} showSessionLink />
        </div>
      </div>
    </div>
  )
}
