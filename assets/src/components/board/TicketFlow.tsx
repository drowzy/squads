import { 
  ReactFlow, 
  Background, 
  Controls, 
  Node, 
  Edge,
  useNodesState,
  useEdgesState,
  ConnectionMode,
  useReactFlow
} from '@xyflow/react'
import '@xyflow/react/dist/style.css'
import { Ticket, useUpdateTicket, useAgents } from '../../api/queries'
import { TicketNode } from './TicketNode'
import { useEffect, useMemo, useState } from 'react'
import ELK from 'elkjs/lib/elk.bundled.js'
import { X, Info, Calendar, User, Tag, ChevronDown } from 'lucide-react'
import { useActiveProject } from '../../routes/__root'

const elk = new ELK()

const nodeTypes = {
  ticket: TicketNode,
}

const statusOptions: Ticket['status'][] = ['open', 'in_progress', 'blocked', 'closed']

interface TicketFlowProps {
  tickets: Ticket[]
}

const elkOptions = {
  'elk.algorithm': 'layered',
  'elk.direction': 'RIGHT',
  'elk.layered.spacing.nodeNodeLayered': '100',
  'elk.spacing.nodeNode': '80',
}

export function TicketFlow({ tickets }: TicketFlowProps) {
  const [nodes, setNodes, onNodesChange] = useNodesState<Node>([])
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([])
  const [selectedTicketId, setSelectedTicketId] = useState<string | null>(null)
  const { fitView } = useReactFlow()

  const { activeProject } = useActiveProject()
  const { data: agents = [] } = useAgents(activeProject?.id)

  const updateTicket = useUpdateTicket()

  const selectedTicket = useMemo(() => 
    tickets.find(t => t.id === selectedTicketId) || null,
  [tickets, selectedTicketId])

  useEffect(() => {
    const elkNodes: any[] = []
    const elkEdges: any[] = []

    // Grouping logic for ELK
    const epics = tickets.filter(t => t.issue_type === 'epic')
    const childrenByParent = tickets.reduce((acc, t) => {
      if (t.parent_id) {
        acc[t.parent_id] = acc[t.parent_id] || []
        acc[t.parent_id].push(t)
      }
      return acc
    }, {} as Record<string, Ticket[]>)

    tickets.forEach((ticket) => {
      // If it's a child of an epic, we'll handle it later if we do nested graphs
      // For now, let's keep it simple but ensure they are positioned near each other
      elkNodes.push({
        id: ticket.id,
        width: 256,
        height: 120,
      })
    })

    // Create a set for quick lookup of existing nodes to prevent dangling edges
    const nodeIds = new Set(tickets.map(t => t.id))

    tickets.forEach((ticket) => {
      if (ticket.dependencies) {
        ticket.dependencies.forEach(depId => {
          const actualDepId = depId.startsWith('discovered-from:') 
            ? depId.replace('discovered-from:', '')
            : depId
          
          if (nodeIds.has(actualDepId)) {
            elkEdges.push({
              id: `e-${actualDepId}-${ticket.id}`,
              sources: [actualDepId],
              targets: [ticket.id],
            })
          }
        })
      }

      if (ticket.parent_id && nodeIds.has(ticket.parent_id)) {
        elkEdges.push({
          id: `p-${ticket.parent_id}-${ticket.id}`,
          sources: [ticket.parent_id],
          targets: [ticket.id],
        })
      }
    })

    const graph = {
      id: 'root',
      layoutOptions: elkOptions,
      children: elkNodes,
      edges: elkEdges,
    }

    elk.layout(graph).then((layoutedGraph) => {
      const newNodes: Node[] = layoutedGraph.children?.map((node: any) => ({
        id: node.id,
        type: 'ticket',
        position: { x: node.x, y: node.y },
        data: { ticket: tickets.find(t => t.id === node.id) },
      })) || []

      const newEdges: Edge[] = layoutedGraph.edges?.map((edge: any) => {
        const isParent = edge.id.startsWith('p-')
        const ticket = tickets.find(t => t.id === edge.targets[0])
        
        return {
          id: edge.id,
          source: edge.sources[0],
          target: edge.targets[0],
          animated: !isParent && ticket?.status === 'in_progress',
          label: isParent ? 'parent' : undefined,
          labelStyle: isParent ? { fill: '#ff00ff', fontSize: 8, fontWeight: 'bold' } : undefined,
          style: { 
            stroke: isParent ? '#ff00ff' : '#00ff00', 
            strokeWidth: 1,
            strokeDasharray: isParent ? '5,5' : undefined
          },
        }
      }) || []

      setNodes(newNodes)
      setEdges(newEdges)
      // window.requestAnimationFrame(() => fitView())
    })
  }, [tickets, setNodes, setEdges, fitView])

  const onNodeClick = (_: any, node: Node) => {
    setSelectedTicketId(node.id)
  }

  const handleUpdateStatus = (status: Ticket['status']) => {
    if (selectedTicket) {
      updateTicket.mutate({ id: selectedTicket.id, status, project_id: activeProject?.id })
    }
  }

  const handleUpdateAssignee = (assignee: string) => {
    if (selectedTicket) {
      updateTicket.mutate({ id: selectedTicket.id, status: selectedTicket.status, assignee, project_id: activeProject?.id })
    }
  }

  return (
    <div className="h-full w-full bg-black/20 border border-tui-border relative overflow-hidden font-mono">
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        onNodeClick={onNodeClick}
        nodeTypes={nodeTypes}
        connectionMode={ConnectionMode.Loose}
      >
        <Background color="#00ff00" gap={20} size={1} />
        <Controls className="!bg-tui-bg !border-tui-border !fill-tui-text" />
      </ReactFlow>

      {/* Ticket Inspector Overlay - Full screen on mobile, sidebar on desktop */}
      {selectedTicket && (
        <>
          {/* Mobile overlay background */}
          <div 
            className="absolute inset-0 bg-black/60 z-10 md:hidden"
            onClick={() => setSelectedTicketId(null)}
          />
          <div className="absolute inset-4 md:inset-auto md:top-4 md:right-4 md:w-80 bg-tui-bg border border-tui-accent shadow-[0_0_30px_rgba(255,0,255,0.1)] z-20 flex flex-col md:max-h-[calc(100%-2rem)] animate-in fade-in slide-in-from-right duration-300">
            <div className="p-3 border-b border-tui-accent bg-tui-accent/10 flex justify-between items-center">
              <span className="text-xs font-bold text-tui-accent tracking-widest uppercase flex items-center gap-2">
                <Info size={14} />
                Ticket_Inspector
              </span>
              <button onClick={() => setSelectedTicketId(null)} className="text-tui-accent hover:text-white transition-colors p-1">
                <X size={20} />
              </button>
            </div>
          
          <div className="p-4 overflow-y-auto space-y-4 flex-1">
            <div className="flex justify-between items-start">
              <div>
                <span className="text-xs font-bold text-tui-dim uppercase tracking-widest block mb-1">ID</span>
                <span className="text-sm font-bold text-tui-accent">{selectedTicket.id}</span>
              </div>
              <div className="text-right">
                <span className="text-xs font-bold text-tui-dim uppercase tracking-widest block mb-1">Status</span>
                <div className="relative group">
                  <select 
                    value={selectedTicket.status}
                    onChange={(e) => handleUpdateStatus(e.target.value as Ticket['status'])}
                    className="appearance-none bg-tui-bg border border-tui-border px-2 py-1 text-xs uppercase cursor-pointer hover:border-tui-accent focus:outline-none focus:border-tui-accent pr-6"
                  >
                    {statusOptions.map(status => (
                      <option key={status} value={status}>{status}</option>
                    ))}
                  </select>
                  <ChevronDown size={10} className="absolute right-2 top-2 pointer-events-none text-tui-dim group-hover:text-tui-accent" />
                </div>
              </div>
            </div>

            <div>
              <span className="text-xs font-bold text-tui-dim uppercase tracking-widest block mb-1">Title</span>
              <h3 className="text-sm font-bold uppercase leading-tight border-l-2 border-tui-accent pl-2 py-1 bg-tui-accent/5">
                {selectedTicket.title}
              </h3>
            </div>

            <div>
              <span className="text-xs font-bold text-tui-dim uppercase tracking-widest block mb-1">Description</span>
              <p className="text-xs text-tui-text/80 leading-relaxed italic bg-black/20 p-2 border border-tui-border/30">
                {selectedTicket.description}
              </p>
            </div>

            <div className="grid grid-cols-2 gap-4 pt-2">
              <div className="space-y-1">
                <span className="text-xs font-bold text-tui-dim uppercase flex items-center gap-1">
                  <Tag size={10} /> Type
                </span>
                <span className="text-xs font-bold uppercase border border-tui-border px-1.5 py-0.5 inline-block">
                  {selectedTicket.issue_type}
                </span>
              </div>
              <div className="space-y-1">
                <span className="text-xs font-bold text-tui-dim uppercase flex items-center gap-1">
                  <User size={10} /> Assignee
                </span>
                <div className="relative group">
                  <select 
                    value={selectedTicket.assignee || ''}
                    onChange={(e) => handleUpdateAssignee(e.target.value)}
                    className="w-full appearance-none bg-tui-bg border border-tui-border px-2 py-1 text-xs uppercase cursor-pointer hover:border-tui-accent focus:outline-none focus:border-tui-accent pr-6"
                  >
                    <option value="">Unassigned</option>
                    {agents.map(agent => (
                      <option key={agent.id} value={agent.name}>{agent.name}</option>
                    ))}
                  </select>
                  <ChevronDown size={10} className="absolute right-2 top-2 pointer-events-none text-tui-dim group-hover:text-tui-accent" />
                </div>
              </div>
            </div>

            <div className="space-y-1 pt-2 border-t border-tui-border/30">
              <span className="text-xs font-bold text-tui-dim uppercase flex items-center gap-1">
                <Calendar size={10} /> Created_At
              </span>
              <span className="text-xs font-bold text-tui-dim">
                {new Date(selectedTicket.created_at).toLocaleString()}
              </span>
            </div>
          </div>

          <div className="p-3 border-t border-tui-border bg-tui-accent/5 flex flex-col gap-2 shrink-0">
             <div className="flex items-center justify-between text-xs font-bold text-tui-dim uppercase mb-1">
               <span>Quick_Actions</span>
               {updateTicket.isPending && <span className="animate-pulse text-tui-accent">Syncing...</span>}
             </div>
            <div className="flex gap-2">
              <button 
                onClick={() => handleUpdateStatus('closed')}
                disabled={selectedTicket.status === 'closed'}
                className="flex-1 border border-tui-text py-2.5 text-xs font-bold hover:bg-tui-text hover:text-tui-bg disabled:opacity-30 disabled:hover:bg-transparent disabled:hover:text-tui-text uppercase tracking-widest transition-all"
              >
                Close
              </button>
              {selectedTicket.status === 'blocked' ? (
                <button 
                  onClick={() => handleUpdateStatus('open')}
                  className="flex-1 border border-tui-accent py-2.5 text-xs font-bold hover:bg-tui-accent hover:text-tui-bg uppercase tracking-widest transition-all"
                >
                  Unblock
                </button>
              ) : (
                <button 
                  onClick={() => handleUpdateStatus('blocked')}
                  className="flex-1 border border-tui-accent py-2.5 text-xs font-bold hover:bg-tui-accent hover:text-tui-bg uppercase tracking-widest transition-all"
                >
                  Block
                </button>
              )}
            </div>
          </div>
        </div>
        </>
      )}
    </div>
  )
}
