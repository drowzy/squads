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
  RefreshCw,
  StopCircle,
  FileDiff
} from 'lucide-react'
import {
  useSessionMessages,
  useSendSessionPrompt,
  useExecuteSessionCommand,
  useRunSessionShell,
  useAbortSession,
  useProjectFiles,
  type Session,
  type SessionMessageEntry,
  type SessionMessagePart,
  type SessionMessageToolPart,
  type SessionMessageInfo,
  type SessionDiffEntry,
} from '../api/queries'
import { API_BASE } from '../api/client'
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
  /** Callback when user wants to view diffs from a message */
  onViewDiff?: (diffs: SessionDiffEntry[]) => void
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
  onViewDiff,
}: SessionChatProps) {
  const [chatInput, setChatInput] = useState('')
  const [awaitingResponse, setAwaitingResponse] = useState(false)
  const [isStreaming, setIsStreaming] = useState(false)
  const eventSourceRef = useRef<EventSource | null>(null)
  const streamUserMessageIdRef = useRef<string | null>(null)
  const streamAssistantMessageIdRef = useRef<string | null>(null)
  const pendingSinceRef = useRef<number | null>(null)
  const localUserMessageQueueRef = useRef<string[]>([])
  const scrollRafRef = useRef<number | null>(null)
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
  const abortSession = useAbortSession()
  const { addNotification } = useNotifications()

  const queryClient = useQueryClient()

  const messagesLimit = 100
  const messagesQueryKey = ['sessions', session.id, 'messages', messagesLimit] as const

  const updateMessagesCache = (updater: (prev: SessionMessageEntry[]) => SessionMessageEntry[]) => {
    if (!session.id) return

    queryClient.setQueryData(messagesQueryKey, (prev) => {
      const prevList = Array.isArray(prev) ? prev : []
      return updater(prevList)
    })
  }

  const upsertMessage = (info: any) => {
    if (!info || typeof info !== 'object' || typeof info.id !== 'string') return

    updateMessagesCache((prev) => {
      const existingIndex = prev.findIndex((m) => m?.info?.id === info.id)

      if (existingIndex >= 0) {
        const existing = prev[existingIndex]
        const merged: SessionMessageEntry = {
          ...existing,
          info: { ...(existing.info as any), ...(info as any) },
        }

        if (merged === existing) return prev

        const next = prev.slice()
        next[existingIndex] = merged
        return next
      }

      return [...prev, { info: info as any, parts: [] }]
    })
  }

  const appendTextToMessage = (messageId: string, delta: string | null, fullText: string | null) => {
    if (!messageId) return

    updateMessagesCache((prev) => {
      const idx = prev.findIndex((m) => m?.info?.id === messageId)
      const createdAt = Date.now()

      const existing =
        idx >= 0
          ? prev[idx]
          : ({
              info: { id: messageId, role: 'assistant', time: { created: createdAt } } as any,
              parts: [],
            } as SessionMessageEntry)

      const parts = Array.isArray(existing.parts) ? existing.parts.slice() : []
      const textPartIndex = parts.findIndex((p: any) => p?.type === 'text')
      const prevText = textPartIndex >= 0 && typeof (parts[textPartIndex] as any).text === 'string' ? (parts[textPartIndex] as any).text : ''

      let nextText = prevText
      if (typeof delta === 'string' && delta.length) {
        nextText = prevText + delta
      } else if (typeof fullText === 'string') {
        nextText = fullText.length > prevText.length ? fullText : prevText
      }

      if (nextText === prevText) return prev

      const nextTextPart = { ...(textPartIndex >= 0 ? (parts[textPartIndex] as any) : {}), type: 'text', text: nextText }

      if (textPartIndex >= 0) {
        parts[textPartIndex] = nextTextPart as any
      } else {
        parts.push(nextTextPart as any)
      }

      const nextMessage: SessionMessageEntry = { ...existing, parts }

      if (idx >= 0) {
        const next = prev.slice()
        next[idx] = nextMessage
        return next
      }

      return [...prev, nextMessage]
    })

    scrollToBottomSoon()
  }

  const upsertPartToMessage = (messageId: string, part: any) => {
    if (!messageId || !part) return

    updateMessagesCache((prev) => {
      const idx = prev.findIndex((m) => m?.info?.id === messageId)
      const createdAt = Date.now()

      const existing =
        idx >= 0
          ? prev[idx]
          : ({
              info: { id: messageId, role: 'assistant', time: { created: createdAt } } as any,
              parts: [],
            } as SessionMessageEntry)

      const parts = Array.isArray(existing.parts) ? existing.parts.slice() : []
      const partId = typeof part.id === 'string' ? part.id : null
      const partType = typeof part.type === 'string' ? part.type : null

      let partIndex = -1
      if (partId) {
        partIndex = parts.findIndex((p: any) => p?.id === partId)
      } else if (partType) {
        partIndex = parts.findIndex((p: any) => p?.type === partType)
      }

      if (partIndex >= 0) {
        parts[partIndex] = { ...(parts[partIndex] as any), ...(part as any) }
      } else {
        parts.push(part as any)
      }

      const nextMessage: SessionMessageEntry = { ...existing, parts }

      if (idx >= 0) {
        const next = prev.slice()
        next[idx] = nextMessage
        return next
      }

      return [...prev, nextMessage]
    })

    scrollToBottomSoon()
  }

  const scrollToBottomSoon = () => {
    if (scrollRafRef.current != null) return

    scrollRafRef.current = window.requestAnimationFrame(() => {
      scrollRafRef.current = null
      messagesEndRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' })
    })
  }

  // Subscribe to real-time events for this project
  useProjectEvents({
    projectId: session.project_id,
    onEvent: (event) => {
      const kind = normalizeEventKind(event.kind)

      if (kind === 'session:status_changed' && event.session_id === session.id) {
        if (import.meta.env.DEV) {
          console.log('Session status changed, invalidating session query')
        }
        queryClient.invalidateQueries({ queryKey: ['sessions', session.id] })
      }
    }
  })

  useEffect(() => {
    if (!session.id) return

    const eventSource = new EventSource(`${API_BASE}/sessions/${session.id}/stream`)
    eventSourceRef.current = eventSource

    const handleOpenCodeEvent = (eventType: string, rawText: string) => {
      let data: any
      try {
        data = JSON.parse(rawText)
      } catch {
        return
      }

      if (eventType === 'message.updated') {
        const info = data?.properties?.info

        if (info?.role === 'user' && typeof info?.id === 'string') {
          streamUserMessageIdRef.current = info.id

          const localUserId = localUserMessageQueueRef.current.shift()

          if (localUserId) {
            updateMessagesCache((prev) => {
              const localIdx = prev.findIndex((m) => m?.info?.id === localUserId)
              if (localIdx < 0) return prev

              const next = prev.slice()
              const existing = next[localIdx]
              next[localIdx] = { ...existing, info: { ...(existing.info as any), ...(info as any) } }

              return next.filter((m, idx) => idx === localIdx || m?.info?.id !== info.id)
            })
          } else {
            upsertMessage(info)
          }

          scrollToBottomSoon()
        }

        if (info?.role === 'assistant' && typeof info?.id === 'string') {
          streamAssistantMessageIdRef.current = info.id
          upsertMessage(info)
          scrollToBottomSoon()

          if (typeof info?.time?.completed === 'number') {
            setIsStreaming(false)
            setAwaitingResponse(false)
            pendingSinceRef.current = null
          }
        }

        if (info && info.role !== 'user' && info.role !== 'assistant') {
          upsertMessage(info)
        }
      }

      if (eventType === 'message.part.updated') {
        const part = data?.properties?.part
        const delta = typeof data?.properties?.delta === 'string' ? data.properties.delta : null

        if (part) {
          const messageId = typeof part.messageID === 'string' ? part.messageID : null
          const userMessageId = streamUserMessageIdRef.current
          const assistantMessageId = streamAssistantMessageIdRef.current

          const isAssistantPart =
            (assistantMessageId && messageId === assistantMessageId) ||
            (userMessageId && messageId && messageId !== userMessageId)

          if (isAssistantPart) {
            setIsStreaming(true)
          }

          if (messageId) {
            if (part.type === 'text') {
              appendTextToMessage(messageId, delta, typeof part.text === 'string' ? part.text : null)
            } else {
              upsertPartToMessage(messageId, part)
            }
          }
        }
      }

      if (eventType === 'tui.prompt.append' && typeof data?.properties?.text === 'string') {
        const assistantMessageId = streamAssistantMessageIdRef.current

        if (assistantMessageId) {
          setIsStreaming(true)
          appendTextToMessage(assistantMessageId, data.properties.text, null)
        }
      }

      const statusType = data?.properties?.status?.type
      if (eventType === 'session.idle' || (eventType === 'session.status' && statusType === 'idle')) {
        if (pendingSinceRef.current != null) {
          setIsStreaming(false)
          setAwaitingResponse(false)
          pendingSinceRef.current = null
          streamUserMessageIdRef.current = null
          streamAssistantMessageIdRef.current = null
        }
      }
    }

    const bind = (eventType: string) => {
      const handler = (event: MessageEvent) => {
        handleOpenCodeEvent(eventType, event.data)
      }
      eventSource.addEventListener(eventType, handler)
      return handler
    }

    const handlers = {
      'message.updated': bind('message.updated'),
      'message.part.updated': bind('message.part.updated'),
      'tui.prompt.append': bind('tui.prompt.append'),
      'session.status': bind('session.status'),
      'session.idle': bind('session.idle'),
    }

    eventSource.onerror = (err) => {
      if (import.meta.env.DEV) {
        console.error('Session SSE Error:', err)
      }
    }

    return () => {
      for (const [eventType, handler] of Object.entries(handlers)) {
        eventSource.removeEventListener(eventType, handler as any)
      }
      eventSource.close()
      if (eventSourceRef.current === eventSource) {
        eventSourceRef.current = null
      }
    }
  }, [session.id, queryClient])

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
    }
  )

  const messagesContainerRef = useRef<HTMLDivElement | null>(null)

  // Autocomplete logic
  const filteredSuggestions = useMemo(() => {
    if (!autocomplete.active) return []

    if (autocomplete.trigger === '/') {
      return COMMANDS.filter(cmd => cmd.id.startsWith('/' + autocomplete.query))
    }

    if (autocomplete.trigger === '@') {
      const q = autocomplete.query.toLowerCase()
      return projectFiles
        .filter(f => f.toLowerCase().includes(q))
        .slice(0, 10)
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

    setTimeout(() => {
      textareaRef.current?.focus()
      const newPos = beforeMatch.length + suggestion.id.length + 1
      textareaRef.current?.setSelectionRange(newPos, newPos)
    }, 0)
  }

  const handleChatInputChange = (e: React.ChangeEvent<HTMLTextAreaElement>) => {
    const newValue = e.target.value
    setChatInput(newValue)

    const cursorPosition = e.target.selectionStart || 0
    const textBeforeCursor = newValue.substring(0, cursorPosition)

    const lastWordMatch = textBeforeCursor.match(/([/@])(\w*)$/)

    if (lastWordMatch) {
      const trigger = lastWordMatch[1] as '/' | '@'
      const query = lastWordMatch[2] || ''

      const rect = e.target.getBoundingClientRect()
      const containerRect = messagesContainerRef.current?.getBoundingClientRect()

      setAutocomplete({
        active: true,
        trigger,
        query,
        index: 0,
        position: {
          top: rect.top - (containerRect?.top || 0),
          left: 0,
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

  useEffect(() => {
    messagesEndRef.current?.scrollIntoView({ behavior: 'smooth', block: 'end' })
  }, [session.id, sessionMessages.length])


  // Reset chat input and autocomplete when session changes
  useEffect(() => {
    setChatInput('')
    setAutocomplete(prev => ({ ...prev, active: false }))
    setAwaitingResponse(false)
    setIsStreaming(false)

    streamUserMessageIdRef.current = null
    streamAssistantMessageIdRef.current = null
    pendingSinceRef.current = null
    localUserMessageQueueRef.current = []

    if (scrollRafRef.current != null) {
      cancelAnimationFrame(scrollRafRef.current)
      scrollRafRef.current = null
    }
  }, [session.id])

  const handleAbort = async () => {
    streamUserMessageIdRef.current = null
    streamAssistantMessageIdRef.current = null
    pendingSinceRef.current = null
    localUserMessageQueueRef.current = []
    setIsStreaming(false)

    try {
      await abortSession.mutateAsync({ session_id: session.id })
      setAwaitingResponse(false)
      pendingSinceRef.current = null
      addNotification({
        type: 'success',
        title: 'Request Cancelled',
        message: 'The in-flight request has been aborted.'
      })
    } catch (error) {
      addNotification({
        type: 'error',
        title: 'Abort Failed',
        message: error instanceof Error ? error.message : 'Failed to abort request'
      })
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

      // If session is read-only (completed/failed/cancelled/archived), sending a message should effectively "reactivate" it
      // In Squads, this currently means the backend will try to ensure it's running before sending the message
      // and we rely on the backend to handle the state transition or error if it's truly locked.

      const sentAt = Date.now()
      const shouldAwaitResponse = !input.startsWith('/') && !input.startsWith('!')

      if (shouldAwaitResponse) {
        setAwaitingResponse(true)
        pendingSinceRef.current = sentAt
      }

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
        const localId = `local-user-${sentAt}`
        localUserMessageQueueRef.current.push(localId)

        updateMessagesCache((prev) => [
          ...prev,
          {
            info: {
              id: localId,
              role: 'user',
              time: { created: sentAt },
            },
            parts: [{ type: 'text', text: input }],
          } as unknown as SessionMessageEntry,
        ])

        scrollToBottomSoon()

        setIsStreaming(true)
        streamUserMessageIdRef.current = null
        streamAssistantMessageIdRef.current = null

        await sendPrompt.mutateAsync({
          session_id: session.id,
          prompt: input,
          agent: mode,
          model: session.model,
        })
      }

      if (!shouldAwaitResponse) {
        setAwaitingResponse(false)
        pendingSinceRef.current = null
      }
      setChatInput('')
    } catch (error) {
      setIsStreaming(false)
      setAwaitingResponse(false)
      pendingSinceRef.current = null

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
  const isHistory = (['completed', 'failed', 'cancelled', 'archived'] as string[]).includes(session.status)
  const isPending = sendPrompt.isPending || executeCommand.isPending || runShell.isPending
  const isAborting = abortSession.isPending
  const isProcessing = isPending || awaitingResponse || isStreaming
  const messagesToRender = sessionMessages

  return (
    <div className={cn('flex flex-col h-full min-h-0', className)}>
      {/* Header */}
      {showHeader && (
        <div className="p-2 border-b border-tui-border bg-ctp-crust/40 flex items-center justify-between shrink-0">
          <div className="flex items-center gap-2 text-xs font-bold">
            <Terminal size={14} />
            {headerContent || 'SESSION CHAT'}
          </div>
          <div className="flex items-center gap-2 text-xs font-bold">
            <span
              className={cn(
                'px-2 py-0.5 border',
                isActive ? 'border-ctp-green/30 text-ctp-green' : isHistory ? 'border-tui-dim/30 text-tui-dim' : 'border-tui-accent/30 text-tui-accent'
              )}
            >
              {isActive ? 'Live' : isHistory ? 'History' : session.status}
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
        className="flex-1 min-h-0 overflow-y-auto p-3 md:p-4 bg-ctp-crust/60 space-y-3 relative"
      >
        {isLoadingMessages ? (
          <div className="flex items-center justify-center text-tui-dim text-xs uppercase tracking-widest">
            Loading chat...
          </div>
        ) : messagesToRender.length === 0 ? (
          <div className="text-center text-tui-dim text-xs italic">
            No messages yet. Send the first prompt to get started.
          </div>
        ) : (
          messagesToRender.map((message, index) => (
            <ChatMessage
              key={message.info?.id ?? `${message.info?.role || 'msg'}-${index}`}
              message={message}
              onViewDiff={onViewDiff}
            />
          ))
        )}


        <div ref={messagesEndRef} />
        {isHistory && !messagesToRender.length && (
          <div className="absolute inset-0 flex flex-col items-center justify-center p-4 bg-tui-bg/80 backdrop-blur-sm z-10 pointer-events-none">
            <div className="text-tui-dim text-xs uppercase tracking-widest mb-4">No active session</div>
            {/* Start New Session button removed in favor of command/sidebar controls */}
          </div>
        )}
      </div>

      {/* Composer */}
      <div className="border-t border-tui-border p-3 md:p-4 bg-ctp-mantle/40 shrink-0 relative">
        <div className="flex flex-col gap-2">
          {/* Autocomplete Menu */}
          {autocomplete.active && filteredSuggestions.length > 0 && (
            <div 
              ref={autocompleteRef}
              style={{ left: autocomplete.position.left }}
              className="absolute bottom-full mb-1 w-64 max-h-[40vh] overflow-y-auto bg-ctp-mantle border border-tui-accent/40 shadow-xl z-50 font-mono text-xs"
            >
              <div className="p-1 border-b border-tui-border bg-ctp-crust/40 text-[9px] uppercase tracking-tui text-tui-dim flex justify-between items-center">
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
            className="w-full min-h-[80px] bg-ctp-crust border border-tui-border-dim p-3 text-sm focus:border-tui-accent outline-none font-mono resize-none placeholder:text-tui-dim/30"
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
            {isProcessing ? (
              <button
                onClick={handleAbort}
                disabled={isAborting}
                className="bg-red-500/20 text-red-400 border border-red-500/40 px-4 py-2 text-xs font-bold uppercase tracking-widest flex items-center gap-2 hover:bg-red-500/30 transition-colors disabled:opacity-50"
              >
                {isAborting ? (
                  <Loader2 size={14} className="animate-spin" />
                ) : (
                  <StopCircle size={14} />
                )}
                Cancel
              </button>
            ) : (
              <button
                onClick={handleSendPrompt}
                disabled={!chatInput.trim()}
                className="bg-tui-text text-tui-bg px-4 py-2 text-xs font-bold uppercase tracking-widest flex items-center gap-2 hover:bg-white transition-colors disabled:opacity-50"
              >
                <Send size={14} />
                Send
              </button>
            )}
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

export function ChatMessage({ message, onViewDiff }: { message: SessionMessageEntry; onViewDiff?: () => void }) {
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
            <MixedMessageContent content={parts.text} />
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
                  <span>Neural Link / Reasoning HUD</span>
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
              <div className="p-3 pt-1 text-[11px] text-tui-accent/90 font-mono whitespace-pre-wrap border-t border-tui-accent/10 mt-1 leading-relaxed bg-ctp-crust/40">
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

         {/* Diff Pill - for messages with summary diffs */}
         {message.info.summary &&
          typeof message.info.summary === 'object' &&
          'diffs' in message.info.summary &&
          Array.isArray(message.info.summary.diffs) &&
          message.info.summary.diffs.length > 0 && (
           <div className="mt-3">
             <button
               onClick={() => onViewDiff?.()}
               className="flex items-center gap-2 px-3 py-2 bg-tui-accent/10 border border-tui-accent/30 text-tui-accent text-[10px] font-bold uppercase tracking-widest rounded-sm hover:bg-tui-accent/20 transition-colors"
             >
               <FileDiff size={12} />
               <span>View Diff ({(message.info.summary.diffs as SessionDiffEntry[]).length} {(message.info.summary.diffs as SessionDiffEntry[]).length === 1 ? 'file' : 'files'})</span>
             </button>
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

type ArtifactTagKind = 'issue' | 'review'

type ArtifactTagPayload = {
  id?: string
  title?: string
  status?: string
  url?: string
  path?: string
}

type MixedMessagePart =
  | { type: 'text'; text: string }
  | {
      type: 'artifact'
      kind: ArtifactTagKind
      raw: string
      payload?: ArtifactTagPayload
      parseError?: string
    }

function MixedMessageContent({ content }: { content: string }) {
  const parts = useMemo(() => parseMixedMessageContent(content), [content])

  if (parts.length === 1 && parts[0].type === 'text') {
    return <MarkdownRenderer content={parts[0].text} />
  }

  return (
    <div className="space-y-3">
      {parts.map((part, index) => {
        if (part.type === 'text') {
          return part.text.trim() ? <MarkdownRenderer key={`text-${index}`} content={part.text} /> : null
        }

        return (
          <ArtifactTagCard
            key={`artifact-${index}`}
            kind={part.kind}
            raw={part.raw}
            payload={part.payload}
            parseError={part.parseError}
          />
        )
      })}
    </div>
  )
}

function parseMixedMessageContent(content: string): MixedMessagePart[] {
  const parts: MixedMessagePart[] = []
  const tagRegex = new RegExp('<(issue|review)>([\\s\\S]*?)<\\/\\1>', 'g')

  let lastIndex = 0
  let match: RegExpExecArray | null

  while ((match = tagRegex.exec(content)) !== null) {
    const start = match.index
    const end = tagRegex.lastIndex

    if (start > lastIndex) {
      parts.push({ type: 'text', text: content.slice(lastIndex, start) })
    }

    const kind = match[1] as ArtifactTagKind
    const inner = match[2]
    const raw = match[0]

    const { payload, parseError } = parseArtifactPayload(inner)

    parts.push({ type: 'artifact', kind, raw, payload, parseError })
    lastIndex = end
  }

  if (lastIndex < content.length) {
    parts.push({ type: 'text', text: content.slice(lastIndex) })
  }

  return parts.length ? parts : [{ type: 'text', text: content }]
}

function parseArtifactPayload(inner: string): { payload?: ArtifactTagPayload; parseError?: string } {
  const trimmed = inner.trim()

  if (!trimmed) {
    return { parseError: 'Empty tag payload' }
  }

  try {
    const parsed = JSON.parse(trimmed)

    if (parsed && typeof parsed === 'object') {
      return { payload: parsed as ArtifactTagPayload }
    }

    return { parseError: 'Tag payload is not an object' }
  } catch (error) {
    return {
      parseError: error instanceof Error ? error.message : 'Invalid JSON',
    }
  }
}

function ArtifactTagCard({
  kind,
  raw,
  payload,
  parseError,
}: {
  kind: ArtifactTagKind
  raw: string
  payload?: ArtifactTagPayload
  parseError?: string
}) {
  const title = payload?.title || payload?.id || (kind === 'issue' ? 'Issue' : 'Review')
  const status = payload?.status
  const url = payload?.url

  return (
    <div className="border border-tui-border bg-ctp-mantle/40 p-3 rounded-sm">
      <div className="flex items-center justify-between gap-3 mb-2">
        <div className="text-[10px] uppercase tracking-widest text-tui-dim font-bold">
          {kind === 'issue' ? 'Issue' : 'Review'} Artifact
        </div>
        {status ? (
          <div className="text-[10px] font-mono px-2 py-0.5 border border-tui-border/40 text-tui-dim">
            {status}
          </div>
        ) : null}
      </div>
      <div className="flex items-center justify-between gap-3">
        <div className="font-bold text-xs text-tui-text truncate">{title}</div>
        {url ? (
          <a
            href={url}
            className="text-[10px] uppercase font-bold tracking-widest text-tui-accent border border-tui-accent/30 px-2 py-1 hover:bg-tui-accent hover:text-tui-bg transition-colors shrink-0"
          >
            Open
          </a>
        ) : null}
      </div>
      {parseError ? (
        <details className="mt-2 border border-red-900/40 bg-red-950/20 rounded-sm">
          <summary className="cursor-pointer p-2 text-[10px] uppercase tracking-widest text-red-400 select-none">
            Invalid {kind} tag payload
          </summary>
          <pre className="p-2 text-[10px] text-red-200/80 whitespace-pre-wrap">{raw}</pre>
        </details>
      ) : null}
    </div>
  )
}

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

type TaskToolSummaryStep = {
  id: string
  tool: string
  status: string
  title?: string
}

function isPlainObject(value: unknown): value is Record<string, unknown> {
  return !!value && typeof value === 'object' && !Array.isArray(value)
}

function parseTaskToolMetadata(metadata: unknown): { childSessionId?: string; steps: TaskToolSummaryStep[] } {
  if (!isPlainObject(metadata)) return { steps: [] }

  const sessionIdCandidates = [metadata['sessionId'], metadata['sessionID'], metadata['session_id']]
  const childSessionId = sessionIdCandidates.find(
    (value) => typeof value === 'string' && value.length > 0
  ) as string | undefined

  const summaryRaw = metadata['summary']
  if (!Array.isArray(summaryRaw)) return { childSessionId, steps: [] }

  const steps: TaskToolSummaryStep[] = []

  summaryRaw.forEach((entry, index) => {
    if (!isPlainObject(entry)) return

    const tool = typeof entry['tool'] === 'string' && entry['tool'].length > 0 ? entry['tool'] : 'tool'
    const id = typeof entry['id'] === 'string' && entry['id'].length > 0 ? entry['id'] : `${tool}-${index}`

    const state = entry['state']
    const stateObject = isPlainObject(state) ? state : undefined
    const status = typeof stateObject?.['status'] === 'string' ? stateObject['status'] : 'unknown'
    const title = typeof stateObject?.['title'] === 'string' ? stateObject['title'] : undefined

    steps.push({ id, tool, status, title })
  })

  return { childSessionId, steps }
}

function getToolStatusBadgeClass(status: string) {
  switch (status) {
    case 'error':
      return 'border-red-500/30 text-red-400'
    case 'completed':
      return 'border-green-500/30 text-green-400'
    case 'running':
      return 'border-tui-accent/30 text-tui-accent'
    case 'pending':
      return 'border-tui-dim/30 text-tui-dim'
    default:
      return 'border-tui-border/40 text-tui-dim'
  }
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
  const metadata = toolPart.state?.metadata

  const { childSessionId, steps: taskSummarySteps } = useMemo(
    () => parseTaskToolMetadata(metadata),
    [metadata]
  )

  const [showAllTaskSteps, setShowAllTaskSteps] = useState(false)

  const inputFilePath = getToolInputFilePath(input)
  const outputLanguage = inferLanguageFromFilePath(inputFilePath)
  const outputSegments = useMemo(() => {
    if (typeof output !== 'string' || output.length === 0) return []
    return splitToolOutput(output)
  }, [output])

  const isError = status === 'error' || !!error
  const isDone = status === 'completed' || status === 'success' || status === 'done' || !!output

  const isTaskTool = toolName === 'task'
  const hasTaskProgress = isTaskTool && (taskSummarySteps.length > 0 || !!childSessionId)
  const totalSteps = taskSummarySteps.length
  const completedSteps = taskSummarySteps.filter((s) => s.status === 'completed').length
  const errorSteps = taskSummarySteps.filter((s) => s.status === 'error').length
  const runningStep = taskSummarySteps.find((s) => s.status === 'running')
  const pendingStep = taskSummarySteps.find((s) => s.status === 'pending')
  const headlineStep = runningStep || pendingStep
  const canToggleAllSteps = taskSummarySteps.length > 5
  const visibleSteps = showAllTaskSteps ? taskSummarySteps : taskSummarySteps.slice(-5)
  const hiddenStepCount = Math.max(0, taskSummarySteps.length - visibleSteps.length)

  return (
    <div
      className={`border rounded-sm overflow-hidden text-xs ${
        isError ? 'border-red-900/50 bg-red-950/10' : 'border-tui-border-dim bg-ctp-crust/40'
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
        {hasTaskProgress && (
          <div className="rounded border border-tui-border/40 bg-tui-dim/5 p-2 space-y-1">
            <div className="flex items-center justify-between gap-2">
              <div className="text-[9px] uppercase tracking-widest text-tui-dim">Subagent</div>
              {childSessionId ? (
                <div className="text-[9px] text-tui-dim/70 font-mono">session/{childSessionId.slice(0, 8)}</div>
              ) : (
                <div className="text-[9px] text-tui-dim/70 font-mono">starting…</div>
              )}
            </div>

            <div className="flex items-center justify-between gap-2">
              <div className="min-w-0 text-[10px] text-tui-text/90 truncate">
                {headlineStep ? headlineStep.title || headlineStep.tool : 'awaiting subagent activity…'}
              </div>
              {totalSteps > 0 && (
                <div className="shrink-0 text-[9px] uppercase tracking-widest text-tui-dim">
                  {completedSteps}/{totalSteps}
                  {errorSteps > 0 ? ` • ${errorSteps} err` : ''}
                </div>
              )}
            </div>

            {visibleSteps.length > 0 && (
              <div className={cn('space-y-1', showAllTaskSteps ? 'max-h-52 overflow-y-auto pr-1' : '')}>
                {visibleSteps.map((step) => (
                  <div key={step.id} className="flex items-center gap-2">
                    <span
                      className={cn(
                        'shrink-0 text-[9px] uppercase tracking-widest px-1.5 py-0.5 rounded border',
                        getToolStatusBadgeClass(step.status)
                      )}
                    >
                      {step.status}
                    </span>
                    <span className="min-w-0 text-[10px] text-tui-text/80 truncate">
                      {step.title || step.tool}
                    </span>
                  </div>
                ))}
                {canToggleAllSteps && !showAllTaskSteps && hiddenStepCount > 0 && (
                  <button
                    type="button"
                    onClick={() => setShowAllTaskSteps(true)}
                    className="text-[9px] text-tui-accent hover:text-white underline hover:no-underline text-left"
                  >
                    +{hiddenStepCount} more…
                  </button>
                )}
                {canToggleAllSteps && showAllTaskSteps && (
                  <button
                    type="button"
                    onClick={() => setShowAllTaskSteps(false)}
                    className="text-[9px] text-tui-dim hover:text-tui-text underline hover:no-underline text-left"
                  >
                    Show less
                  </button>
                )}
              </div>
            )}
          </div>
        )}

        {isTaskTool && input && (
          <details className="group">
            <summary className="cursor-pointer select-none flex items-center justify-between gap-3">
              <div className="min-w-0 flex items-center gap-2">
                <div className="text-[9px] uppercase tracking-widest text-tui-dim">Prompt</div>
              </div>
              <ChevronRight
                size={12}
                className="shrink-0 transition-transform group-open:rotate-90 text-tui-dim"
              />
            </summary>
            <div className="mt-2 bg-ctp-crust/40 p-2 rounded border border-tui-border-dim overflow-x-auto">
              <pre>{formatJSON(input)}</pre>
            </div>
          </details>
        )}

        {input && !isTaskTool && (
          <details className="group">
            <summary className="cursor-pointer select-none flex items-center justify-between gap-3">
              <div className="min-w-0 flex items-center gap-2">
                <div className="text-[9px] uppercase tracking-widest text-tui-dim">Input</div>
                {inputFilePath && (
                  <div className="text-[9px] text-tui-dim/70 font-mono truncate">
                    {inputFilePath}
                  </div>
                )}
              </div>
              <ChevronRight
                size={12}
                className="shrink-0 transition-transform group-open:rotate-90 text-tui-dim"
              />
            </summary>
            <div className="mt-2 bg-ctp-crust/40 p-2 rounded border border-tui-border-dim overflow-x-auto">
              <pre>{formatJSON(input)}</pre>
            </div>
          </details>
        )}

        {output && (
          <div>
            <div className="text-[9px] uppercase tracking-widest text-tui-dim mb-1">Output</div>
            <div className="space-y-2">
              {outputSegments.map((segment, index) => {
                if (segment.type === 'text') {
                  return (
                    <div
                      key={`text-${index}`}
                      className="bg-ctp-crust/40 p-2 rounded border border-tui-border-dim overflow-x-auto text-tui-text/90"
                    >
                      <pre>{segment.text}</pre>
                    </div>
                  )
                }

                if (segment.type === 'diagnostics') {
                  const hasErrors = segment.diagnostics.some((d) => d.severity === 'error')

                  return (
                    <div key={`diag-${index}`} className="space-y-1">
                      <div className="flex items-center justify-between gap-3">
                        <div className="text-[9px] uppercase tracking-widest text-tui-dim">
                          Diagnostics
                        </div>
                        {segment.filePath && (
                          <div className="text-[9px] text-tui-dim/70 font-mono truncate">
                            {segment.filePath}
                          </div>
                        )}
                      </div>
                      <div
                        className={cn(
                          'rounded border overflow-hidden',
                          hasErrors
                            ? 'border-red-900/50 bg-red-950/10'
                            : 'border-tui-border-dim bg-ctp-crust/40'
                        )}
                      >
                        <div className="divide-y divide-tui-border/30">
                          {segment.diagnostics.length > 0 ? (
                            segment.diagnostics.map((diag, diagIndex) => (
                              <div key={diagIndex} className="px-2 py-1 flex gap-2">
                                <span
                                  className={cn(
                                    'shrink-0 text-[9px] uppercase tracking-widest px-1.5 py-0.5 rounded border',
                                    diag.severity === 'error'
                                      ? 'border-red-500/30 text-red-400'
                                      : diag.severity === 'warning'
                                      ? 'border-yellow-500/30 text-yellow-300'
                                      : diag.severity === 'info'
                                      ? 'border-blue-500/30 text-blue-300'
                                      : diag.severity === 'hint'
                                      ? 'border-purple-500/30 text-purple-300'
                                      : 'border-tui-dim/30 text-tui-dim'
                                  )}
                                >
                                  {diag.severity}
                                </span>
                                {typeof diag.line === 'number' && typeof diag.column === 'number' && (
                                  <span className="shrink-0 text-[10px] text-tui-dim font-mono">
                                    [{diag.line}:{diag.column}]
                                  </span>
                                )}
                                <span className="text-tui-text/90 break-words">{diag.message}</span>
                              </div>
                            ))
                          ) : (
                            <div className="px-2 py-1 text-[10px] text-tui-dim">
                              No diagnostics reported.
                            </div>
                          )}
                        </div>
                      </div>
                    </div>
                  )
                }

                return (
                  <div key={`file-${index}`} className="space-y-1">
                    <div className="bg-ctp-crust/40 rounded border border-tui-border-dim overflow-x-auto">
                      <SyntaxHighlighter
                        style={vscDarkPlus}
                        language={outputLanguage}
                        showLineNumbers
                        PreTag="div"
                        customStyle={{
                          margin: 0,
                          background: 'transparent',
                          fontSize: '0.75rem',
                        }}
                      >
                        {segment.code}
                      </SyntaxHighlighter>
                    </div>
                    {segment.meta.length > 0 && (
                      <div className="text-[10px] text-tui-dim whitespace-pre-wrap">
                        {segment.meta.join('\n')}
                      </div>
                    )}
                  </div>
                )
              })}
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

type ToolDiagnosticSeverity = 'error' | 'warning' | 'info' | 'hint' | 'unknown'

type ToolOutputDiagnostic = {
  severity: ToolDiagnosticSeverity
  line?: number
  column?: number
  message: string
  raw: string
}

type ToolOutputSegment =
  | { type: 'text'; text: string }
  | { type: 'file'; code: string; meta: string[] }
  | { type: 'diagnostics'; filePath?: string; diagnostics: ToolOutputDiagnostic[] }

function getToolInputFilePath(input?: Record<string, unknown>) {
  const filePath = input?.filePath
  if (typeof filePath === 'string' && filePath.length > 0) return filePath

  const path = input?.path
  if (typeof path === 'string' && path.length > 0) return path

  return undefined
}

function splitToolOutput(output: string): ToolOutputSegment[] {
  const segments: ToolOutputSegment[] = []
  const normalized = output.replace(/\r\n/g, '\n')
  const blockRegex = /<(file|file_diagnostics)>\s*([\s\S]*?)\s*<\/\1>/g

  let lastIndex = 0
  let match: RegExpExecArray | null

  while ((match = blockRegex.exec(normalized)) !== null) {
    const before = normalized.slice(lastIndex, match.index).trim()
    if (before) segments.push({ type: 'text', text: before })

    const tag = match[1]
    const inner = match[2] || ''
    let consumedUntil = blockRegex.lastIndex

    if (tag === 'file') {
      const { code, meta } = parseFileBlock(inner)
      segments.push({ type: 'file', code, meta })
    } else {
      const lineEnd = normalized.indexOf('\n', consumedUntil)
      const endOfLine = lineEnd === -1 ? normalized.length : lineEnd
      const trailing = normalized.slice(consumedUntil, endOfLine).trim()

      if (trailing) {
        consumedUntil = endOfLine
      }

      const diagnostics = parseDiagnosticsBlock(inner)
      segments.push({ type: 'diagnostics', filePath: trailing || undefined, diagnostics })
    }

    lastIndex = consumedUntil
    blockRegex.lastIndex = consumedUntil
  }

  const after = normalized.slice(lastIndex).trim()
  if (after) segments.push({ type: 'text', text: after })

  if (segments.length === 0) {
    return [{ type: 'text', text: normalized }]
  }

  return segments
}

function parseFileBlock(block: string) {
  const codeLines: string[] = []
  const meta: string[] = []

  const lines = block.replace(/\r\n/g, '\n').split('\n')
  for (const line of lines) {
    const match = line.match(/^\d+\|\s?(.*)$/)
    if (match) {
      codeLines.push(match[1] ?? '')
    } else {
      const trimmed = line.trimEnd()
      if (trimmed) meta.push(trimmed)
    }
  }

  return { code: codeLines.join('\n'), meta }
}

function parseDiagnosticsBlock(block: string): ToolOutputDiagnostic[] {
  const diagnostics: ToolOutputDiagnostic[] = []
  const lines = block.replace(/\r\n/g, '\n').split('\n')

  for (const line of lines) {
    const raw = line.trim()
    if (!raw) continue

    const match = raw.match(/^(ERROR|WARNING|WARN|INFO|HINT)\s+\[(\d+):(\d+)\]\s+(.*)$/i)

    if (match) {
      const severityRaw = (match[1] || '').toLowerCase()
      const severity: ToolDiagnosticSeverity =
        severityRaw === 'error'
          ? 'error'
          : severityRaw === 'warning' || severityRaw === 'warn'
          ? 'warning'
          : severityRaw === 'info'
          ? 'info'
          : severityRaw === 'hint'
          ? 'hint'
          : 'unknown'

      const lineNumber = Number(match[2])
      const columnNumber = Number(match[3])
      const message = match[4] || raw

      diagnostics.push({
        severity,
        line: Number.isFinite(lineNumber) ? lineNumber : undefined,
        column: Number.isFinite(columnNumber) ? columnNumber : undefined,
        message,
        raw,
      })

      continue
    }

    diagnostics.push({
      severity: 'unknown',
      message: raw,
      raw,
    })
  }

  return diagnostics
}

function inferLanguageFromFilePath(filePath?: string) {
  if (!filePath) return undefined

  const basename = filePath.split('/').pop() || filePath
  const dot = basename.lastIndexOf('.')
  if (dot < 0) return undefined

  const ext = basename.slice(dot + 1).toLowerCase()
  switch (ext) {
    case 'ts':
      return 'typescript'
    case 'tsx':
      return 'tsx'
    case 'js':
      return 'javascript'
    case 'jsx':
      return 'jsx'
    case 'json':
      return 'json'
    case 'md':
      return 'markdown'
    case 'yml':
    case 'yaml':
      return 'yaml'
    case 'toml':
      return 'toml'
    case 'css':
      return 'css'
    case 'html':
    case 'heex':
      return 'markup'
    case 'sh':
      return 'bash'
    case 'py':
      return 'python'
    case 'rs':
      return 'rust'
    case 'go':
      return 'go'
    case 'ex':
    case 'exs':
      return 'elixir'
    default:
      return undefined
  }
}
