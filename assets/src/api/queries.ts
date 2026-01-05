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
  project_name?: string
  opencode_status?: 'idle' | 'provisioning' | 'running' | 'error'
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

export interface ExternalNode {
  base_url: string
  healthy: boolean
  version?: string
  source: 'local_lsof' | 'config' | 'manual'
  last_seen_at: string
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
  recipients?: {
    agent_id: string
    recipient_type: string
    read_at?: string
    acknowledged_at?: string
  }[]
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

export interface SquadConnection {
  id: string
  from_squad_id: string
  to_squad_id: string
  status: 'pending' | 'active' | 'disabled'
  notes?: string
  inserted_at: string
  from_squad?: Squad
  to_squad?: Squad
}

export interface McpServer {
  id: string
  squad_id: string
  name: string
  source: 'builtin' | 'registry' | 'custom'
  type: 'remote' | 'container'
  image?: string | null
  url?: string | null
  command?: string | null
  args?: Record<string, unknown>
  headers?: Record<string, unknown>
  enabled: boolean
  status: string
  last_error?: string | null
  catalog_meta?: Record<string, unknown>
  tools?: Record<string, unknown>
  inserted_at: string
  updated_at: string
}

export interface McpCatalogEntry {
  name: string
  title?: string
  icon?: string
  category?: string
  tags?: string[]
  image?: string
  secrets?: unknown[]
  oauth?: unknown[]
  run_env?: Record<string, unknown>
  source?: Record<string, unknown>
  tools?: unknown[]
  raw?: Record<string, unknown>
}

export interface McpCliStatus {
  available: boolean
  message?: string
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
    refetchInterval: (query) => {
      const data = query.state.data as Squad[] | undefined
      if (data?.some((squad) => squad.opencode_status === 'provisioning')) {
        return 2000
      }
      return false
    },
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

export function useSessions(params?: { project_id?: string; agent_id?: string; status?: string }) {
  const queryKey = params ? ['sessions', params] : ['sessions']
  return useQuery({
    queryKey,
    queryFn: () => {
      const searchParams = new URLSearchParams()
      if (params?.project_id) searchParams.append('project_id', params.project_id)
      if (params?.agent_id) searchParams.append('agent_id', params.agent_id)
      if (params?.status && params.status !== 'all') searchParams.append('status', params.status)
      const url = searchParams.toString() ? `/sessions?${searchParams.toString()}` : '/sessions'
      return fetcher<Session[]>(url)
    },
  })
}

export function useSquadConnections(params?: { project_id?: string; squad_id?: string }) {
  const queryKey = params ? ['fleet', 'connections', params] : ['fleet', 'connections']
  return useQuery({
    queryKey,
    queryFn: () => {
      const searchParams = new URLSearchParams()
      if (params?.project_id) searchParams.append('project_id', params.project_id)
      if (params?.squad_id) searchParams.append('squad_id', params.squad_id)
      const url = searchParams.toString() ? `/fleet/connections?${searchParams.toString()}` : '/fleet/connections'
      return fetcher<SquadConnection[]>(url)
    },
  })
}

// --- MCP Queries ---

export function useMcpServers(squadId: string) {
  return useQuery({
    queryKey: ['mcp', 'servers', squadId],
    queryFn: () => fetcher<McpServer[]>(`/mcp?squad_id=${squadId}`),
    enabled: !!squadId,
  })
}

export function useMcpCatalog(filters?: { query?: string; category?: string; tag?: string }) {
  const queryKey = filters ? ['mcp', 'catalog', filters] : ['mcp', 'catalog']

  return useQuery({
    queryKey,
    queryFn: () => {
      const searchParams = new URLSearchParams()
      if (filters?.query) searchParams.append('query', filters.query)
      if (filters?.category) searchParams.append('category', filters.category)
      if (filters?.tag) searchParams.append('tag', filters.tag)
      const url = searchParams.toString() ? `/mcp/catalog?${searchParams.toString()}` : '/mcp/catalog'
      return fetcher<McpCatalogEntry[]>(url)
    },
  })
}

export function useMcpCliStatus() {
  return useQuery({
    queryKey: ['mcp', 'cli'],
    queryFn: () => fetcher<McpCliStatus>('/mcp/cli'),
    staleTime: 30000,
  })
}

// --- Mutations ---

export function useCreateSquadConnection() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { from_squad_id: string; to_squad_id: string; notes?: string }) =>
      fetcher<SquadConnection>('/fleet/connections', {
        method: 'POST',
        body: JSON.stringify({ squad_connection: data }),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['fleet', 'connections'] })
    },
  })
}

export function useDeleteSquadConnection() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: string) =>
      fetcher<void>(`/fleet/connections/${id}`, {
        method: 'DELETE',
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['fleet', 'connections'] })
    },
  })
}

export function useMessageSquad() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { from_squad_id: string; to_squad_id: string; subject: string; body: string; sender_name?: string }) =>
      fetcher<{ id: string; subject: string; recipient_count: number }>(`/squads/${data.from_squad_id}/message`, {
        method: 'POST',
        body: JSON.stringify({
          to_squad_id: data.to_squad_id,
          subject: data.subject,
          body: data.body,
          sender_name: data.sender_name,
        }),
      }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['mail'] })
    },
  })
}

export function useProjectFiles(projectId: string) {
  return useQuery({
    queryKey: ['projects', projectId, 'files'],
    queryFn: () => fetcher<{ files: string[] }>(`/projects/${projectId}/files`),
    enabled: !!projectId,
    staleTime: 60000, // Cache for 1 minute
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
    onSuccess: (_result, variables) => {
      const actualProjectId = variables.project_id || projectId
      if (actualProjectId) {
        queryClient.invalidateQueries({ queryKey: ['projects', actualProjectId, 'mail'] })
      }
      queryClient.invalidateQueries({ queryKey: ['mail'] })
    },
  })
}

export function useReplyMessage(projectId?: string) {
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
      const actualProjectId = variables.project_id || projectId
      queryClient.invalidateQueries({ queryKey: ['mail', 'threads', variables.thread_id] })
      if (actualProjectId) {
        queryClient.invalidateQueries({ queryKey: ['projects', actualProjectId, 'mail'] })
      }
      queryClient.invalidateQueries({ queryKey: ['mail'] })
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

export function useExternalNodes() {
  return useQuery({
    queryKey: ['external-nodes'],
    queryFn: () => fetcher<ExternalNode[]>('/external_nodes'),
    refetchInterval: 30000, // Refresh every 30 seconds
  })
}

export function useProbeExternalNode() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (url: string) => fetcher<ExternalNode>('/external_nodes/probe', {
      method: 'POST',
      body: JSON.stringify({ url }),
    }),
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['external-nodes'] })
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

export function useSessionTodos(sessionId: string) {
  return useQuery({
    queryKey: ['sessions', sessionId, 'todos'],
    queryFn: () => fetcher<any[]>(`/sessions/${sessionId}/todos`),
    enabled: !!sessionId,
  })
}

export function useSessionDiff(sessionId: string) {
  return useQuery({
    queryKey: ['sessions', sessionId, 'diff'],
    queryFn: () => fetcher<string>(`/sessions/${sessionId}/diff`),
    enabled: !!sessionId,
  })
}

export function useSendSessionPrompt() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: async (data: { session_id: string; prompt: string; model?: string; agent?: string; no_reply?: boolean }) => {
      const { session_id, ...payload } = data
      // TODO(opencode-squads-gfh): Switch back to /prompt_async once async flow is stable.
      // Use sync endpoint for easier request/response debugging.
      await fetcher<void>(`/sessions/${session_id}/prompt`, {
        method: 'POST',
        body: JSON.stringify(payload),
      })
      return { ok: true }
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['sessions', variables.session_id, 'messages'] })
    },
  })
}

export function useExecuteSessionCommand() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { session_id: string; command: string; arguments?: string; agent?: string; model?: string }) => {
      const { session_id, ...payload } = data
      return fetcher<{ ok?: boolean; output?: string }>(`/sessions/${session_id}/command`, {
        method: 'POST',
        body: JSON.stringify(payload),
      })
    },
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['sessions', variables.session_id, 'messages'] })
    },
  })
}

export function useRunSessionShell() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { session_id: string; command: string; agent?: string; model?: string }) => {
      const { session_id, ...payload } = data
      return fetcher<{ ok?: boolean; output?: string }>(`/sessions/${session_id}/shell`, {
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

export function useNewSession() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: {
      agent_id: string
      ticket_key?: string
      title?: string
      worktree_path?: string
      branch?: string
      metadata?: Record<string, unknown>
    }) => {
      const { agent_id, ...payload } = data
      return fetcher<Session>(`/agents/${agent_id}/sessions/new`, {
        method: 'POST',
        body: JSON.stringify(payload),
      })
    },
    onSuccess: () => {
      queryClient.invalidateQueries({ queryKey: ['sessions'] })
      queryClient.invalidateQueries({ queryKey: ['agents'] })
    },
  })
}

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
    mutationFn: (data: { session_id: string; reason?: string }) =>
      fetcher<void>(`/sessions/${data.session_id}/stop`, {
        method: 'POST',
        body: data.reason ? JSON.stringify({ reason: data.reason }) : undefined,
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['sessions'] })
      queryClient.invalidateQueries({ queryKey: ['sessions', variables.session_id] })
      queryClient.invalidateQueries({ queryKey: ['agents'] })
      queryClient.invalidateQueries({ queryKey: ['projects'] })
    },
  })
}

export function useAbortSession() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { session_id: string }) =>
      fetcher<void>(`/sessions/${data.session_id}/abort`, {
        method: 'POST',
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['sessions', variables.session_id] })
      queryClient.invalidateQueries({ queryKey: ['sessions', variables.session_id, 'messages'] })
    },
  })
}

export function useArchiveSession() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { session_id: string }) =>
      fetcher<Session>(`/sessions/${data.session_id}/archive`, {
        method: 'POST',
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['sessions'] })
      queryClient.invalidateQueries({ queryKey: ['sessions', variables.session_id] })
    },
  })
}

const invalidateTicketQueries = (queryClient: ReturnType<typeof useQueryClient>, projectId?: string) => {
  if (projectId) {
    queryClient.invalidateQueries({ queryKey: ['projects', projectId, 'tickets'] })
    return
  }
  queryClient.invalidateQueries({
    predicate: (query) => {
      const key = query.queryKey
      return Array.isArray(key) && key[0] === 'projects' && key[2] === 'tickets'
    },
  })
}

export function useUpdateTicketStatus(projectId?: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { id: string; status: Ticket['status']; project_id?: string }) =>
      fetcher<Ticket>(`/tickets/${data.id}/status`, {
        method: 'PATCH',
        body: JSON.stringify({ status: data.status }),
      }),
    onSuccess: (_, variables) => {
      const actualProjectId = variables.project_id || projectId
      invalidateTicketQueries(queryClient, actualProjectId)
    },
  })
}

export function useClaimTicket(projectId?: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { id: string; agent_id: string; agent_name?: string; project_id?: string }) =>
      fetcher<Ticket>(`/tickets/${data.id}/claim`, {
        method: 'POST',
        body: JSON.stringify({ agent_id: data.agent_id, agent_name: data.agent_name }),
      }),
    onSuccess: (_, variables) => {
      const actualProjectId = variables.project_id || projectId
      invalidateTicketQueries(queryClient, actualProjectId)
    },
  })
}

export function useUnclaimTicket(projectId?: string) {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { id: string; project_id?: string }) =>
      fetcher<Ticket>(`/tickets/${data.id}/unclaim`, {
        method: 'POST',
      }),
    onSuccess: (_, variables) => {
      const actualProjectId = variables.project_id || projectId
      invalidateTicketQueries(queryClient, actualProjectId)
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
      invalidateTicketQueries(queryClient, variables.project_id)
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
      invalidateTicketQueries(queryClient)
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

export function useDeleteProject() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (id: string) =>
      fetcher<void>(`/projects/${id}`, {
        method: 'DELETE',
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

// --- MCP Mutations ---

export function useCreateMcpServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: {
      squad_id: string
      name: string
      source: McpServer['source']
      type: McpServer['type']
      image?: string
      url?: string
      command?: string
      args?: Record<string, unknown>
      headers?: Record<string, unknown>
      catalog_meta?: Record<string, unknown>
    }) =>
      fetcher<McpServer>(`/mcp?squad_id=${data.squad_id}`, {
        method: 'POST',
        body: JSON.stringify(data),
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['mcp', 'servers', variables.squad_id] })
    },
  })
}

export function useUpdateMcpServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: {
      squad_id: string
      name: string
      image?: string
      url?: string
      command?: string
      args?: Record<string, unknown>
      headers?: Record<string, unknown>
      enabled?: boolean
      status?: string
      last_error?: string | null
      catalog_meta?: Record<string, unknown>
    }) =>
      fetcher<McpServer>(`/mcp/${encodeURIComponent(data.name)}?squad_id=${data.squad_id}`, {
        method: 'PATCH',
        body: JSON.stringify(data),
      }),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['mcp', 'servers', variables.squad_id] })
    },
  })
}

export function useEnableMcpServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { squad_id: string; name: string }) =>
      fetcher<McpServer>(
        `/mcp/${encodeURIComponent(data.name)}/connect?squad_id=${data.squad_id}`,
        {
          method: 'POST',
        }
      ),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['mcp', 'servers', variables.squad_id] })
    },
  })
}

export function useDisableMcpServer() {
  const queryClient = useQueryClient()
  return useMutation({
    mutationFn: (data: { squad_id: string; name: string }) =>
      fetcher<McpServer>(
        `/mcp/${encodeURIComponent(data.name)}/disconnect?squad_id=${data.squad_id}`,
        {
          method: 'POST',
        }
      ),
    onSuccess: (_, variables) => {
      queryClient.invalidateQueries({ queryKey: ['mcp', 'servers', variables.squad_id] })
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
