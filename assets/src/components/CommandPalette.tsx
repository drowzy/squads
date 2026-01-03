import React, { useEffect } from 'react'
import { Command } from 'cmdk'
import type { Dispatch, SetStateAction } from 'react'
import { useNavigate } from '@tanstack/react-router'
import { 
  Search, 
  Users, 
  Play, 
  UserCircle, 
  LayoutDashboard, 
  ClipboardList, 
  Mail,
  ChevronRight,
  PlusCircle
} from 'lucide-react'
import { useAgents, useSquads, useSessions, useProjects, useNewSession } from '../api/queries'
import { cn } from '../lib/cn'
import { useNotifications } from './Notifications'

interface CommandPaletteProps {
  isOpen: boolean
  setIsOpen: Dispatch<SetStateAction<boolean>>
  activeProjectId: string | null
}

export function CommandPalette({ isOpen, setIsOpen, activeProjectId }: CommandPaletteProps) {
  const navigate = useNavigate()
  const { data: agents } = useAgents(activeProjectId || undefined)
  const { data: squads } = useSquads(activeProjectId || '')
  const { data: sessions } = useSessions()
  const { data: projects } = useProjects()
  const newSession = useNewSession()
  const { addNotification } = useNotifications()

  // Find current agent from URL if possible
  const path = window.location.pathname
  const agentMatch = path.match(/\/agent\/([^?\/]+)/)
  const currentAgentId = agentMatch ? agentMatch[1] : null
  const currentAgent = agents?.find(a => a.id === currentAgentId || a.slug === currentAgentId)

  // Toggle the menu when ⌘K is pressed
  useEffect(() => {
    const down = (e: KeyboardEvent) => {
      if ((e.key === 'k' || e.key === 'K') && (e.metaKey || e.ctrlKey)) {
        e.preventDefault()
        setIsOpen((open) => !open)
      }
    }

    window.addEventListener('keydown', down, { capture: true })
    return () => window.removeEventListener('keydown', down, { capture: true })
  }, [setIsOpen])

  const runCommand = (command: () => void) => {
    command()
    setIsOpen(false)
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 z-[100] flex items-start justify-center pt-[15vh] p-4 bg-black/60 backdrop-blur-sm animate-in fade-in duration-200">
      <div 
        className="fixed inset-0" 
        onClick={() => setIsOpen(false)} 
        aria-hidden="true"
      />
      <Command
        label="Global Command Menu"
        onKeyDown={(e) => {
          if (e.key === 'Escape') {
            setIsOpen(false)
          }
        }}
        className={cn(
          "relative w-full max-w-2xl bg-tui-bg border border-tui-border rounded-lg shadow-2xl overflow-hidden flex flex-col font-mono",
          "animate-in zoom-in-95 duration-200"
        )}
      >
        <div className="flex items-center border-b border-tui-border px-4 py-3">
          <Search className="mr-3 h-5 w-5 text-tui-dim" />
          <Command.Input
            autoFocus
            placeholder="Type a command or search..."
            className="flex-1 bg-transparent border-none outline-none text-tui-text placeholder:text-tui-dim text-lg"
          />
          <div className="flex items-center gap-1.5 ml-4">
            <kbd className="px-1.5 py-0.5 rounded border border-tui-border bg-tui-dim/10 text-[10px] text-tui-dim">ESC</kbd>
          </div>
        </div>

        <Command.List className="max-h-[60vh] overflow-y-auto p-2 custom-scrollbar">
          <Command.Empty className="py-12 text-center text-tui-dim flex flex-col items-center gap-2">
            <div className="text-xl font-bold tracking-widest uppercase">No_Results_Found</div>
            <div className="text-xs">Try searching for something else</div>
          </Command.Empty>

          <Command.Group heading={<span className="text-[10px] font-bold tracking-[0.2em] text-tui-dim px-2 mb-2 block uppercase">Navigation</span>}>
            {currentAgent && (
              <PaletteItem
                onSelect={() => runCommand(async () => {
                  try {
                    await newSession.mutateAsync({
                      agent_id: currentAgent.id,
                      title: `New Session for ${currentAgent.name}`
                    })
                    navigate({ to: `/agent/${currentAgent.id}` })
                    addNotification({
                      type: 'success',
                      title: 'New Session Started',
                      message: `Started a fresh session for ${currentAgent.name}`
                    })
                  } catch (err) {
                    addNotification({
                      type: 'error',
                      title: 'Failed to start session',
                      message: err instanceof Error ? err.message : 'Unknown error'
                    })
                  }
                })}
                icon={<PlusCircle size={18} className="text-tui-accent" />}
                label={`New Session for ${currentAgent.name}`}
                shortcut="⌘ N"
              />
            )}
            {!currentAgent && (
              <PaletteItem
                onSelect={() => runCommand(() => navigate({ to: '/agent' }))}
                icon={<PlusCircle size={18} className="text-tui-accent" />}
                label="New Session"
                description="Select an agent to start a new session"
              />
            )}
            <PaletteItem
              onSelect={() => runCommand(() => navigate({ to: '/' }))}
              icon={<LayoutDashboard size={18} />}
              label="Overview"
              shortcut="G O"
            />
            <PaletteItem
              onSelect={() => runCommand(() => navigate({ to: '/squad' }))}
              icon={<Users size={18} />}
              label="Squad"
              shortcut="G S"
            />
            <PaletteItem
              onSelect={() => runCommand(() => navigate({ to: '/sessions' }))}
              icon={<Play size={18} />}
              label="Sessions"
              shortcut="G P"
            />
            <PaletteItem
              onSelect={() => runCommand(() => navigate({ to: '/board' }))}
              icon={<ClipboardList size={18} />}
              label="Board"
              shortcut="G B"
            />
            <PaletteItem
              onSelect={() => runCommand(() => navigate({ to: '/agent' }))}
              icon={<UserCircle size={18} />}
              label="Agents"
              shortcut="G A"
            />
            <PaletteItem
              onSelect={() => runCommand(() => navigate({ to: '/mail' }))}
              icon={<Mail size={18} />}
              label="Mail"
              shortcut="G M"
            />
          </Command.Group>

          {agents && agents.length > 0 && (
            <Command.Group heading={<span className="text-[10px] font-bold tracking-[0.2em] text-tui-dim px-2 mt-4 mb-2 block uppercase">Agents</span>}>
              {agents.map(agent => (
                <PaletteItem
                  key={agent.id}
                  onSelect={() => runCommand(() => navigate({ to: `/agent`, search: { search: agent.slug } }))}
                  icon={<UserCircle size={18} className="text-tui-accent" />}
                  label={agent.name}
                  description={agent.role}
                />
              ))}
            </Command.Group>
          )}

          {squads && squads.length > 0 && (
            <Command.Group heading={<span className="text-[10px] font-bold tracking-[0.2em] text-tui-dim px-2 mt-4 mb-2 block uppercase">Squads</span>}>
              {squads.map(squad => (
                <PaletteItem
                  key={squad.id}
                  onSelect={() => runCommand(() => navigate({ to: '/squad' }))}
                  icon={<Users size={18} className="text-tui-success" />}
                  label={squad.name}
                  description={squad.description || 'No description'}
                />
              ))}
            </Command.Group>
          )}

          {sessions && sessions.length > 0 && (
            <Command.Group heading={<span className="text-[10px] font-bold tracking-[0.2em] text-tui-dim px-2 mt-4 mb-2 block uppercase">Recent Sessions</span>}>
              {sessions.slice(0, 5).map(session => (
                <PaletteItem
                  key={session.id}
                  onSelect={() => runCommand(() => navigate({ to: `/agent/${session.agent_id}` }))}
                  icon={<Play size={18} className="text-tui-warning" />}
                  label={session.ticket_key || session.id.slice(0, 8)}
                  description={session.status}
                />
              ))}
            </Command.Group>
          )}

          {projects && projects.length > 1 && (
            <Command.Group heading={<span className="text-[10px] font-bold tracking-[0.2em] text-tui-dim px-2 mt-4 mb-2 block uppercase">Projects</span>}>
              {projects.map(project => (
                <PaletteItem
                  key={project.id}
                  onSelect={() => runCommand(() => {
                    navigate({ to: '/' })
                  })}
                  icon={<ChevronRight size={18} />}
                  label={project.name}
                  description={project.path}
                />
              ))}
            </Command.Group>
          )}
        </Command.List>

        <div className="border-t border-tui-border p-3 bg-black/20 flex items-center justify-between text-[10px] text-tui-dim uppercase tracking-widest font-bold">
          <div className="flex items-center gap-4">
            <div className="flex items-center gap-1.5">
              <kbd className="px-1 py-0.5 rounded border border-tui-border bg-tui-dim/10">↑↓</kbd>
              <span>Navigate</span>
            </div>
            <div className="flex items-center gap-1.5">
              <kbd className="px-1 py-0.5 rounded border border-tui-border bg-tui-dim/10">ENTER</kbd>
              <span>Execute</span>
            </div>
          </div>
          <div className="flex items-center gap-1.5">
            <span>Uplink_Active</span>
            <div className="w-1.5 h-1.5 rounded-full bg-tui-success animate-pulse" />
          </div>
        </div>
      </Command>
    </div>
  )
}

function PaletteItem({ 
  onSelect, 
  icon, 
  label, 
  description, 
  shortcut 
}: { 
  onSelect: () => void
  icon: React.ReactNode
  label: string
  description?: string
  shortcut?: string
}) {
  return (
    <Command.Item
      onSelect={onSelect}
      className={cn(
        "flex items-center justify-between px-3 py-2.5 rounded-md cursor-pointer",
        "aria-selected:bg-tui-accent aria-selected:text-white transition-colors duration-75",
        "group"
      )}
    >
      <div className="flex items-center gap-3">
        <div className="text-tui-dim group-aria-selected:text-white">
          {icon}
        </div>
        <div className="flex flex-col">
          <span className="text-sm font-bold">{label}</span>
          {description && (
            <span className="text-[10px] text-tui-dim group-aria-selected:text-white/70 line-clamp-1 italic">
              {description}
            </span>
          )}
        </div>
      </div>
      {shortcut && (
        <div className="flex items-center gap-1">
          {shortcut.split(' ').map((s, i) => (
            <kbd key={i} className="px-1.5 py-0.5 rounded border border-tui-border bg-tui-dim/10 text-[9px] group-aria-selected:border-white/30 group-aria-selected:bg-white/10 group-aria-selected:text-white">
              {s}
            </kbd>
          ))}
        </div>
      )}
    </Command.Item>
  )
}
