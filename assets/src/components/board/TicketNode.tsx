import { Handle, Position, NodeProps } from '@xyflow/react'
import { Ticket } from '../../api/queries'
import { ClipboardList, Clock, AlertCircle, CheckCircle2 } from 'lucide-react'

const statusIcons = {
  open: <ClipboardList size={12} />,
  in_progress: <Clock size={12} className="text-tui-accent" />,
  blocked: <AlertCircle size={12} className="text-red-500" />,
  closed: <CheckCircle2 size={12} className="text-tui-text" />,
}

export function TicketNode({ data }: NodeProps) {
  const ticket = data.ticket as Ticket
  const isEpic = ticket.issue_type === 'epic'
  
  return (
    <div className={`bg-tui-bg border ${isEpic ? 'border-tui-accent border-2' : 'border-tui-border'} p-3 w-64 shadow-[0_0_15px_rgba(0,255,0,0.05)] hover:border-tui-accent transition-colors group relative`}>
      {isEpic && (
        <div className="absolute -top-2 -left-2 bg-tui-accent text-tui-bg text-[8px] font-bold px-1 py-0.5 z-10 uppercase tracking-widest">
          EPIC
        </div>
      )}
      <Handle type="target" position={Position.Top} className="!bg-tui-border !w-2 !h-2" />
      
      <div className="flex justify-between items-start mb-2">
        <span className="text-[10px] font-bold text-tui-dim group-hover:text-tui-accent font-mono">
          {ticket.id}
        </span>
        <div className="flex gap-1">
          {statusIcons[ticket.status]}
        </div>
      </div>
      
      <h4 className="text-xs font-bold leading-tight mb-2 line-clamp-2 uppercase tracking-tight">
        {ticket.title}
      </h4>

      <div className="flex items-center justify-between mt-2 pt-2 border-t border-tui-border/30">
        <span className="text-[8px] border border-tui-border px-1 uppercase text-tui-dim">
          {ticket.issue_type}
        </span>
        {ticket.assignee && (
          <div className="flex items-center gap-1">
            <div className="w-3 h-3 border border-tui-border flex items-center justify-center bg-tui-dim/20">
              <span className="text-[6px] font-bold">{ticket.assignee[0].toUpperCase()}</span>
            </div>
            <span className="text-[8px] text-tui-dim">{ticket.assignee}</span>
          </div>
        )}
      </div>

      <Handle type="source" position={Position.Bottom} className="!bg-tui-border !w-2 !h-2" />
    </div>
  )
}
