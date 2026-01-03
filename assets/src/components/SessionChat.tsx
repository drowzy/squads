import { useState, useEffect, useRef, useMemo } from 'react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'
import { Prism as SyntaxHighlighter } from 'react-syntax-highlighter'
import { vscDarkPlus } from 'react-syntax-highlighter/dist/esm/styles/prism'
import { 
  Terminal, 
  Archive, 
  Pencil, 
  Send, 
  Loader2, 
  ChevronRight,
  Zap,
  FileText,
  Command,
  RefreshCw
} from 'lucide-react'
import {
  useSessionMessages,
  useSendSessionPrompt,
  useExecuteSessionCommand,
  useRunSessionShell,
  useProjectFiles,
  type Session,
  type SessionMessageEntry,
  type SessionMessagePart,
  type SessionMessageToolPart,
  type SessionMessageInfo,
} from '../api/queries'
import { useNotifications } from './Notifications'
import { cn } from '../lib/cn'
import { useProjectEvents } from '../lib/socket'
import { useQueryClient } from '@tanstack/react-query'

// Mode type for plan/build toggle
export type AgentMode = 'plan' | 'build'

const normalizeEventKind = (kind: string) => kind.replace(/^(\w+)\./, '$1:')

interface SessionChatProps {
  session: Session
  className?: string
  /** Current mode for the session (sticky per session) */
  mode?: AgentMode
  /** Callback when mode changes */
  onModeChange?: (mode: AgentMode) => void
  /** Whether to show the mode toggle */
  showModeToggle?: boolean
  /** Whether to show header */
  showHeader?: boolean
  /** Custom header content */
  headerContent?: React.ReactNode
  /** Callback when /new command is triggered */
  onNewSession?: () => void
}

const COMMANDS = [
  { id: '/new', label: 'New Session', description: 'Start a fresh session for the agent' },
  { id: '/compact', label: 'Compact', description: 'Force history compaction' },
  { id: '/help', label: 'Help', description: 'Show available commands' },
  { id: '/sessions', label: 'Sessions', description: 'List session history' },
  { id: '/reset', label: 'Reset', description: 'Reset agent state' },
]

export function SessionChat({
  session,
  className,
  mode = 'plan',
  onModeChange,
  showModeToggle = true,
  showHeader = true,
  headerContent,
  onNewSession,
}: SessionChatProps) {
  const [chatInput, setChatInput] = useState('')
  const [autocomplete, setAutocomplete] = useState<{
    active: boolean
    trigger: '/' | '@' | null
    query: string
    index: number
    position: { top: number; left: number }
  }>({
    active: false,
    trigger: null,
    query: '',
    index: 0,
    position: { top: 0, left: 0 }
  })

  const messagesEndRef = useRef<HTMLDivElement | null>(null)
  const textareaRef = useRef<HTMLTextAreaElement | null>(null)
  const autocompleteRef = useRef<HTMLDivElement | null>(null)

  const sendPrompt = useSendSessionPrompt()
  const executeCommand = useExecuteSessionCommand()
  const runShell = useRunSessionShell()
  const { addNotification } = useNotifications()

  const queryClient = useQueryClient()

  // Subscribe to real-time events for this project
  useProjectEvents({
    projectId: session.project_id,
    onEvent: (event) => {
      const kind = normalizeEventKind(event.kind)
      // If a message was created or status changed for THIS session, invalidate queries
      if (
        (kind === 'session:status_changed' && event.session_id === session.id) ||
        (kind === 'message:created' && event.session_id === session.id)
      ) {
        console.log('Session event received, invalidating queries:', kind)
        queryClient.invalidateQueries({ queryKey: ['sessions', session.id, 'messages'] })
        queryClient.invalidateQueries({ queryKey: ['sessions', session.id] })
      }
    }
  })

  const { data: fileData } = useProjectFiles(session.project_id)
  const projectFiles = useMemo(() => {
    // Return empty if fileData or fileData.files is undefined/null
    if (!fileData || !fileData.files) return []
    return fileData.files
  }, [fileData])

  const { data: sessionMessages = [], isLoading: isLoadingMessages } = useSessionMessages(
    session.id,
    {
      enabled: !!session.id,
      limit: 100,
      refetchInterval: session.status === 'running' ? 2500 : false,
    }
  )

  const messagesContainerRef = useRef<HTMLDivElement | null>(null)

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' })
  }, [session.id, sessionMessages.length])

  // Reset chat input and autocomplete when session changes
  useEffect(() => {
    setChatInput('')
    setAutocomplete(prev => ({ ...prev, active: false }))
  }, [session.id])

  // Autocomplete logic
  const filteredSuggestions = useMemo(() => {
    if (!autocomplete.active) return []
    
    if (autocomplete.trigger === '/') {
      return COMMANDS.filter(cmd => cmd.id.startsWith('/' + autocomplete.query))
    }
    
    if (autocomplete.trigger === '@') {
      const q = autocomplete.query.toLowerCase()
      console.log('Filtering project files:', { q, totalFiles: projectFiles.length, files: projectFiles.slice(0, 5) })
      return projectFiles
        .filter(f => f.toLowerCase().includes(q))
        .slice(0, 10) // Limit to 10 for performance
        .map(f => ({ id: f, label: f, description: '' }))
    }
    
    return []
  }, [autocomplete.active, autocomplete.trigger, autocomplete.query, projectFiles])

  const handleAutocompleteSelect = (suggestion: { id: string }) => {
    const cursorPosition = textareaRef.current?.selectionStart || 0
    const textBeforeCursor = chatInput.substring(0, cursorPosition)
    const textAfterCursor = chatInput.substring(cursorPosition)
    
    const lastWordMatch = textBeforeCursor.match(/([/@])(\w*)$/)
    if (!lastWordMatch) return

    const matchStart = lastWordMatch.index!
    
    const beforeMatch = textBeforeCursor.substring(0, matchStart)
    const newValue = beforeMatch + suggestion.id + ' ' + textAfterCursor
    
    setChatInput(newValue)
    setAutocomplete(prev => ({ ...prev, active: false }))
    
    // Set focus back to textarea
    setTimeout(() => {
      textareaRef.current?.focus()
      const newPos = beforeMatch.length + suggestion.id.length + 1
      textareaRef.current?.setSelectionRange(newPos, newPos)
    }, 0)
  }

  const handleChatInputChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const value = e.target.value
    setChatInput(value)

    const cursorPosition = e.target.selectionStart
    const textBeforeCursor = value.substring(0, cursorPosition)
    
    const lastWordMatch = textBeforeCursor.match(/([/@])(\w*)$/)
    
    if (lastWordMatch) {
      const trigger = lastWordMatch[1] as '/' | '@'
      const query = lastWordMatch[2]
      
      console.log('Autocomplete triggered:', { trigger, query })

      // Calculate position based on textarea and cursor
      const rect = e.target.getBoundingClientRect()
      const containerRect = messagesContainerRef.current?.getBoundingClientRect()
      
      setAutocomplete({
        active: true,
        trigger,
        query,
        index: 0,
        position: {
          top: rect.top - (containerRect?.top || 0),
          left: 0
        }
      })
    } else if (autocomplete.active) {
      setAutocomplete(prev => ({ ...prev, active: false }))
    }
  }

  const handleKeyDown = (e: React.KeyboardEvent<HTMLTextAreaElement>) => {
    if (autocomplete.active && filteredSuggestions.length > 0) {
      if (e.key === 'ArrowDown') {
        e.preventDefault()
        setAutocomplete(prev => ({ ...prev, index: (prev.index + 1) % filteredSuggestions.length }))
      } else if (e.key === 'ArrowUp') {
        e.preventDefault()
        setAutocomplete(prev => ({ ...prev, index: (prev.index - 1 + filteredSuggestions.length) % filteredSuggestions.length }))
      } else if (e.key === 'Enter' || e.key === 'Tab') {
        e.preventDefault()
        handleAutocompleteSelect(filteredSuggestions[autocomplete.index])
      } else if (e.key === 'Escape') {
        setAutocomplete(prev => ({ ...prev, active: false }))
      }
    } else if (e.key === 'Enter' && !e.shiftKey) {
      e.preventDefault()
      handleSendPrompt()
    }
  }

  const handleSendPrompt = async () => {
    const input = chatInput.trim()
    if (!input) return

    try {
      if (input === '/new' && onNewSession) {
        onNewSession()
        setChatInput('')
        return
      }

      // If session is read-only (completed/failed/cancelled), sending a message should effectively "reactivate" it
      // In Squads, this currently means the backend will try to ensure it's running before sending the message
      // and we rely on the backend to handle the state transition or error if it's truly locked.

        if (input.startsWith('/')) {
          const parts = input.split(' ')
          const command = parts[0]
          const args = parts.slice(1).join(' ')
          await executeCommand.mutateAsync({
            session_id: session.id,
            command,
            arguments: args || undefined,
            agent: mode,
            model: session.model,
          })
        } else if (input.startsWith('!')) {
          const command = input.slice(1).trim()
          await runShell.mutateAsync({
            session_id: session.id,
            command,
            agent: mode,
            model: session.model,
          })
        } else {
        await sendPrompt.mutateAsync({
          session_id: session.id,
          prompt: input,
          agent: mode, // Send with current mode
        })
      }
      setChatInput('')
    } catch (error) {
      console.error('SessionChat action failed', {
        input,
        sessionId: session.id,
        error,
      })
      addNotification({
        type: 'error',
        title: 'Action Failed',
        message: error instanceof Error ? error.message : 'Failed to process message',
      })
    }
  }

  const isActive = (['running', 'pending', 'paused', 'starting'] as string[]).includes(session.status)
  const isHistory = (['completed', 'failed', 'cancelled'] as string[]).includes(session.status)
  const isPending = sendPrompt.isPending || executeCommand.isPending || runShell.isPending

  return (
    <div className={cn('flex flex-col h-full', className)}>
      {/* Header */}
      {showHeader && (
        <div className="p-2 border-b border-tui-border bg-tui-dim/10 flex items-center justify-between shrink-0">
          <div className="flex items-center gap-2 text-xs font-bold">
            <Terminal size={14} />
            {headerContent || 'SESSION_CHAT'}
          </div>
          <div className="flex items-center gap-2 text-[10px] font-bold uppercase">
            <span
              className={cn(
                'px-2 py-0.5 border',
                isActive ? 'border-ctp-green/30 text-ctp-green' : isHistory ? 'border-tui-dim/30 text-tui-dim' : 'border-tui-accent/30 text-tui-accent'
              )}
            >
              {isActive ? 'LIVE' : isHistory ? 'HISTORY' : session.status}
            </span>
            <span className="text-tui-dim hidden sm:inline font-mono">
              session/{session.id.slice(0, 8)}
            </span>
          </div>
        </div>
      )}

      {/* Messages */}
      <div 
        ref={messagesContainerRef}
        className="flex-1 overflow-y-auto p-3 md:p-4 bg-black/40 space-y-3 relative"
      >
        {isLoadingMessages ? (
          <div className="flex items-center justify-center text-tui-dim text-xs uppercase tracking-widest">
            Loading chat...
          </div>
        ) : sessionMessages.length === 0 ? (
          <div className="text-center text-tui-dim text-xs italic">
            No messages yet. Send the first prompt to get started.
          </div>
        ) : (
          sessionMessages.map((message, index) => (
            <ChatMessage
              key={message.info?.id ?? `${message.info?.role || 'msg'}-${index}`}
              message={message}
            />
          ))
        )}
        <div ref={messagesEndRef} />
        {isHistory && !sessionMessages.length && (
          <div className="absolute inset-0 flex flex-col items-center justify-center p-4 bg-tui-bg/80 backdrop-blur-sm z-10 pointer-events-none">
            <div className="text-tui-dim text-xs uppercase tracking-widest mb-4">No active session</div>
            {/* Start New Session button removed in favor of command/sidebar controls */}
          </div>
        )}
      </div>

      {/* Composer */}
      <div className="border-t border-tui-border p-3 md:p-4 bg-tui-bg/60 shrink-0 relative">
        <div className="flex flex-col gap-2">
          {/* Autocomplete Menu */}
          {autocomplete.active && filteredSuggestions.length > 0 && (
            <div 
              ref={autocompleteRef}
              style={{ left: autocomplete.position.left }}
              className="absolute bottom-full mb-1 w-64 max-h-[40vh] overflow-y-auto bg-tui-bg border border-tui-accent/40 shadow-xl z-50 font-mono text-xs"
            >
              <div className="p-1 border-b border-tui-border bg-tui-dim/10 text-[9px] uppercase tracking-widest text-tui-dim flex justify-between items-center">
                <span>Suggestions for {autocomplete.trigger}{autocomplete.query}</span>
                <span>{filteredSuggestions.length} found</span>
              </div>
              {filteredSuggestions.map((suggestion, idx) => (
                <button
                  key={suggestion.id}
                  onClick={() => handleAutocompleteSelect(suggestion)}
                  className={cn(
                    "w-full text-left px-3 py-2 flex flex-col gap-0.5 border-b border-tui-border/30 last:border-0",
                    autocomplete.index === idx ? "bg-tui-accent text-tui-bg" : "hover:bg-tui-accent/10"
                  )}
                >
                  <div className="flex items-center gap-2 font-bold">
                    {autocomplete.trigger === '/' ? <Command size={10} /> : <FileText size={10} />}
                    {suggestion.id}
                  </div>
                  {suggestion.description && (
                    <div className={cn(
                      "text-[10px] uppercase opacity-70",
                      autocomplete.index === idx ? "text-tui-bg" : "text-tui-dim"
                    )}>
                      {suggestion.description}
                    </div>
                  )}
                </button>
              ))}
            </div>
          )}

          <textarea
            ref={textareaRef}
            value={chatInput}
            onChange={handleChatInputChange}
            onKeyDown={handleKeyDown}
            placeholder={isHistory ? "Type to reactivate session..." : "Type a message..."}
            className="w-full min-h-[80px] bg-black/40 border border-tui-border p-3 text-sm focus:border-tui-accent outline-none font-mono resize-none"
          />
          <div className="flex items-center justify-between">
            <div className="flex items-center gap-3">
              {showModeToggle && (
                <ModeToggle mode={mode} onChange={onModeChange} />
              )}
              {isHistory && (
                <div className="text-[10px] text-tui-accent uppercase font-bold flex items-center gap-1">
                  <RefreshCw size={10} />
                  Resumption_Enabled
                </div>
              )}
              <span className="text-[10px] text-tui-dim uppercase hidden sm:inline">
                Enter to send - Shift+Enter for newline
              </span>
            </div>
            <button
              onClick={handleSendPrompt}
              disabled={isPending || !chatInput.trim()}
              className="bg-tui-text text-tui-bg px-4 py-2 text-xs font-bold uppercase tracking-widest flex items-center gap-2 hover:bg-white transition-colors disabled:opacity-50"
            >
              {isPending ? (
                <Loader2 size={14} className="animate-spin" />
              ) : (
                <Send size={14} />
              )}
              Send
            </button>
          </div>
        </div>
      </div>
    </div>
  )
}

// Mode toggle component
interface ModeToggleProps {
  mode: AgentMode
  onChange?: (mode: AgentMode) => void
}

function ModeToggle({ mode, onChange }: ModeToggleProps) {
  return (
    <div className="flex items-center border border-tui-border rounded-sm overflow-hidden">
      <button
        onClick={() => onChange?.('plan')}
        className={cn(
          'px-3 py-1 text-[10px] font-bold uppercase tracking-widest transition-colors',
          mode === 'plan'
            ? 'bg-tui-accent text-tui-bg'
            : 'bg-tui-bg text-tui-dim hover:text-tui-text'
        )}
      >
        Plan
      </button>
      <button
        onClick={() => onChange?.('build')}
        className={cn(
          'px-3 py-1 text-[10px] font-bold uppercase tracking-widest transition-colors',
          mode === 'build'
            ? 'bg-tui-accent text-tui-bg'
            : 'bg-tui-bg text-tui-dim hover:text-tui-text'
        )}
      >
        Build
      </button>
    </div>
  )
}

// Export for use in agent detail page
export { ModeToggle }

// ============================================================================
// Chat Message Component
// ============================================================================

export function ChatMessage({ message }: { message: SessionMessageEntry }) {
  const role = getMessageRole(message.info)
  const parts = normalizeMessageParts(message.parts)
  const timestamp = formatMessageTime(message.info)
  const isUser = role === 'user' || role === 'human' || role === 'client'
  const isSystem = role === 'system' || role === 'tool'

  // Combine token info from message info or step-finish part
  const tokens = message.info.tokens || parts.stepFinishTokens
  const cost = message.info.cost ?? parts.stepFinishCost
  const modelLabel = getMessageModelLabel(message.info)
  const modeLabel = message.info.mode || message.info.agent

  return (
    <div className={`flex flex-col gap-1 ${isUser ? 'items-end' : 'items-start'}`}>
      <div
        className={`max-w-[95%] lg:max-w-[90%] border rounded-sm px-3 py-3 md:px-4 md:py-4 text-xs md:text-sm leading-relaxed shadow-sm ${
          isUser
            ? 'bg-tui-accent/10 border-tui-accent/30 text-tui-text'
            : isSystem
            ? 'bg-tui-dim/5 border-tui-border/40 text-tui-dim'
            : 'bg-tui-bg border-tui-border text-tui-text'
        }`}
      >
        {/* Header: Role, Time, Model, Mode */}
        <div className="flex flex-wrap items-center justify-between gap-3 text-[10px] uppercase tracking-widest text-tui-dim mb-3 border-b border-tui-border/30 pb-2">
          <div className="flex items-center gap-2">
            <span className={`font-bold ${isUser ? 'text-tui-accent' : 'text-tui-text'}`}>
              {role}
            </span>
            {modeLabel && !isUser && (
              <span
                className={cn(
                  'px-1.5 py-0.5 border rounded-sm text-[9px]',
                  modeLabel === 'plan'
                    ? 'border-blue-500/30 text-blue-400'
                    : modeLabel === 'build'
                    ? 'border-green-500/30 text-green-400'
                    : 'border-tui-border text-tui-dim'
                )}
              >
                {modeLabel}
              </span>
            )}
            {timestamp && <span className="opacity-70">{timestamp}</span>}
          </div>
          {modelLabel && !isUser && <div className="opacity-70 font-mono">{modelLabel}</div>}
        </div>

        {/* Error Display */}
        {message.info.error && (
          <div className="mb-3 p-2 bg-red-950/30 border border-red-900/50 rounded text-red-400 text-xs">
            <div className="font-bold uppercase text-[10px] mb-1">Error</div>
            {formatError(message.info.error)}
          </div>
        )}

        {/* Text Content */}
        {parts.text ? (
          <div className="min-w-0 break-words">
            <MarkdownRenderer content={parts.text} />
          </div>
        ) : !parts.tools.length &&
          !parts.reasoning.length &&
          !parts.attachments.length &&
          !parts.patches.length ? (
          <div className="text-[10px] text-tui-dim italic flex items-center gap-2">
            <span className="w-1.5 h-1.5 bg-tui-dim/50 rounded-full animate-pulse" />
            <span className="w-1.5 h-1.5 bg-tui-dim/50 rounded-full animate-pulse delay-75" />
            <span className="w-1.5 h-1.5 bg-tui-dim/50 rounded-full animate-pulse delay-150" />
          </div>
        ) : null}

        {/* Reasoning (Collapsible) */}
        {parts.reasoning.length > 0 && (
          <div className="mt-3">
            <details className="group border border-tui-accent/20 bg-tui-accent/5 rounded-sm">
              <summary className="cursor-pointer p-2 text-[10px] uppercase tracking-widest text-tui-accent hover:text-white transition-colors flex items-center justify-between select-none">
                <div className="flex items-center gap-2">
                  <Zap size={12} className="animate-pulse" />
                  <span>Neural_Link / Reasoning_HUD</span>
                </div>
                <div className="flex items-center gap-3">
                  {tokens?.reasoning ? (
                    <span className="opacity-50 font-mono text-[9px]">{tokens.reasoning} TKNS</span>
                  ) : null}
                  <ChevronRight
                    size={12}
                    className="transition-transform group-open:rotate-90 text-tui-dim"
                  />
                </div>
              </summary>
              <div className="p-3 pt-1 text-[11px] text-tui-accent/90 font-mono whitespace-pre-wrap border-t border-tui-accent/10 mt-1 leading-relaxed bg-black/20">
                {parts.reasoning.join('\n\n')}
              </div>
            </details>
          </div>
        )}

        {/* Tools */}
        {parts.tools.length > 0 && (
          <div className="mt-4 space-y-3">
            {parts.tools.map((tool, index) => (
              <ToolPartBlock key={tool.id ?? `${(tool as any).tool}-${index}`} part={tool} />
            ))}
          </div>
        )}

        {/* Attachments */}
        {parts.attachments.length > 0 && (
          <div className="mt-3 space-y-1">
            {parts.attachments.map((file, index) => (
              <FilePartBlock key={index} part={file} />
            ))}
          </div>
        )}

        {/* Patches */}
        {parts.patches.length > 0 && (
          <div className="mt-3 space-y-1">
            {parts.patches.map((patch, index) => (
              <PatchPartBlock key={index} part={patch} />
            ))}
          </div>
        )}

        {/* Meta Lines (Snapshots, etc) */}
        {parts.metaLines.length > 0 && (
          <div className="mt-3 pt-2 border-t border-tui-border/20 space-y-1">
            {parts.metaLines.map((line, index) => (
              <div
                key={index}
                className="text-[9px] uppercase tracking-widest text-tui-dim font-mono"
              >
                {line}
              </div>
            ))}
          </div>
        )}

        {/* Footer: Tokens & Cost */}
        {(tokens || cost != null) && !isUser && (
          <div className="mt-3 pt-2 border-t border-tui-border/30 flex flex-wrap gap-3 text-[9px] uppercase tracking-widest text-tui-dim opacity-80">
            {tokens && (
              <div className="flex gap-2">
                <span title="Input Tokens">IN {tokens.input}</span>
                <span title="Output Tokens">OUT {tokens.output}</span>
                {tokens.cache && (
                  <span title="Cache Read/Write">
                    CACHE {tokens.cache.read}/{tokens.cache.write}
                  </span>
                )}
              </div>
            )}
            {cost != null && (
              <div className="ml-auto font-mono text-tui-accent/80">${formatCost(cost)}</div>
            )}
          </div>
        )}
      </div>
    </div>
  )
}

// ============================================================================
// Helper Components
// ============================================================================

function MarkdownRenderer({ content }: { content: string }) {
  return (
    <div className="prose prose-invert prose-sm max-w-none break-words">
      <ReactMarkdown
        remarkPlugins={[remarkGfm]}
        components={{
          code(props) {
          const { children, className, ...rest } = props
          const match = /language-(\w+)/.exec(className || '')
          return match ? (
            <SyntaxHighlighter
              style={vscDarkPlus}
              language={match[1]}
              PreTag="div"
              customStyle={{
                margin: '0.5rem 0',
                borderRadius: '0.25rem',
                fontSize: '0.75rem',
              }}
            >
              {String(children).replace(/\n$/, '')}
            </SyntaxHighlighter>
          ) : (
            <code className={cn("bg-tui-dim/20 px-1 rounded text-tui-accent font-mono", className)} {...rest}>
              {children}
            </code>
          )
        },
        pre({ children }) {
          return <>{children}</>
        },
        a({ href, children }) {
          return (
            <a
              href={href}
              target="_blank"
              rel="noopener noreferrer"
              className="text-tui-accent underline hover:no-underline"
            >
              {children}
            </a>
          )
        },
        ul({ children }) {
          return <ul className="list-disc list-inside space-y-1 my-2">{children}</ul>
        },
        ol({ children }) {
          return <ol className="list-decimal list-inside space-y-1 my-2">{children}</ol>
        },
        p({ children }) {
          return <p className="my-2">{children}</p>
        },
        h1({ children }) {
          return <h1 className="text-lg font-bold mt-4 mb-2">{children}</h1>
        },
        h2({ children }) {
          return <h2 className="text-base font-bold mt-3 mb-2">{children}</h2>
        },
        h3({ children }) {
          return <h3 className="text-sm font-bold mt-2 mb-1">{children}</h3>
        },
        blockquote({ children }) {
          return (
            <blockquote className="border-l-2 border-tui-accent pl-3 my-2 text-tui-dim italic">
              {children}
            </blockquote>
          )
        },
      }}
      >
        {content}
      </ReactMarkdown>
    </div>
  )
}

function ToolPartBlock({ part }: { part: SessionMessagePart }) {
  if (part.type !== 'tool') return null
  const toolPart = part as SessionMessageToolPart
  const toolName = toolPart.tool
  const status = toolPart.state?.status || 'unknown'
  const title = toolPart.state?.title || toolName || 'tool'
  const input = toolPart.state?.input
  const output = toolPart.state?.output
  const error = toolPart.state?.error

  const isError = status === 'error' || !!error
  const isDone = status === 'success' || status === 'done' || !!output

  return (
    <div
      className={`border rounded-sm overflow-hidden text-xs ${
        isError ? 'border-red-900/50 bg-red-950/10' : 'border-tui-border/60 bg-black/20'
      }`}
    >
      <div className="px-3 py-2 bg-tui-dim/10 border-b border-tui-border/30 flex items-center justify-between">
        <div className="flex items-center gap-2 font-mono text-tui-accent">
          <Terminal size={12} />
          <span className="font-bold">{title}</span>
        </div>
        <span
          className={`text-[9px] uppercase tracking-widest px-1.5 py-0.5 rounded border ${
            isError
              ? 'border-red-500/30 text-red-400'
              : isDone
              ? 'border-green-500/30 text-green-400'
              : 'border-tui-dim/30 text-tui-dim'
          }`}
        >
          {status}
        </span>
      </div>

      <div className="p-3 space-y-3 font-mono">
        {input && (
          <div>
            <div className="text-[9px] uppercase tracking-widest text-tui-dim mb-1">Input</div>
            <div className="bg-black/40 p-2 rounded border border-tui-border/30 overflow-x-auto">
              <pre>{formatJSON(input)}</pre>
            </div>
          </div>
        )}
        {output && (
          <div>
            <div className="text-[9px] uppercase tracking-widest text-tui-dim mb-1">Output</div>
            <div className="bg-black/40 p-2 rounded border border-tui-border/30 overflow-x-auto text-tui-text/90">
              <pre>{output}</pre>
            </div>
          </div>
        )}
        {error && (
          <div>
            <div className="text-[9px] uppercase tracking-widest text-red-400 mb-1">Error</div>
            <div className="bg-red-950/20 p-2 rounded border border-red-900/30 overflow-x-auto text-red-300">
              <pre>{error}</pre>
            </div>
          </div>
        )}
      </div>
    </div>
  )
}

function FilePartBlock({ part }: { part: SessionMessagePart }) {
  const file = part as { filename?: string; url?: string; mime?: string }
  return (
    <div className="flex items-center gap-2 p-2 border border-tui-border/40 bg-tui-dim/5 rounded text-xs text-tui-dim font-mono">
      <Archive size={12} />
      <span className="text-tui-text">{file.filename || file.url || 'attachment'}</span>
      {file.mime && <span className="text-[9px] opacity-60">({file.mime})</span>}
    </div>
  )
}

function PatchPartBlock({ part }: { part: SessionMessagePart }) {
  const patch = part as { hash?: string; files?: string[] }
  return (
    <div className="flex flex-col gap-1 p-2 border border-tui-border/40 bg-tui-dim/5 rounded text-xs font-mono">
      <div className="flex items-center gap-2 text-tui-accent">
        <Pencil size={12} />
        <span>Applied Patch</span>
        {patch.hash && <span className="text-tui-dim">{patch.hash.slice(0, 7)}</span>}
      </div>
      {patch.files && patch.files.length > 0 && (
        <div className="pl-5 text-tui-dim">
          {patch.files.map((f) => (
            <div key={f}>{f}</div>
          ))}
        </div>
      )}
    </div>
  )
}

// ============================================================================
// Helper Functions
// ============================================================================

function getMessageRole(info?: SessionMessageInfo) {
  const role = info?.role || 'assistant'
  return typeof role === 'string' ? role.toLowerCase() : 'assistant'
}

function normalizeMessageParts(parts: SessionMessagePart[] | undefined) {
  const textParts: string[] = []
  const reasoningParts: string[] = []
  const tools: SessionMessagePart[] = []
  const attachments: SessionMessagePart[] = []
  const patches: SessionMessagePart[] = []
  const metaLines: string[] = []
  let stepFinishTokens: SessionMessageInfo['tokens']
  let stepFinishCost: number | undefined

  if (!Array.isArray(parts)) {
    return {
      text: '',
      reasoning: [],
      tools: [],
      attachments: [],
      patches: [],
      metaLines: [],
      stepFinishTokens,
      stepFinishCost,
    }
  }

  parts.forEach((part) => {
    switch (part.type) {
      case 'text': {
        const textPart = part as { text?: string; ignored?: boolean; synthetic?: boolean }
        if (textPart.ignored) return
        if (textPart.synthetic) return
        if (typeof textPart.text === 'string') {
          textParts.push(textPart.text)
        }
        return
      }
      case 'reasoning': {
        const reasoningPart = part as { text?: string }
        if (typeof reasoningPart.text === 'string') {
          reasoningParts.push(reasoningPart.text)
        }
        return
      }
      case 'tool':
        tools.push(part)
        return
      case 'file':
        attachments.push(part)
        return
      case 'patch':
        patches.push(part)
        return
      case 'step-finish': {
        const stepPart = part as { tokens?: SessionMessageInfo['tokens']; cost?: number }
        stepFinishTokens = stepPart.tokens
        stepFinishCost = stepPart.cost
        return
      }
      case 'step-start':
        return
      case 'snapshot': {
        const snapshotPart = part as { snapshot?: string }
        metaLines.push(`SNAPSHOT ${snapshotPart.snapshot || ''}`.trim())
        return
      }
      case 'compaction': {
        const compactionPart = part as { auto?: boolean }
        metaLines.push(`COMPACTION ${compactionPart.auto ? 'AUTO' : 'MANUAL'}`)
        return
      }
      case 'agent': {
        const agentPart = part as { name?: string }
        metaLines.push(`AGENT ${agentPart.name || ''}`.trim())
        return
      }
      case 'retry': {
        const retryPart = part as { attempt?: number; error?: { message?: string } | string }
        const errorText = retryPart.error ? formatError(retryPart.error) : ''
        metaLines.push(`RETRY ${retryPart.attempt ?? ''} ${errorText}`.trim())
        return
      }
      case 'subtask': {
        const subtaskPart = part as { description?: string; agent?: string }
        const description = subtaskPart.description || 'subtask'
        metaLines.push(`SUBTASK ${description}${subtaskPart.agent ? ` - ${subtaskPart.agent}` : ''}`)
        return
      }
      default:
        return
    }
  })

  return {
    text: textParts.join('\n'),
    reasoning: reasoningParts,
    tools,
    attachments,
    patches,
    metaLines,
    stepFinishTokens,
    stepFinishCost,
  }
}

function formatMessageTime(info?: SessionMessageInfo) {
  const created = info?.time?.created
  if (!created) return ''
  const timestamp = created > 10_000_000_000 ? created : created * 1000
  const date = new Date(timestamp)
  if (Number.isNaN(date.getTime())) return ''
  return date.toLocaleTimeString()
}

function formatCost(cost: number) {
  if (!Number.isFinite(cost)) return `${cost}`
  return cost < 1 ? cost.toFixed(4) : cost.toFixed(2)
}

function getMessageModelLabel(info?: SessionMessageInfo) {
  if (!info) return ''
  if (info.providerID && info.modelID) return `${info.providerID}/${info.modelID}`
  if (typeof info.model === 'string') return info.model
  if (info.model && typeof info.model === 'object') {
    const provider = info.model.providerID
    const model = info.model.modelID
    if (provider && model) return `${provider}/${model}`
  }
  return ''
}

function formatError(error: SessionMessageInfo['error'] | { message?: string } | string) {
  if (!error) return ''
  if (typeof error === 'string') return error
  if (typeof error === 'object') {
    return (error as { message?: string; type?: string }).message || (error as { type?: string }).type || 'error'
  }
  return 'error'
}

function formatJSON(value: Record<string, unknown>) {
  try {
    return JSON.stringify(value, null, 2)
  } catch {
    return String(value)
  }
}
