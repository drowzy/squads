import { createFileRoute } from '@tanstack/react-router'
import { useProjects, useSquadConnections, useCreateSquadConnection, useDeleteSquadConnection, useSquads, SquadConnection, Squad, Project } from '../../api/queries'
import { useState } from 'react'
import { Card, CardHeader, CardTitle, CardContent } from '../../components/ui/card'
import { Button } from '../../components/ui/button'
import { Plus, Link, Trash2, ArrowRight } from 'lucide-react'
import { Dialog, DialogContent, DialogHeader, DialogTitle, DialogTrigger } from '../../components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '../../components/ui/select'
import { Label } from '../../components/ui/label'
import { Badge } from '../../components/ui/badge'

export const Route = createFileRoute('/fleet/')({
  component: FleetIndex,
})

function FleetIndex() {
  const { data: projects, isLoading: isProjectsLoading } = useProjects()
  // Fetch connections for all projects - the API supports listing all if no project_id is provided?
  // Wait, the API currently requires project_id or squad_id. 
  // Let's assume we might need to fetch for each project or update the API to support global listing.
  // For now, let's just fetch connections for each project and aggregate, or maybe just list projects and their squads first.
  
  // Actually, to show the "Fleet" view, we ideally want a global list of connections.
  // But our API endpoint `index` currently expects params. 
  // Let's check the API controller implementation. 
  // It matches on %{"squad_id" => ...} or %{"project_id" => ...}.
  // It does NOT have a catch-all clause for global listing.
  // We might need to update the backend to allow listing all connections if we want a truly global view, 
  // OR we iterate over projects. Iterating is fine for now if the number of projects is small.
  
  // However, for the UI, let's display the list of projects and squads, and then a list of connections.

  // Let's try to fetch connections for the first project for now, or maybe we can't easily get ALL connections without a backend change.
  // Let's assume for this ticket we will focus on the UI structure and maybe just show connections per project or request a backend change if needed.
  // Actually, the prompt implied "Global squads + connections".
  // I will implement the UI to show all projects and squads. 
  // For connections, I'll temporarily just list them if I can, or I might need to make a quick backend tweak to allow listing all.
  
  // Let's check if I can just pass nothing to useSquadConnections? 
  // The hook allows params to be optional, but the backend implementation strictly pattern matches.
  // `def index(conn, %{"squad_id" => squad_id})`
  // `def index(conn, %{"project_id" => project_id})`
  // It will crash or 404/400 if params are missing? No, Phoenix controller matching... 
  // If no clause matches, it raises a FunctionClauseError.
  
  // So I should probably update the backend to support listing all connections.
  // BUT, I'm in the "UI" ticket now. I can do a quick fix to the backend as part of this if needed.
  // OR I can just map over projects and fetch connections.
  
  // Let's just list projects and squads first.
  
  return (
    <div className="container mx-auto p-6 space-y-8 max-w-7xl">
      <div className="flex items-center justify-between">
        <div>
          <h1 className="text-3xl font-bold tracking-tight">Fleet Command</h1>
          <p className="text-muted-foreground mt-2">
            Manage global squad infrastructure and cross-project connections.
          </p>
        </div>
        <CreateConnectionDialog projects={projects || []} />
      </div>

      <div className="grid gap-6 md:grid-cols-2 lg:grid-cols-3">
        {projects?.map((project) => (
          <ProjectFleetCard key={project.id} project={project} />
        ))}
      </div>
    </div>
  )
}

function ProjectFleetCard({ project }: { project: Project }) {
  // We can fetch squads and connections for this project
  const { data: squads } = useQuerySquads(project.id) // We need to import or use the existing hook but it expects projectId
  // Wait, `useSquads` is available.
  
  // Also connections for this project
  const { data: connections } = useSquadConnections({ project_id: project.id })

  return (
    <Card className="flex flex-col h-full">
      <CardHeader className="pb-3">
        <div className="flex items-center justify-between">
            <CardTitle className="text-lg font-semibold truncate" title={project.name}>
                {project.name}
            </CardTitle>
            <Badge variant="outline" className="font-mono text-xs">
                {project.path.split('/').pop()}
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
                    {!squads?.length && <div className="text-sm text-muted-foreground italic">No squads deployed</div>}
                </div>
            </div>

            {connections && connections.length > 0 && (
                <div>
                    <h4 className="text-sm font-medium text-muted-foreground mb-2">Active Connections</h4>
                    <div className="space-y-2">
                        {connections.map(conn => (
                            <ConnectionItem key={conn.id} connection={conn} currentProjectId={project.id} />
                        ))}
                    </div>
                </div>
            )}
        </div>
      </CardContent>
    </Card>
  )
}

function ConnectionItem({ connection, currentProjectId }: { connection: SquadConnection, currentProjectId: string }) {
    const { mutate: deleteConnection } = useDeleteSquadConnection()
    
    // Determine direction relative to current project
    const isOutgoing = connection.from_squad?.project_id === currentProjectId
    const otherSquad = isOutgoing ? connection.to_squad : connection.from_squad
    const mySquad = isOutgoing ? connection.from_squad : connection.to_squad
    
    if (!otherSquad || !mySquad) return null

    return (
        <div className="text-xs border rounded-md p-2 flex items-center justify-between group bg-background">
            <div className="flex items-center gap-2 overflow-hidden">
                <Badge variant="outline" className="text-[10px] px-1 h-5 shrink-0">
                    {mySquad.name}
                </Badge>
                <ArrowRight className="w-3 h-3 text-muted-foreground shrink-0" />
                <div className="truncate">
                    <span className="font-medium">{otherSquad.name}</span>
                    {/* Ideally show project name too if we had it easily, but it's not in Squad struct usually unless preloaded deep */}
                </div>
            </div>
            <Button
                variant="ghost"
                size="icon"
                className="h-6 w-6 opacity-0 group-hover:opacity-100 transition-opacity -mr-1"
                onClick={() => deleteConnection(connection.id)}
            >
                <Trash2 className="w-3 h-3 text-destructive" />
            </Button>
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
