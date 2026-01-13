import { Activity, FileText, History, ListTodo, ChevronLeft, ChevronRight } from 'lucide-react'
import { cn } from '../lib/cn'

type SidebarTab = 'logs' | 'stats' | 'timeline' | 'todos'

interface RightSidebarProps {
  isOpen: boolean
  activeTab: SidebarTab
  onTabChange: (tab: SidebarTab) => void
  onClose: () => void
  logsContent?: React.ReactNode
  statsContent?: React.ReactNode
  timelineContent?: React.ReactNode
  todosContent?: React.ReactNode
}

const tabs: Array<{ id: SidebarTab; label: string; icon: React.ReactNode }> = [
  { id: 'logs', label: 'Logs', icon: <Activity size={14} /> },
  { id: 'stats', label: 'Stats', icon: <FileText size={14} /> },
  { id: 'timeline', label: 'Timeline', icon: <History size={14} /> },
  { id: 'todos', label: 'Tasks', icon: <ListTodo size={14} /> },
]

export function RightSidebar({
  isOpen,
  activeTab,
  onTabChange,
  onClose,
  logsContent,
  statsContent,
  timelineContent,
  todosContent,
}: RightSidebarProps) {
  if (!isOpen) return null

  const getContent = () => {
    switch (activeTab) {
      case 'logs':
        return logsContent
      case 'stats':
        return statsContent
      case 'timeline':
        return timelineContent
      case 'todos':
        return todosContent
      default:
        return null
    }
  }

  return (
    <div className="h-full flex flex-col border-l border-tui-border bg-ctp-mantle/50 animate-in slide-in-from-right duration-200 w-80">
      <div className="flex items-center justify-between px-3 py-2 border-b border-tui-border bg-ctp-crust/40 shrink-0">
        <div className="flex items-center gap-1">
          {tabs.map((tab) => (
            <button
              key={tab.id}
              onClick={() => onTabChange(tab.id)}
              className={cn(
                'flex items-center gap-1.5 px-2 py-1 text-[10px] font-bold uppercase tracking-widest transition-colors rounded-sm',
                activeTab === tab.id
                  ? 'bg-tui-accent text-tui-bg'
                  : 'text-tui-dim hover:text-tui-text hover:bg-tui-dim/5'
              )}
            >
              {tab.icon}
              {tab.label}
            </button>
          ))}
        </div>
        <button
          onClick={onClose}
          className="p-1 text-tui-dim hover:text-tui-accent transition-colors"
          title="Close sidebar"
        >
          <ChevronRight size={14} />
        </button>
      </div>

      <div className="flex-1 overflow-y-auto custom-scrollbar">
        {getContent()}
      </div>

      <div className="border-t border-tui-border p-2 bg-ctp-crust/40 shrink-0">
        <div className="text-[9px] text-tui-dim">
          Press <kbd className="px-1 py-0.5 rounded border border-tui-border bg-tui-dim/10">]</kbd> to close
        </div>
      </div>
    </div>
  )
}
