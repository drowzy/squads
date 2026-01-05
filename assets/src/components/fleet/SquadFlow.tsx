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
import {
  Squad,
  SquadConnection,
} from '../../api/queries'
import { SquadNode } from './SquadNode'
import { useEffect } from 'react'
import ELK from 'elkjs/lib/elk.bundled.js'

const elk = new ELK()

const nodeTypes = {
  squad: SquadNode,
}

interface SquadFlowProps {
  squads: Squad[]
  connections: SquadConnection[]
  onMessage?: (to: Squad) => void
}

const elkOptions = {
  'elk.algorithm': 'layered',
  'elk.direction': 'RIGHT',
  'elk.layered.spacing.nodeNodeLayered': '120',
  'elk.spacing.nodeNode': '100',
}

export function SquadFlow({ squads, connections, onMessage }: SquadFlowProps) {
  const [nodes, setNodes, onNodesChange] = useNodesState<Node>([])
  const [edges, setEdges, onEdgesChange] = useEdgesState<Edge>([])
  const { fitView } = useReactFlow()

  useEffect(() => {
    if (squads.length === 0) return

    const elkNodes: any[] = []
    const elkEdges: any[] = []

    squads.forEach((squad) => {
      elkNodes.push({
        id: squad.id,
        width: 256,
        height: 120,
      })
    })

    const nodeIds = new Set(squads.map(s => s.id))

    connections.forEach((conn) => {
      if (conn.from_squad_id && conn.to_squad_id && 
          nodeIds.has(conn.from_squad_id) && nodeIds.has(conn.to_squad_id)) {
        elkEdges.push({
          id: conn.id,
          sources: [conn.from_squad_id],
          targets: [conn.to_squad_id],
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
        type: 'squad',
        position: { x: node.x, y: node.y },
        data: { 
          squad: squads.find(s => s.id === node.id),
          onMessage
        },
      })) || []

      const newEdges: Edge[] = layoutedGraph.edges?.map((edge: any) => ({
        id: edge.id,
        source: edge.sources[0],
        target: edge.targets[0],
        animated: true,
        style: { 
          stroke: '#00ff00', 
          strokeWidth: 2,
        },
      })) || []

      setNodes(newNodes)
      setEdges(newEdges)
      window.requestAnimationFrame(() => fitView({ padding: 50 }))
    })
  }, [squads, connections, setNodes, setEdges, fitView])

  return (
    <div className="h-[400px] w-full bg-black/20 border border-tui-border relative overflow-hidden font-mono mb-8">
      <div className="absolute top-2 left-2 z-10">
        <span className="text-[10px] font-bold text-tui-accent bg-tui-bg px-2 py-1 border border-tui-accent/30 uppercase tracking-widest">
          Squad_Network_Graph
        </span>
      </div>
      <ReactFlow
        nodes={nodes}
        edges={edges}
        onNodesChange={onNodesChange}
        onEdgesChange={onEdgesChange}
        nodeTypes={nodeTypes}
        connectionMode={ConnectionMode.Loose}
        zoomOnScroll={false}
        panOnScroll={true}
        preventScrolling={false}
      >
        <Background color="#00ff00" gap={20} size={1} />
        <Controls className="!bg-tui-bg !border-tui-border !fill-tui-text" />
      </ReactFlow>
    </div>
  )
}
