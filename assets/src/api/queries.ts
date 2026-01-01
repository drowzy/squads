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
  context_window?: number
  max_output?: number
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
  ticket_key?: string
  worktree_path?: string
  branch?: string
  started_at?: string
  finished_at?: string
  metadata?: Record<string, unknown>
}

export interface SessionMessageInfo {
  id: string
  role: string
  time?: { created?: number; completed?: number }
  agent?: string
  model?: { providerID?: string; modelID?: string } | string
  providerID?: string
  modelID?: string
  mode?: string
  finish?: string
  summary?: boolean | { title?: string; body?: string }
  error?: string | { message?: string; type?: string }
  cost?: number
  tokens?: {
    input: number
    output: number
    reasoning: number
    cache: { read: number; write: number }
  }
}

export interface SessionMessagePartBase {
  id?: string
  type?: string
}

export interface SessionMessageTextPart extends SessionMessagePartBase {
  type: 'text'
  text: string
  ignored?: boolean
  synthetic?: boolean
}

export interface SessionMessageReasoningPart extends SessionMessagePartBase {
  type: 'reasoning'
  text: string
}

export interface SessionMessageToolPart extends SessionMessagePartBase {
  type: 'tool'
  tool?: string
  callID?: string
  state?: {
    status?: string
    title?: string
    input?: Record<string, unknown>
    output?: string
    error?: string
    metadata?: Record<string, unknown>
  }
}

export interface SessionMessageStepPart extends SessionMessagePartBase {
  type: 'step-start' | 'step-finish'
  reason?: string
  cost?: number
  tokens?: {
    input: number
    output: number
    reasoning: number
    cache: { read: number; write: number }
  }
}

export interface SessionMessageFilePart extends SessionMessagePartBase {
  type: 'file'
  filename?: string
  mime?: string
  url?: string
}

export interface SessionMessagePatchPart extends SessionMessagePartBase {
  type: 'patch'
  hash?: string
  files?: string[]
}

export interface SessionMessageMetaPart extends SessionMessagePartBase {
  type: 'snapshot' | 'compaction' | 'agent' | 'retry' | 'subtask'
  name?: string
  description?: string
  prompt?: string
  attempt?: number
  error?: { message?: string } | string
  auto?: boolean
  snapshot?: string
}

export type SessionMessagePart =
  | SessionMessageTextPart
  | SessionMessageReasoningPart
  | SessionMessageToolPart
  | SessionMessageStepPart
  | SessionMessageFilePart
  | SessionMessagePatchPart
  | SessionMessageMetaPart
  | SessionMessagePartBase

export interface SessionMessageEntry {
  info: SessionMessageInfo
  parts: SessionMessagePart[]
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
  assignee?: string // Deprecated, mapped from assignee_name
  assignee_name?: string
  assignee_id?: string
  parent_id?: string
  dependencies?: string[]
}

export interface BoardSummary {
  ready: Ticket[]
  in_progress: Ticket[]
  blocked: Ticket[]
  closed: Ticket[]
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
      // If we don't have a projectId, we can't load the board yet
      // This prevents the global /api/board 400 error by not calling it
      if (!projectId) return [] as Ticket[]

      const url = `/projects/${projectId}/board`
      return fetcher<BoardSummary | Ticket[]>(url).then(res => {
          // Flatten the board structure into a list of tickets for the frontend to consume
          if (res && typeof res === 'object' && !Array.isArray(res)) {
            const summary = res as BoardSummary
              return [
                  ...(summary.ready || []),
                  ...(summary.in_progress || []),
                  ...(summary.blocked || []),
                  ...(summary.closed || [])
              ]
          }
          return (res as Ticket[]) || []
      })
    },
    enabled: !!projectId,
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
    mutationFn: (data: { subject: string; body_md: string; to: string[]; sender_name: string; project_id?: string }) => {
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

export function useSessionMessages(
  sessionId: string,
  options?: { limit?: number; enabled?: boolean; refetchInterval?: number | false }
) {
  const limit = options?.limit ?? 50
  return useQuery({
    queryKey: ['sessions', sessionId, 'messages', limit],
    queryFn: () => fetcher<SessionMessageEntry[]>(`/sessions/${sessionId}/messages?limit=${limit}`),
    enabled: options?.enabled ?? !!sessionId,
    refetchInterval: options?.refetchInterval,
  })
}

export function useSendSessionPrompt() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { session_id: string; prompt: string; model?: string; agent?: string; no_reply?: boolean }) => {
      const { session_id, ...payload } = data
      return fetcher<{ ok?: boolean }>(`/sessions/${session_id}/prompt`, {
        method: 'POST',
        body: JSON.stringify(payload),
      })
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['sessions', variables.session_id, 'messages'] })
    },
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
    mutationFn: (data: {
      agent_id: string
      ticket_key?: string
      title?: string
      worktree_path?: string
      branch?: string
      metadata?: Record<string, unknown>
    }) =>
      fetcher<Session>('/sessions/start', {
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
      const url = `/tickets/${data.id}`
      // We use the status endpoint for status updates and claim/unclaim for assignments
      // But for simplicity in this hook, we'll assume we can patch properties or use specific endpoints
      // Let's stick to status updates for now or assume a generic update if available
      
      // If we're updating status:
      if (data.status) {
         return fetcher<Ticket>(`${url}/status`, {
          method: 'PATCH',
          body: JSON.stringify({ status: data.status }),
        })
      }
      
      // If we're updating assignee (claiming):
      if (data.assignee) {
        return fetcher<Ticket>(`${url}/claim`, {
          method: 'POST',
          body: JSON.stringify({ agent_id: 'current-user-or-agent', agent_name: data.assignee }),
        })
      }
      
       // Fallback to a generic patch if we had one, but we don't seem to expose a generic update on TicketController
       // So we might need to rely on the specific actions.
       throw new Error("Update not fully supported via single endpoint yet")
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['tickets'] })
    },
  })
}

export function useCreateTicket() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { project_id: string; title: string; issue_type?: string; priority?: number; parent_beads_id?: string }) =>
      fetcher<Ticket>(`/projects/${data.project_id}/tickets`, {
        method: 'POST',
        body: JSON.stringify(data),
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['projects', variables.project_id, 'tickets'] })
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
