import { createFileRoute } from '@tanstack/react-router'
import { 
  Send, 
  Inbox, 
  Search, 
  Trash2, 
  Archive, 
  MoreVertical,
  ChevronRight,
  Plus,
  User,
  Clock,
  ArrowLeft,
  Loader2,
  AlertCircle,
  X
} from 'lucide-react'
import { useState, useMemo, useEffect } from 'react'
import { 
  useMailThreads, 
  useMailThread, 
  useReplyMessage, 
  useSendMessage,
  useAgents,
  MailThread, 
  MailMessage 
} from '../api/queries'
import { useActiveProject } from './__root'
import { cn } from '../lib/cn'
import { useNotifications } from '../components/Notifications'
import { ListToolbar } from '../components/ui/ListToolbar'

export const Route = createFileRoute('/mail')({
  component: MailSystem,
})

function MailSystem() {
  const { activeProject } = useActiveProject()
  const [selectedThreadId, setSelectedThreadId] = useState<string | null>(null)
  const [isComposeOpen, setIsComposeOpen] = useState(false)
  const [showFolders, setShowFolders] = useState(false)
  const [searchQuery, setSearchQuery] = useState('')

  const { data: threads = [], isLoading: isLoadingThreads, error: threadsError } = useMailThreads(activeProject?.id)

  const filteredThreads = useMemo(() => {
    return threads.filter(t => 
      t.subject.toLowerCase().includes(searchQuery.toLowerCase()) ||
      t.participants.some(p => p.toLowerCase().includes(searchQuery.toLowerCase()))
    )
  }, [threads, searchQuery])

  const handleSelectThread = (threadId: string) => {
    setSelectedThreadId(threadId)
  }

  if (isLoadingThreads) {
    return (
      <div className="h-full flex items-center justify-center">
        <Loader2 className="animate-spin text-tui-accent" size={32} />
      </div>
    )
  }

  if (threadsError) {
    return (
      <div className="h-full flex flex-col items-center justify-center text-tui-accent">
        <AlertCircle size={48} className="mb-4" />
        <h3 className="text-xl font-bold">Mail Subsystem Offline</h3>
        <p className="text-sm opacity-70">Verify backend mail endpoints</p>
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col space-y-4 md:space-y-6">
      <div className="flex justify-between items-start md:items-end gap-4">
        <div>
          <h2 className="text-xl md:text-2xl font-bold tracking-tighter uppercase">Squad Command / Mail</h2>
          <p className="text-tui-dim text-xs md:text-sm italic hidden sm:block">Secure inter-agent and mentor communication</p>
        </div>
        <button 
          aria-label="Compose new message"
          onClick={() => setIsComposeOpen(true)}
          className="bg-tui-accent text-tui-bg px-3 md:px-4 py-2 text-xs font-bold flex items-center gap-2 hover:bg-tui-accent/90 transition-colors uppercase tracking-widest shrink-0"
        >
          <Plus size={16} />
          <span className="hidden sm:inline">Compose New</span>
        </button>
      </div>

      <ListToolbar
        searchQuery={searchQuery}
        onSearchChange={setSearchQuery}
        searchPlaceholder="Search threads..."
      />

      <div className="flex-1 border border-tui-border flex flex-col md:flex-row bg-tui-bg/50 overflow-hidden relative">
        {/* Mobile folder toggle */}
        <button 
          aria-label="Toggle folders"
          onClick={() => setShowFolders(!showFolders)}
          className="md:hidden p-3 border-b border-tui-border flex items-center gap-2 text-xs font-bold text-tui-dim"
        >
          <Inbox size={16} />
          Inbox ({threads.reduce((acc, t) => acc + t.unread_count, 0)})
          <ChevronRight size={14} className={`ml-auto transition-transform ${showFolders ? 'rotate-90' : ''}`} />
        </button>

        {/* Sidebar Nav - hidden on mobile unless toggled */}
        <div className={`${showFolders ? 'block' : 'hidden'} md:block w-full md:w-48 border-b md:border-b-0 md:border-r border-tui-border flex flex-col bg-tui-dim/5`}>
          <nav className="p-2 space-y-1">
            <MailSidebarItem icon={<Inbox size={16} />} label="Inbox" count={threads.reduce((acc, t) => acc + t.unread_count, 0)} active onClick={() => setShowFolders(false)} />
            <MailSidebarItem icon={<Send size={16} />} label="Sent" onClick={() => setShowFolders(false)} />
            <MailSidebarItem icon={<Archive size={16} />} label="Archive" onClick={() => setShowFolders(false)} />
            <MailSidebarItem icon={<Trash2 size={16} />} label="Trash" onClick={() => setShowFolders(false)} />
          </nav>
        </div>

        {/* Content Area - show thread list or thread view (not both on mobile) */}
        <div className="flex-1 flex flex-col min-w-0">
          {/* Mobile: Show either list or thread, Desktop: Show list with thread overlay */}
          <div className={cn(
            "flex-1 flex flex-col",
            selectedThreadId ? "hidden md:flex" : "flex",
            showFolders && "hidden md:flex"
          )}>
            <div className="flex-1 overflow-y-auto divide-y divide-tui-border/50">
              {filteredThreads.length === 0 && (
                <div className="p-8 text-center text-tui-dim italic text-sm">No active threads found.</div>
              )}
              {filteredThreads.map((thread) => (
                <ThreadItem 
                  key={thread.id} 
                  thread={thread} 
                  onClick={() => handleSelectThread(thread.id)}
                />
              ))}
            </div>
          </div>
          
          {selectedThreadId && (
            <div className={cn(
              "flex-1 flex flex-col",
              !selectedThreadId && "hidden"
            )}>
              <ThreadView 
                threadId={selectedThreadId} 
                onBack={() => setSelectedThreadId(null)} 
              />
            </div>
          )}
        </div>

        {/* Compose Modal */}
        {isComposeOpen && (
          <ComposeOverlay onClose={() => setIsComposeOpen(false)} />
        )}
      </div>
    </div>
  )
}

function ComposeOverlay({ onClose }: { onClose: () => void }) {
  return (
    <div 
      className="absolute inset-0 bg-tui-bg/90 backdrop-blur-sm flex items-center justify-center p-2 md:p-6 z-10"
      onClick={(e) => { if (e.target === e.currentTarget) onClose(); }}
    >
      <ComposeModal onClose={onClose} />
    </div>
  )
}

function ThreadView({ threadId, onBack }: { threadId: string; onBack: () => void }) {
  const { data: messages = [], isLoading } = useMailThread(threadId)
  const [replyBody, setReplyBody] = useState('')
  const { activeProject } = useActiveProject()
  const { addNotification } = useNotifications()
  const replyMutation = useReplyMessage()

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onBack()
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [onBack])

  const handleReply = async () => {
    if (!replyBody.trim()) return
    try {
      await replyMutation.mutateAsync({ thread_id: threadId, body_md: replyBody, project_id: activeProject?.id })
      setReplyBody('')
      addNotification({
        type: 'success',
        title: 'Mail Sent',
        message: 'Reply delivered successfully.'
      })
    } catch (error) {
      console.error('Failed to send reply:', error)
      addNotification({
        type: 'error',
        title: 'Transmission Failure',
        message: 'Failed to deliver reply. Check subsystem status.'
      })
    }
  }

  if (isLoading) {
    return (
      <div className="flex-1 flex items-center justify-center">
        <Loader2 className="animate-spin text-tui-accent" size={24} />
      </div>
    )
  }

  const subject = messages[0]?.subject || 'Unknown Subject'

  return (
    <div className="flex-1 flex flex-col">
      <div className="h-12 border-b border-tui-border flex items-center px-2 bg-tui-dim/10">
        <button 
          aria-label="Back to threads"
          onClick={onBack}
          className="p-2 hover:bg-tui-dim/20 text-tui-dim hover:text-tui-text"
        >
          <ArrowLeft size={20} />
        </button>
        <div className="flex-1 px-2 font-bold text-xs truncate">
          {subject}
        </div>
        <div className="flex gap-1 p-2">
        <button 
          aria-label="Delete thread"
          className="p-2 hover:bg-tui-dim/20 text-tui-dim"
        >
          <Trash2 size={16} />
        </button>
        <button 
          aria-label="More options"
          className="p-2 hover:bg-tui-dim/20 text-tui-dim hidden sm:block"
        >
          <MoreVertical size={16} />
        </button>
        </div>
      </div>
      <div className="flex-1 overflow-y-auto p-4 md:p-6">
        <div className="max-w-3xl mx-auto space-y-6 md:space-y-8">
          {messages.map((msg) => (
            <div key={msg.id} className="space-y-4">
              <div className="flex flex-col sm:flex-row sm:justify-between sm:items-start border-b border-tui-border pb-4 gap-2">
                <div className="flex gap-3 md:gap-4">
                  <div className="w-8 h-8 md:w-10 md:h-10 border border-tui-border flex items-center justify-center bg-tui-dim/20 shrink-0">
                    <User size={16} className="text-tui-accent md:hidden" />
                    <User size={20} className="text-tui-accent hidden md:block" />
                  </div>
                  <div>
                    <div className="font-bold text-sm">{msg.sender_name}</div>
                    <div className="text-xs text-tui-dim uppercase">TO: {msg.to.join(', ')}</div>
                  </div>
                </div>
                <div className="text-xs text-tui-dim flex items-center gap-1 ml-11 sm:ml-0">
                  <Clock size={12} />
                  {new Date(msg.inserted_at).toLocaleString()}
                </div>
              </div>
              <div className="text-sm leading-relaxed font-mono whitespace-pre-wrap">
                {msg.body_md}
              </div>
            </div>
          ))}

          <div className="border-t border-tui-border pt-4 md:pt-6">
            <textarea 
              value={replyBody}
              onChange={(e) => setReplyBody(e.target.value)}
              placeholder="Type your reply..."
              className="w-full h-24 md:h-32 bg-black/40 border border-tui-border p-3 md:p-4 text-sm focus:border-tui-accent outline-none font-mono mb-4"
            />
            <div className="flex justify-end">
              <button 
                onClick={handleReply}
                disabled={replyMutation.isPending || !replyBody.trim()}
                className="bg-tui-text text-tui-bg px-4 md:px-6 py-2 text-xs font-bold flex items-center gap-2 uppercase tracking-widest transition-colors disabled:opacity-50"
              >
                {replyMutation.isPending ? <Loader2 size={16} className="animate-spin" /> : <Send size={16} />}
                Send_Reply
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  )
}

function ComposeModal({ onClose }: { onClose: () => void }) {
  const { activeProject } = useActiveProject()
  const { addNotification } = useNotifications()
  const [sender, setSender] = useState<string>('')
  const [to, setTo] = useState<string[]>([])
  const [subject, setSubject] = useState('')
  const [body, setBody] = useState('')
  
  const { data: agents = [] } = useAgents(activeProject?.id)

  const sendMutation = useSendMessage()

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose()
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [onClose])

  // Auto-select first agent as sender if not set
  useEffect(() => {
    if (agents.length > 0 && !sender) {
      setSender("Human")
    }
  }, [agents, sender])

  const handleSend = async () => {
    if (!sender || to.length === 0 || !subject.trim() || !body.trim()) return
    try {
      await sendMutation.mutateAsync({ to, subject, body_md: body, sender_name: sender, project_id: activeProject?.id })
      addNotification({
        type: 'success',
        title: 'Mail Sent',
        message: 'Message delivered successfully.'
      })
      onClose()
    } catch (error) {
      console.error('Failed to send message:', error)
      addNotification({
        type: 'error',
        title: 'Transmission Failure',
        message: 'Failed to deliver message. Check subsystem status.'
      })
    }
  }

  const toggleRecipient = (name: string) => {
    if (to.includes(name)) {
      setTo(to.filter(n => n !== name))
    } else {
      setTo([...to, name])
    }
  }

  return (
    <div className="w-full max-w-2xl border border-tui-accent bg-tui-bg shadow-[0_0_30px_rgba(255,0,255,0.1)] flex flex-col max-h-[95vh] md:max-h-[90vh]">
      <div className="p-3 border-b border-tui-accent bg-tui-accent/10 flex justify-between items-center">
        <span className="text-xs font-bold text-tui-accent tracking-widest uppercase flex items-center gap-2">
          <Plus size={14} />
          New Message
        </span>
        <button 
          aria-label="Close compose modal"
          onClick={onClose}
          className="text-tui-accent hover:text-white p-1"
        >
          <X size={20} />
        </button>
      </div>
      
      <div className="flex-1 overflow-y-auto p-4 md:p-6 space-y-4">
        <div className="space-y-2">
          <label className="text-xs font-bold text-tui-dim uppercase tracking-widest">From</label>
          <div className="flex flex-wrap gap-2 p-2 border border-tui-border bg-black/20 min-h-[44px]">
            <button
              onClick={() => setSender("Human")}
              className={`text-xs px-3 py-1.5 border transition-colors ${
                sender === "Human"
                  ? 'border-tui-accent bg-tui-accent/20 text-tui-text'
                  : 'border-tui-border text-tui-dim hover:border-tui-text'
              }`}
            >
              Human
            </button>
            {agents.map(agent => (
              <button
                key={agent.id}
                onClick={() => setSender(agent.name)}
                className={`text-xs px-3 py-1.5 border transition-colors ${
                  sender === agent.name 
                    ? 'border-tui-accent bg-tui-accent/20 text-tui-text' 
                    : 'border-tui-border text-tui-dim hover:border-tui-text'
                }`}
              >
                {agent.name}
              </button>
            ))}
          </div>
        </div>

        <div className="space-y-2">
          <label className="text-xs font-bold text-tui-dim uppercase tracking-widest">Recipients</label>
          <div className="flex flex-wrap gap-2 p-2 border border-tui-border bg-black/20 min-h-[44px]">
            {agents.filter(a => a.name !== sender).map(agent => (
              <button
                key={agent.id}
                onClick={() => toggleRecipient(agent.name)}
                className={`text-xs px-3 py-1.5 border transition-colors ${
                  to.includes(agent.name) 
                    ? 'border-tui-accent bg-tui-accent/20 text-tui-text' 
                    : 'border-tui-border text-tui-dim hover:border-tui-text'
                }`}
              >
                {agent.name}
              </button>
            ))}
            {agents.filter(a => a.name !== sender).length === 0 && (
              <span className="text-xs text-tui-dim italic uppercase">No Recipients Available</span>
            )}
          </div>
        </div>

        <div className="space-y-2">
          <label className="text-xs font-bold text-tui-dim uppercase tracking-widest">Subject</label>
          <input 
            type="text"
            value={subject}
            onChange={(e) => setSubject(e.target.value)}
            placeholder="Subject line..."
            className="w-full bg-black/40 border border-tui-border p-3 text-sm focus:border-tui-accent outline-none font-mono"
          />
        </div>

        <div className="space-y-2 flex-1 flex flex-col">
          <label className="text-xs font-bold text-tui-dim uppercase tracking-widest">Message Body</label>
          <textarea 
            value={body}
            onChange={(e) => setBody(e.target.value)}
            placeholder="Type your message in Markdown..."
            className="w-full flex-1 min-h-[150px] md:min-h-[200px] bg-black/40 border border-tui-border p-3 text-sm focus:border-tui-accent outline-none font-mono"
          />
        </div>
      </div>

      <div className="p-4 border-t border-tui-border flex flex-col sm:flex-row justify-end gap-3">
        <button 
          onClick={onClose}
          className="px-6 py-2.5 text-xs font-bold text-tui-dim hover:text-tui-text transition-colors uppercase tracking-widest order-2 sm:order-1"
        >
          Cancel
        </button>
        <button 
          onClick={handleSend}
          disabled={sendMutation.isPending || !sender || to.length === 0 || !subject.trim() || !body.trim()}
          className="bg-tui-accent text-tui-bg px-6 py-2.5 text-xs font-bold flex items-center justify-center gap-2 uppercase tracking-widest transition-colors disabled:opacity-50 order-1 sm:order-2"
        >
          {sendMutation.isPending ? <Loader2 size={16} className="animate-spin" /> : <Send size={16} />}
          Send
        </button>
      </div>
    </div>
  )
}

function ThreadItem({ thread, onClick }: { thread: MailThread; onClick: () => void }) {
  return (
    <div 
      onClick={onClick}
      className={`
        p-4 cursor-pointer hover:bg-tui-dim/5 flex gap-4 items-start
        ${thread.unread_count > 0 ? 'border-l-2 border-tui-accent bg-tui-accent/5' : ''}
      `}
    >
      <div className="flex-1 min-w-0">
        <div className="flex justify-between items-center mb-1 gap-2">
          <span className={`text-xs font-bold truncate ${thread.unread_count > 0 ? 'text-tui-text' : 'text-tui-dim'}`}>
            {thread.participants.join(', ')}
          </span>
          <span className="text-xs text-tui-dim shrink-0">{new Date(thread.last_message_at).toLocaleTimeString()}</span>
        </div>
        <h4 className={`text-sm truncate ${thread.unread_count > 0 ? 'font-bold' : 'text-tui-dim/80'}`}>
          {thread.subject}
        </h4>
        <div className="flex items-center gap-2 mt-1">
          <span className="text-xs bg-tui-dim/20 px-1.5 py-0.5 rounded text-tui-dim">
            {thread.message_count} messages
          </span>
          {thread.unread_count > 0 && (
            <span className="text-xs bg-tui-accent text-tui-bg px-1.5 py-0.5 rounded font-bold">
              {thread.unread_count} new
            </span>
          )}
        </div>
      </div>
      <ChevronRight size={16} className="text-tui-border self-center shrink-0" />
    </div>
  )
}

function MailSidebarItem({ 
  icon, 
  label, 
  count, 
  active = false,
  onClick
}: { 
  icon: React.ReactNode; 
  label: string; 
  count?: number; 
  active?: boolean;
  onClick?: () => void;
}) {
  return (
    <div 
      onClick={onClick}
      className={`
      flex items-center justify-between px-3 py-3 md:py-2 cursor-pointer transition-colors
      ${active ? 'bg-tui-dim/20 text-tui-text' : 'text-tui-dim hover:bg-tui-dim/10 hover:text-tui-text'}
    `}>
      <div className="flex items-center gap-3">
        {icon}
        <span className="text-xs font-bold tracking-widest">{label}</span>
      </div>
      {count !== undefined && count > 0 && (
        <span className="text-xs font-bold bg-tui-accent text-tui-bg px-1.5 rounded-sm">{count}</span>
      )}
    </div>
  )
}
