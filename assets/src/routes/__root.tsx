import { createRootRouteWithContext, Link, Outlet, useLocation } from '@tanstack/react-router'
import { 
  Terminal, 
  Users, 
  LayoutDashboard, 
  UserCircle, 
  ClipboardList, 
  Mail, 
  Wifi, 
  WifiOff, 
  Menu, 
  X, 
  ChevronDown, 
  Plus, 
  FolderOpen, 
  Play, 
  Search, 
  Network,
  Settings,
  Activity,
  Bug
} from 'lucide-react'
import type { QueryClient } from '@tanstack/react-query'
import { useEffect, useState, createContext, useContext } from 'react'
import { useProjects, useDeleteProject, type Project } from '../api/queries'
import { API_BASE } from '../api/client'
import { NotificationProvider, useNotifications } from '../components/Notifications'
import { ProjectCreateModal } from '../components/ProjectCreateModal'
import { CommandPalette } from '../components/CommandPalette'
import { TerminalPanel } from '../components/TerminalPanel'
import { cn } from '../lib/cn'
import { Trash2 } from 'lucide-react'

interface MyRouterContext {
  queryClient: QueryClient
}

// Project context for sharing active project across the app
interface ProjectContextValue {
  activeProject: Project | null
  setActiveProjectId: (id: string) => void
  projects: Project[]
  isLoading: boolean
}

const ProjectContext = createContext<ProjectContextValue | null>(null)

export function useActiveProject() {
  const ctx = useContext(ProjectContext)
  if (!ctx) throw new Error('useActiveProject must be used within ProjectProvider')
  return ctx
}

export const Route = createRootRouteWithContext<MyRouterContext>()({
  component: () => (
    <NotificationProvider>
      <AppShell />
    </NotificationProvider>
  ),
})

function AppShell() {
  const { queryClient } = Route.useRouteContext()
  const { addNotification } = useNotifications()
  const { data: projects, isLoading: projectsLoading } = useProjects()
  const deleteProject = useDeleteProject()
  const [activeProjectId, setActiveProjectId] = useState<string | null>(null)
  const [sseStatus, setSseStatus] = useState<'connecting' | 'connected' | 'error'>('connecting')
  const [sidebarOpen, setSidebarOpen] = useState(false)
  const [projectDropdownOpen, setProjectDropdownOpen] = useState(false)
  const [createProjectOpen, setCreateProjectOpen] = useState(false)
  const [commandPaletteOpen, setCommandPaletteOpen] = useState(false)
  const [opsExpanded, setOpsExpanded] = useState(false)
  const [statusOpen, setStatusOpen] = useState(false)
  const location = useLocation()
  const operationsRoutes = ['/agent', '/review', '/events', '/nodes', '/fleet']
  const isOperationsRoute = operationsRoutes.some((path) => location.pathname.startsWith(path))
  const [utilitiesOpen, setUtilitiesOpen] = useState(false)

  // Set first project as active when projects load
  useEffect(() => {
    if (projects?.length && !activeProjectId) {
      setActiveProjectId(projects[0].id)
    }
  }, [projects, activeProjectId])

  useEffect(() => {
    if (isOperationsRoute) {
      setOpsExpanded(true)
    }
  }, [isOperationsRoute])

  const activeProject = projects?.find(p => p.id === activeProjectId) ?? null

  // Close sidebar on navigation
  useEffect(() => {
    setSidebarOpen(false)
  }, [location.pathname])

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape') {
        setSidebarOpen(false)
        setProjectDropdownOpen(false)
        setCreateProjectOpen(false)
        setStatusOpen(false)
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [])

  useEffect(() => {
    if (!activeProjectId) return

    const eventSource = new EventSource(`${API_BASE}/projects/${activeProjectId}/events/stream`)

    eventSource.onopen = () => {
      setSseStatus('connected')
    }

    eventSource.onmessage = (event) => {
      const payload = JSON.parse(event.data)
      if (payload.data) {
        const rawKind = payload.data.kind
        const kind = rawKind.replace(/^(\w+)\./, '$1:')
        
        // Broadcast event internally for components like SessionChat and TerminalPanel
        window.dispatchEvent(new CustomEvent('project-event', { 
          detail: { ...payload.data, kind } 
        }))

        addNotification({
          type: kind.includes('fail') || kind.includes('error') ? 'error' : 'success',
          title: kind.toUpperCase(),
          message: `Event detected: ${kind}`,
          duration: 4000
        })

        if (kind.startsWith('session:')) {
          queryClient.invalidateQueries({ queryKey: ['sessions'] })
        }
        if (kind.startsWith('agent:')) {
          queryClient.invalidateQueries({ queryKey: ['projects', activeProjectId, 'squads'] })
          queryClient.invalidateQueries({ queryKey: ['projects', activeProjectId, 'agents'] })
          queryClient.invalidateQueries({ queryKey: ['agents'] })
        }
        if (kind.startsWith('ticket:')) {
          queryClient.invalidateQueries({ queryKey: ['projects', activeProjectId, 'tickets'] })
        }
        if (kind.startsWith('mail:')) {
          queryClient.invalidateQueries({ queryKey: ['mail'] })
          if (activeProjectId) {
            queryClient.invalidateQueries({ queryKey: ['projects', activeProjectId, 'mail'] })
          }
        }
      }
    }

    eventSource.onerror = (err) => {
      console.error('SSE Error:', err)
      setSseStatus('error')
    }

    return () => {
      eventSource.close()
    }
  }, [activeProjectId, queryClient, addNotification])

  return (
    <ProjectContext.Provider value={{
      activeProject,
      setActiveProjectId,
      projects: projects ?? [],
      isLoading: projectsLoading,
    }}>
    <div className="flex min-h-screen bg-tui-bg text-tui-text font-mono">
      {/* Mobile sidebar overlay */}
      {sidebarOpen && (
        <div 
          className="fixed inset-0 bg-black/60 z-40 md:hidden"
          onClick={() => setSidebarOpen(false)}
        />
      )}

      {/* Sidebar */}
      <aside className={cn(
        "w-64 border-r border-tui-border flex flex-col bg-tui-bg z-50",
        "fixed inset-y-0 left-0 transform transition-transform duration-200 ease-in-out md:relative md:translate-x-0",
        sidebarOpen ? "translate-x-0" : "-translate-x-full"
      )}>
        <div className="p-4 border-b border-tui-border flex items-center justify-between">
          <div className="flex items-center gap-2">
            <Terminal className="text-tui-accent" aria-hidden="true" />
            <span className="font-bold text-xl tracking-tight">SQUADS_</span>
          </div>
          <button 
            aria-label="Close sidebar"
            className="p-2 text-tui-dim hover:text-tui-text md:hidden"
            onClick={() => setSidebarOpen(false)}
          >
            <X size={20} aria-hidden="true" />
          </button>
        </div>

        {/* Project Selector */}
        <div className="p-2 border-b border-tui-border">
          <div className="relative">
            <button
              aria-label={projectDropdownOpen ? "Close project selector" : "Open project selector"}
              aria-expanded={projectDropdownOpen}
              aria-haspopup="true"
              onClick={() => setProjectDropdownOpen(!projectDropdownOpen)}
              className={cn(
                "w-full flex items-center justify-between gap-2 px-3 py-2",
                "text-left text-sm border border-tui-border rounded",
                "hover:bg-tui-dim/10 transition-colors",
                "focus:outline-none focus:ring-1 focus:ring-tui-accent",
                projectDropdownOpen && "bg-tui-dim/10"
              )}
            >
              <div className="flex items-center gap-2 min-w-0">
                <FolderOpen size={14} className="text-tui-accent shrink-0" />
                <span className="truncate">
                  {activeProject?.name || 'No Project'}
                </span>
              </div>
              <ChevronDown size={14} className={cn(
                "text-tui-dim shrink-0 transition-transform",
                projectDropdownOpen && "rotate-180"
              )} />
            </button>

            {projectDropdownOpen && (
              <>
                <div 
                  className="fixed inset-0 z-10" 
                  onClick={() => setProjectDropdownOpen(false)} 
                  aria-hidden="true"
                />
                <div 
                  role="menu"
                  className="absolute left-0 right-0 mt-1 z-20 bg-tui-bg border border-tui-border rounded shadow-lg max-h-64 overflow-auto"
                >
                  {projects?.map(project => (
                    <button
                      key={project.id}
                      role="menuitem"
                      onClick={() => {
                        setActiveProjectId(project.id)
                        setProjectDropdownOpen(false)
                      }}
                      className={cn(
                        "w-full text-left px-3 py-2 text-sm hover:bg-tui-dim/20 transition-colors focus:outline-none focus:bg-tui-dim/20",
                        project.id === activeProjectId && "bg-tui-accent/10 text-tui-accent"
                      )}
                    >
                      <div className="font-medium truncate">{project.name}</div>
                      <div className="text-xs text-tui-dim truncate">{project.path}</div>
                    </button>
                  ))}
                  {(!projects || projects.length === 0) && (
                    <div className="px-3 py-2 text-sm text-tui-dim" role="menuitem" aria-disabled="true">
                      No projects yet
                    </div>
                  )}
                  <div className="border-t border-tui-border">
                    <button
                      role="menuitem"
                      onClick={() => {
                        setProjectDropdownOpen(false)
                        setCreateProjectOpen(true)
                      }}
                      className="w-full flex items-center gap-2 px-3 py-2 text-sm text-tui-accent hover:bg-tui-dim/20 transition-colors focus:outline-none focus:bg-tui-dim/20"
                    >
                      <Plus size={14} aria-hidden="true" />
                      <span>New Project</span>
                    </button>
                    {activeProject && (
                      <button
                        role="menuitem"
                        onClick={() => {
                          if (confirm(`Are you sure you want to delete project "${activeProject.name}"? This will remove all associated squads and agents.`)) {
                            deleteProject.mutate(activeProject.id, {
                              onSuccess: () => {
                                setProjectDropdownOpen(false)
                                setActiveProjectId(null)
                                addNotification({
                                  type: 'success',
                                  title: 'Project Deleted',
                                  message: `Project ${activeProject.name} has been removed.`,
                                })
                              }
                            })
                          }
                        }}
                        className="w-full flex items-center gap-2 px-3 py-2 text-sm text-ctp-red hover:bg-ctp-red/10 transition-colors focus:outline-none focus:bg-ctp-red/10"
                      >
                        <Trash2 size={14} aria-hidden="true" />
                        <span>Delete Current Project</span>
                      </button>
                    )}
                  </div>
                </div>
              </>
            )}
          </div>
        </div>
        
        <nav className="flex-1 p-2 space-y-4 overflow-y-auto">
          <div className="space-y-1">
            <div className="px-2 py-1 text-[10px] font-bold uppercase tracking-tui text-tui-dim">
              Primary
            </div>
            <NavItem to="/" icon={<LayoutDashboard size={20} />} label="Overview" />
            <NavItem to="/sessions" icon={<Play size={20} />} label="Sessions" />
            <NavItem to="/squad" icon={<Users size={20} />} label="Squad" />
            <NavItem to="/board" icon={<ClipboardList size={20} />} label="Board" />
            <NavItem to="/mail" icon={<Mail size={20} />} label="Mail" />
          </div>

          <div className="space-y-1">
            <button
              type="button"
              onClick={() => setOpsExpanded((prev) => !prev)}
              aria-expanded={opsExpanded}
              className="w-full flex items-center justify-between px-2 py-1 text-[10px] font-bold uppercase tracking-tui text-tui-dim hover:text-tui-text transition-colors"
            >
              <span>Operations</span>
              <ChevronDown
                size={14}
                className={cn('transition-transform', opsExpanded && 'rotate-180')}
              />
            </button>
            {opsExpanded && (
              <div className="space-y-1">
                <NavItem to="/agent" icon={<UserCircle size={20} />} label="Agents" />
                <NavItem to="/review" icon={<ClipboardList size={20} />} label="Review" />
                <NavItem to="/events" icon={<Terminal size={20} />} label="Events" />
                <NavItem to="/nodes" icon={<Wifi size={20} />} label="Nodes" />
                <NavItem to="/fleet" icon={<Network size={20} />} label="Fleet" />
              </div>
            )}
          </div>
        </nav>

        <div className="p-2 border-t border-tui-border">
           <div className="relative">
             <button
                onClick={() => setUtilitiesOpen(!utilitiesOpen)}
                className={cn(
                  "w-full flex items-center justify-between gap-2 px-3 py-2",
                  "text-left text-[10px] border border-tui-border rounded",
                  "hover:bg-tui-dim/10 transition-colors uppercase font-bold tracking-tui",
                  utilitiesOpen && "bg-tui-dim/10"
                )}
             >
                <div className="flex items-center gap-2">
                  <Settings size={14} className="text-tui-dim" />
                  <span>Utilities</span>
                </div>
                <ChevronDown size={14} className={cn("text-tui-dim transition-transform", utilitiesOpen && "rotate-180")} />
             </button>

             {utilitiesOpen && (
               <div className="absolute bottom-full left-0 right-0 mb-1 z-20 bg-tui-bg border border-tui-border rounded shadow-lg p-1 space-y-1">
                  <div className="px-2 py-1 text-[9px] font-bold uppercase tracking-tui text-tui-dim border-b border-tui-border/50 mb-1">System Tools</div>
                  <button 
                    onClick={() => {
                      setUtilitiesOpen(false)
                      setCommandPaletteOpen(true)
                    }}
                    className="w-full flex items-center gap-2 px-2 py-2 text-[10px] uppercase font-bold tracking-tui hover:bg-tui-dim/20 transition-colors text-left"
                  >
                    <Search size={14} />
                    <span>Command Palette (⌘K)</span>
                  </button>
                  <button 
                    onClick={() => {
                      setUtilitiesOpen(false)
                      window.dispatchEvent(new CustomEvent('toggle-terminal'))
                    }}
                    className="w-full flex items-center gap-2 px-2 py-2 text-[10px] uppercase font-bold tracking-tui hover:bg-tui-dim/20 transition-colors text-left"
                  >
                    <Terminal size={14} />
                    <span>Toggle Terminal</span>
                  </button>
                  {import.meta.env.DEV && (
                    <div className="pt-1 mt-1 border-t border-tui-border/50">
                      <div className="px-2 py-1 text-[9px] font-bold uppercase tracking-tui text-tui-accent">Dev Mode</div>
                      <div className="flex items-center gap-2 px-2 py-2 text-[10px] uppercase font-bold tracking-tui text-tui-dim">
                        <Bug size={14} />
                        <span>Devtools Active</span>
                      </div>
                    </div>
                  )}
               </div>
             )}
           </div>
        </div>

        <div className="p-4 border-t border-tui-border text-[10px] text-tui-dim flex items-center justify-between tracking-tui font-bold">
          <span>System Ready</span>
          <span>V0.1.0</span>
        </div>
      </aside>

      {/* Main Content */}
      <main className="flex-1 flex flex-col min-w-0 overflow-hidden">
        <header className="h-14 border-b border-tui-border flex items-center px-4 md:px-6 justify-between bg-black/20">
          <div className="flex items-center gap-3 md:gap-4">
            {/* Mobile hamburger menu */}
            <button 
              aria-label="Open sidebar"
              className="p-2 -ml-2 text-tui-dim hover:text-tui-text md:hidden"
              onClick={() => setSidebarOpen(true)}
            >
              <Menu size={24} aria-hidden="true" />
            </button>
            <span className="text-tui-dim hidden sm:inline text-[10px] font-bold tracking-tui uppercase">Project:</span>
            <span className="text-tui-text text-sm sm:text-base font-bold truncate max-w-[200px]">
              {activeProject?.name || 'No Project'}
            </span>
          </div>
          
          <div className="flex-1 flex justify-center px-4 max-w-md mx-auto hidden md:flex">
             <button 
                onClick={() => setCommandPaletteOpen(true)}
                className="w-full max-w-sm flex items-center justify-between gap-3 px-3 py-1.5 bg-black/40 border border-tui-border rounded text-tui-dim hover:text-tui-text hover:border-tui-accent transition-all group"
             >
                <div className="flex items-center gap-2">
                  <Search size={14} className="group-hover:text-tui-accent" />
                  <span className="text-[10px] font-bold tracking-tui uppercase">Search Commands...</span>
                </div>
                <div className="flex items-center gap-1">
                   <kbd className="px-1.5 py-0.5 rounded border border-tui-border bg-tui-dim/10 text-[10px] group-hover:border-tui-accent group-hover:text-tui-accent transition-colors">⌘K</kbd>
                </div>
             </button>
          </div>

          <div className="flex items-center gap-4">
            <div className="relative">
              <button
                type="button"
                onClick={() => setStatusOpen((open) => !open)}
                aria-expanded={statusOpen}
                className="flex items-center gap-2 text-[10px] font-bold tracking-tui uppercase text-tui-dim hover:text-tui-text transition-colors"
              >
                <span className="hidden sm:inline">Uplink</span>
                <div className={cn(
                  "w-2 h-2 rounded-full",
                  sseStatus === 'connected' ? "bg-ctp-green animate-pulse" :
                  sseStatus === 'connecting' ? "bg-ctp-peach animate-pulse" :
                  "bg-ctp-red"
                )} />
              </button>

              {statusOpen && (
                <>
                  <div className="fixed inset-0 z-40" onClick={() => setStatusOpen(false)} />
                  <div className="absolute right-0 top-full mt-2 z-50 w-80 border border-tui-border bg-tui-bg shadow-lg">
                    <div className="px-3 py-2 border-b border-tui-border text-[10px] font-bold uppercase tracking-widest text-tui-dim flex justify-between items-center">
                      <span>System_Status</span>
                      <button onClick={() => setStatusOpen(false)} className="hover:text-tui-text"><X size={12} /></button>
                    </div>
                    <div className="p-3 space-y-3 text-xs text-tui-dim">
                      <div className="flex items-center justify-between">
                        <span>Status</span>
                        <span className={cn(
                          "font-mono font-bold px-1.5 py-0.5 border rounded-sm",
                          sseStatus === 'connected' ? "border-ctp-green/30 text-ctp-green bg-ctp-green/5" :
                          sseStatus === 'connecting' ? "border-ctp-peach/30 text-ctp-peach bg-ctp-peach/5" :
                          "border-ctp-red/30 text-ctp-red bg-ctp-red/5"
                        )}>
                          {sseStatus === 'connected' ? 'ESTABLISHED' :
                           sseStatus === 'connecting' ? 'NEGOTIATING' :
                           'DISCONNECTED'}
                        </span>
                      </div>
                      <div className="flex items-center justify-between">
                        <span>Project_ID</span>
                        <span className="font-mono text-tui-text">
                          {activeProjectId?.slice(0, 8) || 'OFFLINE'}
                        </span>
                      </div>
                      <div className="flex items-center justify-between gap-3">
                        <span>Working_Dir</span>
                        <span
                          className="font-mono text-tui-text truncate max-w-[180px]"
                          title={activeProject?.path || '~/workspace'}
                        >
                          {activeProject?.path || '~/workspace'}
                        </span>
                      </div>
                      {activeProject && (
                        <div className="pt-2 mt-2 border-t border-tui-border">
                          <button
                            onClick={() => {
                              if (confirm(`Are you sure you want to remove project "${activeProject.name}"? This will remove all associated squads and agents.`)) {
                                deleteProject.mutate(activeProject.id, {
                                  onSuccess: () => {
                                    setStatusOpen(false)
                                    setActiveProjectId(null)
                                    addNotification({
                                      type: 'success',
                                      title: 'Project Removed',
                                      message: `Project ${activeProject.name} has been removed.`,
                                    })
                                  }
                                })
                              }
                            }}
                            className="w-full flex items-center gap-2 px-2 py-1.5 text-ctp-red hover:bg-ctp-red/10 transition-colors rounded"
                          >
                            <Trash2 size={14} aria-hidden="true" />
                            <span>Remove Project</span>
                          </button>
                        </div>
                      )}
                    </div>
                  </div>
                </>
              )}
            </div>
          </div>
        </header>

        <div className="flex-1 overflow-auto p-4 md:p-6 relative">
          {sseStatus === 'error' && (
            <div className="mb-4 p-3 bg-ctp-red/10 border border-ctp-red/30 text-ctp-red flex items-center justify-between gap-3 animate-in fade-in slide-in-from-top-2">
              <div className="flex items-center gap-2 text-xs font-bold tracking-widest uppercase">
                <WifiOff size={16} />
                <span>Uplink_Signal_Lost_Retrying...</span>
              </div>
              <button 
                onClick={() => window.location.reload()}
                className="text-[10px] underline hover:no-underline font-bold uppercase tracking-widest"
              >
                Reconnect_Now
              </button>
            </div>
          )}
          <Outlet />
        </div>
      </main>

      <ProjectCreateModal 
        isOpen={createProjectOpen} 
        onClose={() => setCreateProjectOpen(false)} 
      />
      <CommandPalette 
        isOpen={commandPaletteOpen}
        setIsOpen={setCommandPaletteOpen}
        activeProjectId={activeProjectId}
      />
      {activeProjectId && <TerminalPanel projectId={activeProjectId} />}
    </div>
    </ProjectContext.Provider>
  )
}

function NavItem({ to, icon, label }: { to: string; icon: React.ReactNode; label: string }) {
  return (
    <Link
      to={to}
      activeProps={{
        className: 'bg-tui-dim/20 text-tui-text border-l-2 border-tui-accent',
      }}
      inactiveProps={{
        className: 'text-tui-dim hover:bg-tui-dim/10 hover:text-tui-text',
      }}
      className="flex items-center gap-3 px-3 py-3 md:py-2 transition-colors duration-150"
    >
      {icon}
      <span className="text-sm font-bold tracking-widest">{label}</span>
    </Link>
  )
}
