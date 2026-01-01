import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { fetcher } from './client'

// --- Types ---

export interface Project {
  id: string
  name: string
  path: string
  config?: Record<string, unknown>
  inserted_at: string
  updated_at: string
}

export interface DirectoryEntry {
  name: string
  path: string
  has_children: boolean
  is_git_repo: boolean
}

export interface BrowseResult {
  current_path: string
  parent_path: string
  directories: DirectoryEntry[]
}

export interface Agent {
  id: string
  name: string
  slug: string
  model: string | null
  role: string
  level: 'junior' | 'senior' | 'principal'
  system_instruction: string | null
  status: 'idle' | 'working' | 'blocked' | 'offline'
  squad_id: string
  mentor_id: string | null
  inserted_at: string
  updated_at: string
}

export interface ModelOption {
  id: string
  model_id: string
  name: string
  provider_id: string
  provider_name: string
}

export interface AgentRoleDefinition {
  id: string
  label: string
  description: string
}

export interface AgentLevelDefinition {
  id: 'junior' | 'senior' | 'principal'
  label: string
  description: string
}

export interface AgentRolesConfig {
  roles: AgentRoleDefinition[]
  levels: AgentLevelDefinition[]
  defaults: { role: string; level: AgentLevelDefinition['id'] }
  system_instructions: Record<string, Record<string, string>>
}

export interface Squad {
  id: string
  name: string
  description: string | null
  project_id: string
  agents?: Agent[]
  inserted_at: string
  updated_at: string
}

export interface Session {
  id: string
  project_id: string
  agent_id: string
  status: string
  model: string
  inserted_at: string
}

export interface Event {
  id: string
  kind: string
  payload: any
  occurred_at: string
  project_id: string
  session_id?: string
  agent_id?: string
}

export interface Ticket {
  id: string
  title: string
  description: string
  status: 'open' | 'in_progress' | 'closed' | 'blocked'
  priority: number
  issue_type: string
  created_at: string
  updated_at: string
  assignee?: string
  parent_id?: string
  dependencies?: string[]
}

export interface MailMessage {
  id: string
  subject: string
  body_md: string
  sender_name: string
  to: string[]
  cc?: string[]
  inserted_at: string
  thread_id: string
  importance: 'low' | 'normal' | 'high' | 'urgent'
  ack_required: boolean
}

export interface MailThread {
  id: string
  subject: string
  last_message_at: string
  participants: string[]
  message_count: number
  unread_count: number
}

export interface Review {
  id: string
  title: string
  summary: string
  diff: string
  status: 'pending' | 'approved' | 'changes_requested' | 'merged'
  author_name: string
  project_id: string
  inserted_at: string
}

// --- Queries ---

export function useProjects() {
  return useQuery({
    queryKey: ['projects'],
    queryFn: () => fetcher<Project[]>('/projects'),
  })
}

export function useProject(id: string) {
  return useQuery({
    queryKey: ['projects', id],
    queryFn: () => fetcher<Project>(`/projects/${id}`),
    enabled: !!id,
  })
}

export function useBrowseDirectories(path: string) {
  return useQuery({
    queryKey: ['browse', path],
    queryFn: () => fetcher<BrowseResult>(`/projects/browse?path=${encodeURIComponent(path)}`),
  })
}

export function useSquads(projectId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'squads'],
    queryFn: () => fetcher<Squad[]>(`/projects/${projectId}/squads`),
    enabled: !!projectId,
  })
}

export function useAgentRolesConfig() {
  return useQuery({
    queryKey: ['agents', 'roles'],
    queryFn: () => fetcher<AgentRolesConfig>('/agents/roles'),
  })
}

export function useModels(projectId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'models'],
    queryFn: () => fetcher<ModelOption[]>(`/projects/${projectId}/models`),
    enabled: !!projectId,
  })
}

export function useSyncProviders() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { project_id: string }) =>
      fetcher<unknown>(`/projects/${data.project_id}/providers/sync`, {
        method: 'POST',
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['projects', variables.project_id, 'models'] })
    },
  })
}

export function useSessions() {
  return useQuery({
    queryKey: ['sessions'],
    queryFn: () => fetcher<Session[]>('/sessions'),
  })
}

export function useTickets(projectId?: string) {
  return useQuery({
    queryKey: projectId ? ['projects', projectId, 'tickets'] : ['tickets'],
    queryFn: () => {
      const url = projectId ? `/projects/${projectId}/board` : '/board'
      return fetcher<Ticket[]>(url)
    },
    enabled: true,
  })
}

export function useMailThreads(projectId?: string) {
  return useQuery({
    queryKey: projectId ? ['projects', projectId, 'mail', 'threads'] : ['mail', 'threads'],
    queryFn: () => {
      const url = projectId ? `/projects/${projectId}/mail/threads` : '/mail/threads'
      return fetcher<MailThread[]>(url)
    },
    enabled: true,
  })
}

export function useMailThread(id: string) {
  return useQuery({
    queryKey: ['mail', 'threads', id],
    queryFn: () => fetcher<MailMessage[]>(`/mail/threads/${id}`),
    enabled: !!id,
  })
}

export function useSendMessage(projectId?: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { subject: string; body_md: string; to: string[]; project_id?: string }) => {
      const actualProjectId = data.project_id || projectId
      const url = actualProjectId ? `/projects/${actualProjectId}/mail/send` : '/mail/send'
      return fetcher<MailMessage>(url, {
        method: 'POST',
        body: JSON.stringify(data),
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mail'] })
    },
  })
}

export function useReplyMessage() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { thread_id: string; body_md: string; project_id?: string }) => {
      const url = data.project_id 
        ? `/projects/${data.project_id}/mail/threads/${data.thread_id}/reply`
        : `/mail/threads/${data.thread_id}/reply`
      return fetcher<MailMessage>(url, {
        method: 'POST',
        body: JSON.stringify({ body_md: data.body_md }),
      })
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['mail', 'threads', variables.thread_id] })
      queryClient.invalidateQueries({ queryKey: ['mail', 'threads'] })
    },
  })
}

export function useEvents(params: { project_id?: string; session_id?: string; agent_id?: string; limit?: number }) {
  const queryKey = ['events', params]
  return useQuery({
    queryKey,
    queryFn: () => {
      const searchParams = new URLSearchParams()
      if (params.project_id) searchParams.append('project_id', params.project_id)
      if (params.session_id) searchParams.append('session_id', params.session_id)
      if (params.agent_id) searchParams.append('agent_id', params.agent_id)
      if (params.limit) searchParams.append('limit', params.limit.toString())
      return fetcher<Event[]>(`/events?${searchParams.toString()}`)
    },
  })
}

export function useSession(id: string) {
  return useQuery({
    queryKey: ['sessions', id],
    queryFn: () => fetcher<Session>(`/sessions/${id}`),
    enabled: !!id,
  })
}

export function useReviews() {
  return useQuery({
    queryKey: ['reviews'],
    queryFn: () => fetcher<Review[]>('/reviews'),
  })
}

export function useReview(id: string) {
  return useQuery({
    queryKey: ['reviews', id],
    queryFn: () => fetcher<Review>(`/reviews/${id}`),
    enabled: !!id,
  })
}

// --- Mutations ---

export function useCreateSession() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { project_id: string; agent_id: string; model: string }) =>
      fetcher<Session>('/sessions', {
        method: 'POST',
        body: JSON.stringify(data),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['sessions'] })
    },
  })
}

export function useStopSession() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { session_id: string }) =>
      fetcher<void>('/sessions/stop', {
        method: 'POST',
        body: JSON.stringify(data),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['sessions'] })
      queryClient.invalidateQueries({ queryKey: ['agents'] })
      queryClient.invalidateQueries({ queryKey: ['projects'] })
    },
  })
}

export function useUpdateTicket(projectId?: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { id: string; status: Ticket['status']; assignee?: string; project_id?: string }) => {
      const actualProjectId = data.project_id || projectId
      const url = actualProjectId 
        ? `/projects/${actualProjectId}/board/tickets/${data.id}`
        : `/board/tickets/${data.id}`
      return fetcher<Ticket>(url, {
        method: 'PATCH',
        body: JSON.stringify(data),
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tickets'] })
    },
  })
}

export function useSubmitReview() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { id: string; status: 'approved' | 'changes_requested' | 'merged'; feedback?: string }) =>
      fetcher<Review>(`/reviews/${data.id}/submit`, {
        method: 'POST',
        body: JSON.stringify(data),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['reviews'] })
      queryClient.invalidateQueries({ queryKey: ['tickets'] })
    },
  })
}

// --- Project Mutations ---

export function useCreateProject() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { path: string; name: string; config?: Record<string, unknown> }) =>
      fetcher<Project>('/projects', {
        method: 'POST',
        body: JSON.stringify(data),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['projects'] })
    },
  })
}

// --- Squad Mutations ---

export function useSquad(id: string) {
  return useQuery({
    queryKey: ['squads', id],
    queryFn: () => fetcher<Squad>(`/squads/${id}`),
    enabled: !!id,
  })
}

export function useCreateSquad() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { project_id: string; name: string; description?: string }) =>
      fetcher<Squad>(`/projects/${data.project_id}/squads`, {
        method: 'POST',
        body: JSON.stringify(data),
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['projects', variables.project_id, 'squads'] })
    },
  })
}

export function useUpdateSquad() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { id: string; name?: string; description?: string }) =>
      fetcher<Squad>(`/squads/${data.id}`, {
        method: 'PATCH',
        body: JSON.stringify(data),
      }),
    onSuccess: (squad) => {
      queryClient.invalidateQueries({ queryKey: ['squads', squad.id] })
      queryClient.invalidateQueries({ queryKey: ['projects', squad.project_id, 'squads'] })
    },
  })
}

export function useDeleteSquad() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { id: string; project_id: string }) =>
      fetcher<void>(`/squads/${data.id}`, {
        method: 'DELETE',
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['projects', variables.project_id, 'squads'] })
    },
  })
}

// --- Agent Queries ---


export function useAgents(projectId?: string) {
  return useQuery({
    queryKey: projectId ? ['projects', projectId, 'agents'] : ['agents'],
    queryFn: () => {
      const url = projectId ? `/projects/${projectId}/agents` : '/agents'
      return fetcher<Agent[]>(url)
    },
    enabled: !!projectId,
  })
}


// --- Agent Mutations ---

export function useCreateAgent() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: {
      squad_id: string
      model?: string
      role?: string
      level?: Agent['level']
      system_instruction?: string
      name?: string
      slug?: string
    }) =>
      fetcher<Agent>(`/squads/${data.squad_id}/agents`, {
        method: 'POST',
        body: JSON.stringify(data),
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['squads', variables.squad_id, 'agents'] })
      // Also invalidate the squads list since agents are often preloaded
      queryClient.invalidateQueries({ queryKey: ['projects'] })
    },
  })
}

export function useUpdateAgent() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: {
      id: string
      squad_id: string
      model?: string
      role?: string
      level?: Agent['level']
      system_instruction?: string
      status?: Agent['status']
      mentor_id?: string
    }) =>
      fetcher<Agent>(`/agents/${data.id}`, {
        method: 'PATCH',
        body: JSON.stringify(data),
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['squads', variables.squad_id, 'agents'] })
      queryClient.invalidateQueries({ queryKey: ['projects'] })
    },
  })
}

export function useDeleteAgent() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { id: string; squad_id: string }) =>
      fetcher<void>(`/agents/${data.id}`, {
        method: 'DELETE',
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['squads', variables.squad_id, 'agents'] })
      queryClient.invalidateQueries({ queryKey: ['projects'] })
    },
  })
}

export function useUpdateAgentStatus() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { id: string; squad_id: string; status: Agent['status'] }) =>
      fetcher<Agent>(`/agents/${data.id}/status`, {
        method: 'PATCH',
        body: JSON.stringify({ status: data.status }),
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['squads', variables.squad_id, 'agents'] })
      queryClient.invalidateQueries({ queryKey: ['projects'] })
    },
  })
}
