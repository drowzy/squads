import { Handle, Position, NodeProps } from '@xyflow/react'
import { Squad } from '../../api/queries'
import { Box, Activity, Shield, Cpu } from 'lucide-react'

const statusIcons = {
  idle: <Box size={12} className="text-tui-dim" />,
  provisioning: <Cpu size={12} className="text-tui-accent animate-pulse" />,
  running: <Activity size={12} className="text-tui-accent" />,
  failed: <Shield size={12} className="text-red-500" />,
}

export function SquadNode({ data }: NodeProps) {
  const squad = data.squad as Squad
  
  return (
    <div className="bg-tui-bg border border-tui-border p-3 w-64 shadow-[0_0_15px_rgba(0,255,0,0.05)] hover:border-tui-accent transition-colors group relative font-mono">
      <Handle type="target" position={Position.Top} className="!bg-tui-border !w-2 !h-2" />
      
      <div className="flex justify-between items-start mb-2">
        <span className="text-[10px] font-bold text-tui-dim group-hover:text-tui-accent">
          {squad.id}
        </span>
        <div className="flex gap-1">
          {statusIcons[squad.status as keyof typeof statusIcons] || statusIcons.idle}
        </div>
      </div>
      
      <h4 className="text-xs font-bold leading-tight mb-1 uppercase tracking-tight">
        {squad.name}
      </h4>

      {squad.project_name && (
        <div className="text-[10px] text-tui-accent/70 uppercase truncate mb-2">
          Project: {squad.project_name}
        </div>
      )}

      <div className="flex items-center justify-between mt-2 pt-2 border-t border-tui-border/30">
        <span className="text-[8px] border border-tui-border px-1 uppercase text-tui-dim">
          {squad.status}
        </span>
        {squad.description && (
            <span className="text-[8px] text-tui-dim truncate ml-2 italic">
                {squad.description}
            </span>
        )}
      </div>

      <Handle type="source" position={Position.Bottom} className="!bg-tui-border !w-2 !h-2" />
    </div>
  )
}
