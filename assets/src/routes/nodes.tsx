import { createFileRoute, Link } from '@tanstack/react-router'
import { useExternalNodes, useProbeExternalNode } from '../api/queries'
import { Wifi, Plus, RefreshCcw, ExternalLink, Activity, Info, Terminal } from 'lucide-react'
import { useState, useRef } from 'react'
import { cn } from '../lib/cn'
import { useNotifications } from '../components/Notifications'

export const Route = createFileRoute('/nodes')({
  component: NodesPage,
})

function NodesPage() {
  const { data: nodes, isLoading, refetch, isRefetching } = useExternalNodes()
  const probeNode = useProbeExternalNode()
  const { addNotification } = useNotifications()
  const [newUrl, setNewUrl] = useState('')
  const manualAttachRef = useRef<HTMLDivElement | null>(null)

  const handleManualAdd = async (e: React.FormEvent) => {
    e.preventDefault()
    if (!newUrl) return
    
    try {
      await probeNode.mutateAsync(newUrl)
      addNotification({
        type: 'success',
        title: 'Node Added',
        message: `Successfully connected to ${newUrl}`
      })
      setNewUrl('')
    } catch (err) {
      addNotification({
        type: 'error',
        title: 'Connection Failed',
        message: 'Could not reach OpenCode node at the specified URL'
      })
    }
  }

  return (
    <div className="space-y-6">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
            <Wifi className="text-tui-accent" />
            EXTERNAL_NODES
          </h1>
          <p className="text-tui-dim text-sm mt-1 uppercase tracking-widest">
            Discover and connect to "Ronin" OpenCode instances
          </p>
        </div>
        <button
          onClick={() => refetch()}
          disabled={isLoading || isRefetching}
          className="p-2 border border-tui-border hover:bg-tui-dim/10 text-tui-dim hover:text-tui-text transition-colors disabled:opacity-50"
        >
          <RefreshCcw size={18} className={cn(isRefetching && "animate-spin")} />
        </button>
      </div>

      <div className="grid grid-cols-1 lg:grid-cols-3 gap-6">
        <div className="lg:col-span-2 space-y-4">
          {isLoading ? (
            <div className="p-8 border border-tui-border bg-black/20 text-center animate-pulse text-tui-dim">
              SCANNING_NETWORK...
            </div>
          ) : nodes?.length === 0 ? (
            <div className="p-12 border border-tui-border bg-black/20 text-center space-y-4">
              <p className="text-tui-dim uppercase tracking-widest text-xs">No external nodes detected</p>
              <p className="text-[10px] text-tui-dim/60 italic max-w-xs mx-auto">
                Nodes are discovered via local port scanning (lsof) or manual URL entry.
              </p>
              <div className="flex flex-wrap items-center justify-center gap-2 pt-2">
                <button
                  onClick={() => refetch()}
                  className="px-3 py-1.5 border border-tui-border text-[10px] font-bold uppercase tracking-widest text-tui-dim hover:text-tui-text hover:border-tui-accent transition-colors"
                >
                  Rescan
                </button>
                <button
                  onClick={() => manualAttachRef.current?.scrollIntoView({ behavior: 'smooth', block: 'center' })}
                  className="px-3 py-1.5 border border-tui-accent text-[10px] font-bold uppercase tracking-widest text-tui-accent hover:bg-tui-accent hover:text-tui-bg transition-colors"
                >
                  Manual_Attach
                </button>
              </div>
            </div>
          ) : (
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              {nodes?.map((node) => (
                <div key={node.base_url} className="border border-tui-border bg-black/20 group hover:border-tui-accent/50 transition-colors">
                  <div className="p-4 space-y-3">
                    <div className="flex items-center justify-between">
                      <div className="flex items-center gap-2">
                        <div className={cn(
                          "w-2 h-2 rounded-full",
                          node.healthy ? "bg-ctp-green animate-pulse" : "bg-ctp-red"
                        )} />
                        <span className="text-xs font-bold font-mono text-tui-text truncate max-w-[150px]">
                          {node.base_url}
                        </span>
                      </div>
                      <span className="text-[9px] font-bold uppercase tracking-tighter px-1 border border-tui-border text-tui-dim group-hover:border-tui-accent/30 group-hover:text-tui-accent/70 transition-colors">
                        {node.source}
                      </span>
                    </div>

                    <div className="space-y-1">
                      <div className="flex justify-between text-[10px] font-mono">
                        <span className="text-tui-dim">VERSION:</span>
                        <span className="text-tui-text">{node.version || 'UNKNOWN'}</span>
                      </div>
                      <div className="flex justify-between text-[10px] font-mono">
                        <span className="text-tui-dim">LAST_SEEN:</span>
                        <span className="text-tui-text">{new Date(node.last_seen_at).toLocaleTimeString()}</span>
                      </div>
                    </div>

                    <div className="pt-2 flex gap-2">
                       <Link 
                        to="/sessions"
                        search={{ node: node.base_url }}
                        className="flex-1 py-1.5 border border-tui-border text-[10px] font-bold uppercase tracking-widest text-center hover:bg-tui-dim/10 transition-colors"
                      >
                        Browse_Sessions
                      </Link>
                      <a 
                        href={node.base_url}
                        target="_blank"
                        rel="noopener noreferrer"
                        className="p-1.5 border border-tui-border text-tui-dim hover:text-tui-accent transition-colors"
                      >
                        <ExternalLink size={14} />
                      </a>
                    </div>
                  </div>
                </div>
              ))}
            </div>
          )}
        </div>

        <aside className="space-y-6">
          <section ref={manualAttachRef} className="border border-tui-border bg-black/20 p-4 space-y-4">
            <h3 className="text-xs font-bold uppercase tracking-widest flex items-center gap-2">
              <Plus size={14} className="text-tui-accent" />
              Manual_Attach
            </h3>
            <form onSubmit={handleManualAdd} className="space-y-2">
              <input 
                type="text"
                placeholder="http://127.0.0.1:4096"
                value={newUrl}
                onChange={(e) => setNewUrl(e.target.value)}
                className="w-full bg-black/40 border border-tui-border py-2 px-3 text-xs font-mono focus:outline-none focus:ring-1 focus:ring-tui-accent"
              />
              <button 
                type="submit"
                disabled={probeNode.isPending || !newUrl}
                className="w-full py-2 bg-tui-accent text-tui-bg text-xs font-bold uppercase tracking-widest hover:bg-tui-accent/90 transition-colors disabled:opacity-50"
              >
                {probeNode.isPending ? 'CONNECTING...' : 'CONNECT_NODE'}
              </button>
            </form>
          </section>

          <section className="border border-tui-border p-4 space-y-3">
             <h3 className="text-xs font-bold uppercase tracking-widest flex items-center gap-2 text-tui-dim">
              <Info size={14} />
              About_Discovery
            </h3>
            <div className="space-y-2 text-[10px] text-tui-dim/80 leading-relaxed font-mono">
              <p>
                <span className="text-tui-accent font-bold">Local_LSOF:</span> Scans your local machine for listening processes named "opencode".
              </p>
              <p>
                <span className="text-tui-accent font-bold">Config:</span> Static endpoints defined in the server configuration.
              </p>
              <p>
                External nodes are treated as "transient" - Squads acts as a proxy for browsing and interaction without importing their full state into the local database.
              </p>
            </div>
          </section>
        </aside>
      </div>
    </div>
  )
}
