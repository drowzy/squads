import { useState, useEffect } from 'react'
import React from 'react'
import { cn } from '../lib/cn'
import { DiffPanel } from './DiffPanel'
import { RightSidebar } from './RightSidebar'
import { SessionSidebar } from './SessionSidebar'
import type { Session, SessionMessageEntry, SessionDiffEntry } from '../api/queries'

interface AgentLayoutProps {
  agentId: string
  currentSession?: Session | null
  sessions: Session[]
  selectedSessionId: string
  onSessionSelect: (sessionId: string) => void
  onNewSession: () => void
  messages?: SessionMessageEntry[]
  diffs?: SessionDiffEntry[]
  logsContent?: React.ReactNode
  statsContent?: React.ReactNode
  timelineContent?: React.ReactNode
  todosContent?: React.ReactNode
  children: React.ReactNode
  onViewDiff?: () => void
}

export function AgentLayout({
  agentId,
  currentSession,
  sessions,
  selectedSessionId,
  onSessionSelect,
  onNewSession,
  messages,
  diffs,
  logsContent,
  statsContent,
  timelineContent,
  todosContent,
  children,
  onViewDiff,
}: AgentLayoutProps) {
  const [diffOpen, setDiffOpen] = useState(false)
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [activeSidebarTab, setActiveSidebarTab] = useState<'logs' | 'stats' | 'timeline' | 'todos'>('logs')
  const [historyFilter, setHistoryFilter] = useState<'active' | 'history' | 'all'>('active')

  const handleViewDiff = () => {
    setDiffOpen(true)
  }

  useEffect(() => {
    if (diffs && diffs.length > 0 && !diffOpen) {
      setDiffOpen(true)
    }
  }, [diffs, diffOpen])

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.target instanceof HTMLInputElement || e.target instanceof HTMLTextAreaElement) {
        return
      }

      if (e.key === '[') {
        e.preventDefault()
        setDiffOpen((prev) => !prev)
      }

      if (e.key === ']') {
        e.preventDefault()
        setSidebarOpen((prev) => !prev)
      }
    }

    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [])

  return (
    <div className="h-full flex min-h-0">
      <SessionSidebar
        isOpen={sidebarOpen}
        onClose={() => setSidebarOpen(false)}
        currentSession={currentSession}
        sessions={sessions}
        selectedSessionId={selectedSessionId}
        onSelectSession={onSessionSelect}
        historyFilter={historyFilter}
        onHistoryFilterChange={setHistoryFilter}
        onNewSession={onNewSession}
      />

      <div className="flex flex-1 min-w-0">
        <div className="flex-1 min-w-0 flex flex-col">
          {onViewDiff
            ? React.Children.map(children, (child) =>
                React.isValidElement(child)
                  ? React.cloneElement(child, { onViewDiff: handleViewDiff } as any)
                  : child
              )
            : children}
        </div>

        {diffOpen && (
          <div className="w-0 min-w-0 md:min-w-[400px] max-w-[600px] border-l border-tui-border absolute inset-y-0 right-0 bg-ctp-base z-10 md:relative">
            <DiffPanel
              diffs={diffs}
              messages={messages}
              isOpen={diffOpen}
              onClose={() => setDiffOpen(false)}
            />
          </div>
        )}
      </div>

      <RightSidebar
        isOpen={sidebarOpen}
        activeTab={activeSidebarTab}
        onTabChange={setActiveSidebarTab}
        onClose={() => setSidebarOpen(false)}
        logsContent={logsContent}
        statsContent={statsContent}
        timelineContent={timelineContent}
        todosContent={todosContent}
      />
    </div>
  )
}
