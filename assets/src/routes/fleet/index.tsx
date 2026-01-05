import { createFileRoute } from '@tanstack/react-router'
import { useProjects, useSquadConnections, useCreateSquadConnection, useDeleteSquadConnection, useSquads, SquadConnection, Squad, Project } from '../../api/queries'
import { useState, useMemo } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '../../components/ui/card'
import { Button } from '../../components/ui/button'
import { Plus, Link, Trash2, ArrowRight, Mail } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '../../components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../../components/ui/select'
import { Label } from '../../components/ui/label'
import { Badge } from '../../components/ui/badge'
import { useQueries } from '@tanstack/react-query'
import { fetcher } from '../../api/client'
import { SquadFlow } from '../../components/fleet/SquadFlow'
import { ReactFlowProvider } from '@xyflow/react'
import { MessageSquadModal } from '../../components/fleet/MessageSquadModal'

export const Route = createFileRoute('/fleet/')({
  component: FleetIndex,
})

function FleetIndex() {
  const { data: projects = [], isLoading: isProjectsLoading } = useProjects()
  
  const [messageConfig, setMessageConfig] = useState<{ from: Squad, to: Squad } | null>(null)
  
  const squadQueries = useQueries({
    queries: projects.map((project) => ({
      queryKey: ['projects', project.id, 'squads'],
      queryFn: () => fetcher<Squad[]>(`/projects/${project.id}/squads`),
      enabled: !!project.id,
    })),
  })

  const connectionQueries = useQueries({
    queries: projects.map((project) => ({
      queryKey: ['projects', project.id, 'connections'],
      queryFn: () => fetcher<SquadConnection[]>(`/fleet/connections?project_id=${project.id}`),
      enabled: !!project.id,
    })),
  })

  const projectsWithData = useMemo(() => {
    return projects.map((project, index) => ({
      ...project,
      squads: squadQueries[index]?.data || [],
      connections: connectionQueries[index]?.data || [],
      isLoading: squadQueries[index]?.isLoading || connectionQueries[index]?.isLoading
    }))
  }, [projects, squadQueries, connectionQueries])

  const allSquads = useMemo(() => 
    projectsWithData.flatMap(p => p.squads), 
  [projectsWithData])

  const allConnections = useMemo(() => {
    const seen = new Set<string>()
    return projectsWithData.flatMap(p => p.connections).filter(c => {
      if (seen.has(c.id)) return false
      seen.add(c.id)
      return true
    })
  }, [projectsWithData])

  return (
    <div className="container mx-auto p-6 space-y-8 max-w-7xl">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Fleet Command</h1>
          <p className="text-muted-foreground mt-2">
            Manage global squad infrastructure and cross-project connections.
          </p>
        </div>
        <CreateConnectionDialog projects={projects} />
      </div>

      <ReactFlowProvider>
        <SquadFlow 
          squads={allSquads} 
          connections={allConnections} 
          onMessage={(to) => {
            // Find a reasonable 'from' squad - ideally one that is connected
            const connection = allConnections.find(c => c.to_squad_id === to.id || c.from_squad_id === to.id)
            if (connection) {
              const from = connection.from_squad_id === to.id ? connection.to_squad : connection.from_squad
              if (from) setMessageConfig({ from, to })
            } else if (allSquads.length > 1) {
              // Fallback to first other squad if no connection exists but we have squads
              const from = allSquads.find(s => s.id !== to.id)
              if (from) setMessageConfig({ from, to })
            }
          }}
        />
      </ReactFlowProvider>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {projectsWithData.map((projectData) => (
          <ProjectFleetCard 
            key={projectData.id} 
            projectData={projectData} 
            onMessage={(from, to) => setMessageConfig({ from, to })}
          />
        ))}
      </div>

      {messageConfig && (
        <MessageSquadModal
          fromSquad={messageConfig.from}
          toSquad={messageConfig.to}
          isOpen={!!messageConfig}
          onClose={() => setMessageConfig(null)}
        />
      )}
    </div>
  )
}

function ProjectFleetCard({ 
  projectData, 
  onMessage 
}: { 
  projectData: Project & { squads: Squad[], connections: SquadConnection[], isLoading: boolean },
  onMessage: (from: Squad, to: Squad) => void
}) {
  const { squads, connections } = projectData

  return (
    <Card className="flex flex-col h-full">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
            <CardTitle className="text-lg font-semibold truncate" title={projectData.name}>
                {projectData.name}
            </CardTitle>
            <Badge variant="outline" className="font-mono text-xs">
                {projectData.path.split('/').pop()}
            </Badge>
        </div>
      </CardHeader>
      <CardContent className="flex-1">
        <div className="space-y-4">
            <div>
                <h4 className="text-sm font-medium text-muted-foreground mb-2 flex items-center gap-2">
                    Squads
                    <Badge variant="secondary" className="h-5 px-1.5 text-[10px]">{squads?.length || 0}</Badge>
                </h4>
                <div className="space-y-1">
                    {squads?.map(squad => (
                        <div key={squad.id} className="text-sm border rounded-md px-3 py-2 bg-muted/30">
                            <div className="font-medium">{squad.name}</div>
                            {squad.description && <div className="text-xs text-muted-foreground truncate">{squad.description}</div>}
                        </div>
                    ))}
                    {!squads?.length && !projectData.isLoading && <div className="text-sm text-muted-foreground italic">No squads deployed</div>}
                    {projectData.isLoading && <div className="text-sm text-muted-foreground italic">Loading squads...</div>}
                </div>
            </div>

            {connections && connections.length > 0 && (
                <div>
                    <h4 className="text-sm font-medium text-muted-foreground mb-2">Active Connections</h4>
                    <div className="space-y-2">
                        {connections.map(conn => (
                            <ConnectionItem 
                                key={conn.id} 
                                connection={conn} 
                                currentProjectId={projectData.id} 
                                onMessage={onMessage}
                            />
                        ))}
                    </div>
                </div>
            )}
        </div>
      </CardContent>
    </Card>
  )
}

function ConnectionItem({ 
    connection, 
    currentProjectId,
    onMessage
}: { 
    connection: SquadConnection, 
    currentProjectId: string,
    onMessage: (from: Squad, to: Squad) => void
}) {
    const { mutate: deleteConnection } = useDeleteSquadConnection()
    
    // Determine direction relative to current project
    const isOutgoing = connection.from_squad?.project_id === currentProjectId
    const otherSquad = isOutgoing ? connection.to_squad : connection.from_squad
    const mySquad = isOutgoing ? connection.from_squad : connection.to_squad
    
    if (!otherSquad || !mySquad) return null

    return (
        <div className="text-xs border rounded-md p-2 flex items-center justify-between group bg-background">
            <div className="flex items-center gap-2 overflow-hidden">
                <div className="flex flex-col min-w-0">
                    <div className="flex items-center gap-1">
                        <Badge variant="outline" className="text-[10px] px-1 h-4 shrink-0">
                            {mySquad.name}
                        </Badge>
                        <ArrowRight className="w-3 h-3 text-muted-foreground shrink-0" />
                        <span className="font-medium truncate">{otherSquad.name}</span>
                    </div>
                    {otherSquad.project_name && (
                        <div className="text-[10px] text-muted-foreground truncate pl-1">
                            {otherSquad.project_name}
                        </div>
                    )}
                </div>
            </div>
            <div className="flex items-center gap-1 opacity-0 group-hover:opacity-100 transition-opacity -mr-1">
                <Button
                    variant="ghost"
                    size="icon"
                    className="h-6 w-6"
                    onClick={() => onMessage(mySquad, otherSquad)}
                >
                    <Mail className="w-3 h-3" />
                </Button>
                <Button
                    variant="ghost"
                    size="icon"
                    className="h-6 w-6"
                    onClick={() => deleteConnection(connection.id)}
                >
                    <Trash2 className="w-3 h-3 text-destructive" />
                </Button>
            </div>
        </div>
    )
}

function CreateConnectionDialog({ projects }: { projects: Project[] }) {
    const [open, setOpen] = useState(false)
    const [fromProject, setFromProject] = useState<string>('')
    const [fromSquad, setFromSquad] = useState<string>('')
    const [toProject, setToProject] = useState<string>('')
    const [toSquad, setToSquad] = useState<string>('')
    
    // We need to fetch squads for selected projects
    // This is a bit inefficient to do inside the dialog with hooks dependent on state, 
    // but works for now. 
    const { data: fromSquads } = useQuerySquads(fromProject)
    const { data: toSquads } = useQuerySquads(toProject)
    
    const { mutate: createConnection, isPending } = useCreateSquadConnection()

    const handleSubmit = () => {
        if (!fromSquad || !toSquad) return
        createConnection({
            from_squad_id: fromSquad,
            to_squad_id: toSquad
        }, {
            onSuccess: () => {
                setOpen(false)
                setFromSquad('')
                setToSquad('')
            }
        })
    }

    return (
        <Dialog open={open} onOpenChange={setOpen}>
            <DialogTrigger asChild>
                <Button>
                    <Plus className="w-4 h-4 mr-2" />
                    New Connection
                </Button>
            </DialogTrigger>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>Connect Squads</DialogTitle>
                </DialogHeader>
                <div className="grid gap-4 py-4">
                    <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                            <Label>From Project</Label>
                            <Select value={fromProject} onValueChange={(v) => { setFromProject(v); setFromSquad('') }}>
                                <SelectTrigger>
                                    <SelectValue placeholder="Select project" />
                                </SelectTrigger>
                                <SelectContent>
                                    {projects.map(p => (
                                        <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                        </div>
                        <div className="space-y-2">
                            <Label>To Project</Label>
                            <Select value={toProject} onValueChange={(v) => { setToProject(v); setToSquad('') }}>
                                <SelectTrigger>
                                    <SelectValue placeholder="Select project" />
                                </SelectTrigger>
                                <SelectContent>
                                    {projects.map(p => (
                                        <SelectItem key={p.id} value={p.id}>{p.name}</SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                        </div>
                    </div>

                    <div className="grid grid-cols-2 gap-4">
                        <div className="space-y-2">
                            <Label>From Squad</Label>
                            <Select value={fromSquad} onValueChange={setFromSquad} disabled={!fromProject}>
                                <SelectTrigger>
                                    <SelectValue placeholder="Select squad" />
                                </SelectTrigger>
                                <SelectContent>
                                    {fromSquads?.map(s => (
                                        <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                        </div>
                        <div className="space-y-2">
                            <Label>To Squad</Label>
                            <Select value={toSquad} onValueChange={setToSquad} disabled={!toProject}>
                                <SelectTrigger>
                                    <SelectValue placeholder="Select squad" />
                                </SelectTrigger>
                                <SelectContent>
                                    {toSquads?.map(s => (
                                        <SelectItem key={s.id} value={s.id}>{s.name}</SelectItem>
                                    ))}
                                </SelectContent>
                            </Select>
                        </div>
                    </div>
                    
                    <div className="flex justify-end pt-4">
                        <Button onClick={handleSubmit} disabled={!fromSquad || !toSquad || isPending}>
                            {isPending ? 'Connecting...' : 'Connect Squads'}
                        </Button>
                    </div>
                </div>
            </DialogContent>
        </Dialog>
    )
}

// Helper wrapper to use existing hook
function useQuerySquads(projectId: string) {
    return useSquads(projectId)
}
