import { useState } from 'react'
import { Modal } from '../Modal'
import { useCreateTicket } from '../../api/queries'
import { Ticket } from 'lucide-react'

interface CreateTicketModalProps {
  isOpen: boolean
  onClose: () => void
  projectId: string
}

export function CreateTicketModal({ isOpen, onClose, projectId }: CreateTicketModalProps) {
  const [title, setTitle] = useState('')
  const [issueType, setIssueType] = useState('task')
  const [priority, setPriority] = useState(2)
  const createTicket = useCreateTicket()

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    if (!title.trim()) return

    createTicket.mutate(
      {
        project_id: projectId,
        title,
        issue_type: issueType,
        priority
      },
      {
        onSuccess: () => {
          setTitle('')
          setIssueType('task')
          setPriority(2)
          onClose()
        }
      }
    )
  }

  return (
    <Modal isOpen={isOpen} onClose={onClose} title="Create Ticket">
      <form onSubmit={handleSubmit} className="space-y-4">
        <div>
          <label className="block text-xs font-bold text-tui-dim uppercase mb-1">Title</label>
          <input
            type="text"
            value={title}
            onChange={(e) => setTitle(e.target.value)}
            className="w-full bg-ctp-crust border border-tui-border-dim px-3 py-2 text-sm font-mono focus:border-tui-accent focus:outline-none placeholder:text-tui-dim/30"
            placeholder="Implement new feature..."
            autoFocus
          />
        </div>

        <div className="grid grid-cols-2 gap-4">
          <div>
            <label className="block text-xs font-bold text-tui-dim uppercase mb-1">Type</label>
            <select
              value={issueType}
              onChange={(e) => setIssueType(e.target.value)}
               className="w-full bg-ctp-crust border border-tui-border-dim px-3 py-2 text-sm font-mono focus:border-tui-accent focus:outline-none appearance-none"
            >
              <option value="feature">Feature</option>
              <option value="bug">Bug</option>
              <option value="task">Task</option>
              <option value="epic">Epic</option>
              <option value="chore">Chore</option>
            </select>
          </div>

          <div>
            <label className="block text-xs font-bold text-tui-dim uppercase mb-1">Priority</label>
            <select
              value={priority}
              onChange={(e) => setPriority(Number(e.target.value))}
               className="w-full bg-ctp-crust border border-tui-border-dim px-3 py-2 text-sm font-mono focus:border-tui-accent focus:outline-none appearance-none"
            >
              <option value={0}>0 - Critical</option>
              <option value={1}>1 - High</option>
              <option value={2}>2 - Medium</option>
              <option value={3}>3 - Low</option>
              <option value={4}>4 - Backlog</option>
            </select>
          </div>
        </div>

        <div className="flex justify-end pt-4">
          <button
            type="button"
            onClick={onClose}
            className="px-4 py-2 text-xs font-bold uppercase text-tui-dim hover:text-tui-text mr-2"
          >
            Cancel
          </button>
          <button
            type="submit"
            disabled={createTicket.isPending || !title.trim()}
            className="px-4 py-2 bg-tui-accent text-tui-bg text-xs font-bold uppercase hover:bg-white transition-colors disabled:opacity-50"
          >
            {createTicket.isPending ? 'Creating...' : 'Create Ticket'}
          </button>
        </div>
      </form>
    </Modal>
  )
}
