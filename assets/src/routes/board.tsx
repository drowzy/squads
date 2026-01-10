import { createFileRoute, Link } from '@tanstack/react-router'
import {
  AlertCircle,
  CheckCircle2,
  ClipboardList,
  FileText,
  Hammer,
  Loader2,
  MessageSquare,
  RefreshCw,
  ShieldCheck,
  User,
} from 'lucide-react'
import { useMemo, useState, type ReactNode } from 'react'
import {
  type BoardCard,
  type BoardLane,
  type BoardLaneAssignment,
  type Squad,
  useAssignBoardLane,
  useBoard,
  useCreateBoardCard,
  useCreateBoardCardIssues,
  useCreateBoardCardPr,
  useMoveBoardCard,
  useSetBoardCardPrUrl,
  useSyncBoardCardArtifacts,
} from '../api/queries'
import { useActiveProject } from './__root'
import { Modal } from '../components/Modal'
import { SessionChatFlyout } from '../components/SessionChatFlyout'

export const Route = createFileRoute('/board')({
  component: BoardPage,
})

type LaneConfig = {
  lane: BoardLane
  label: string
  icon: ReactNode
  color: string
}

const LANES: LaneConfig[] = [
  { lane: 'todo', label: 'TODO', icon: <ClipboardList size={16} />, color: 'text-ctp-blue' },
  { lane: 'plan', label: 'PLAN', icon: <FileText size={16} />, color: 'text-ctp-mauve' },
  { lane: 'build', label: 'BUILD', icon: <Hammer size={16} />, color: 'text-ctp-peach' },
  { lane: 'review', label: 'REVIEW', icon: <ShieldCheck size={16} />, color: 'text-ctp-green' },
  { lane: 'done', label: 'DONE', icon: <CheckCircle2 size={16} />, color: 'text-ctp-teal' },
]

function BoardPage() {
  const { activeProject } = useActiveProject()
  const projectId = activeProject?.id

  const { data, isLoading, error } = useBoard(projectId)

  const createCard = useCreateBoardCard(projectId)
  const assignLane = useAssignBoardLane(projectId)
  const moveCard = useMoveBoardCard(projectId)
  const syncArtifacts = useSyncBoardCardArtifacts(projectId)
  const createIssues = useCreateBoardCardIssues(projectId)
  const createPr = useCreateBoardCardPr()
  const setPrUrl = useSetBoardCardPrUrl(projectId)

  const [chatSessionId, setChatSessionId] = useState<string | null>(null)
  const [composerBySquad, setComposerBySquad] = useState<Record<string, string>>({})
  const [prUrlByCard, setPrUrlByCard] = useState<Record<string, string>>({})
  const [selectedCardId, setSelectedCardId] = useState<string | null>(null)

  const squads = data?.squads || []
  const cards = data?.cards || []
  const assignments = data?.lane_assignments || []

  const selectedCard = useMemo(() => {
    if (!selectedCardId) return null
    return cards.find((c) => c.id === selectedCardId) || null
  }, [cards, selectedCardId])

  const selectedSessionId = useMemo(() => {
    if (!selectedCard) return null
    const lane = selectedCard.lane
    return lane === 'plan'
      ? selectedCard.plan_session_id
      : lane === 'build'
        ? selectedCard.build_session_id
        : lane === 'review'
          ? selectedCard.review_session_id
          : null
  }, [selectedCard])

  const selectedNextLane: BoardLane | null = useMemo(() => {
    if (!selectedCard) return null
    const lane = selectedCard.lane
    return lane === 'todo' ? 'plan' : lane === 'plan' ? 'build' : lane === 'build' ? 'review' : null
  }, [selectedCard])

  const selectedIssues = selectedCard?.issue_refs?.issues || []

  const cardsBySquad = useMemo(() => {
    const map = new Map<string, BoardCard[]>()
    for (const card of cards) {
      const arr = map.get(card.squad_id) || []
      arr.push(card)
      map.set(card.squad_id, arr)
    }
    return map
  }, [cards])

  const assignmentsByKey = useMemo(() => {
    const key = (a: Pick<BoardLaneAssignment, 'squad_id' | 'lane'>) => `${a.squad_id}:${a.lane}`
    const map = new Map<string, BoardLaneAssignment>()
    for (const a of assignments) map.set(key(a), a)
    return map
  }, [assignments])

  if (!projectId) {
    return (
      <div className="h-full flex items-center justify-center text-tui-dim">
        Select a project to view the board.
      </div>
    )
  }

  if (isLoading) {
    return (
      <div className="h-full flex items-center justify-center">
        <Loader2 className="animate-spin text-tui-accent" size={32} />
      </div>
    )
  }

  if (error) {
    return (
      <div className="h-full flex flex-col items-center justify-center text-tui-accent">
        <AlertCircle size={48} className="mb-4" />
        <h3 className="text-xl font-bold">Failed to load board</h3>
        <p className="text-sm opacity-70">{error instanceof Error ? error.message : 'Check backend connection'}</p>
      </div>
    )
  }

  return (
    <div className="h-full flex flex-col space-y-4 md:space-y-6">
      <div className="flex flex-col gap-2">
        <div>
          <h2 className="text-xl md:text-2xl font-bold tracking-tighter uppercase">Board</h2>
          <p className="text-tui-dim text-xs md:text-sm italic">
            Build requests flow through TODO → PLAN → BUILD → REVIEW.
          </p>
        </div>

        {squads.length === 0 && (
          <div className="border border-tui-border bg-ctp-mantle/50 p-6">
            <div className="text-xs font-bold uppercase tracking-tui text-tui-dim">No squads yet</div>
            <p className="text-[11px] text-tui-dim/70 mt-2">
              Create a squad to unlock a board section.
            </p>
            <div className="mt-4">
              <Link
                to="/squad"
                className="inline-flex items-center gap-2 px-3 py-2 border border-tui-accent text-tui-accent text-xs font-bold uppercase tracking-tui hover:bg-tui-accent hover:text-tui-bg transition-colors"
              >
                <User size={14} />
                Manage squads
              </Link>
            </div>
          </div>
        )}
      </div>

      <div className="flex-1 min-h-0 space-y-6 overflow-y-auto custom-scrollbar pb-6">
        {squads.map((squad) => (
          <SquadSection
            key={squad.id}
            squad={squad}
            cards={cardsBySquad.get(squad.id) || []}
            assignmentsByKey={assignmentsByKey}
            composerValue={composerBySquad[squad.id] || ''}
            onComposerChange={(value) =>
              setComposerBySquad((prev) => ({
                ...prev,
                [squad.id]: value,
              }))
            }
            onCreateCard={() => {
              const body = (composerBySquad[squad.id] || '').trim()
              if (!body) return

              createCard.mutate(
                { squad_id: squad.id, body },
                {
                  onSuccess: () => {
                    setComposerBySquad((prev) => ({ ...prev, [squad.id]: '' }))
                  },
                }
              )
            }}
            onAssignLane={(lane, agentId) => {
              assignLane.mutate({ squad_id: squad.id, lane, agent_id: agentId })
            }}
            onMoveCard={(cardId, lane) => moveCard.mutate({ id: cardId, lane })}
            onOpenChat={(sessionId) => setChatSessionId(sessionId)}
            onOpenCard={(cardId) => setSelectedCardId(cardId)}
            onSync={(cardId) => syncArtifacts.mutate(cardId)}
            onCreateIssues={(cardId) => createIssues.mutate(cardId)}
            onCreatePr={(cardId) => createPr.mutate(cardId)}
            prUrlByCard={prUrlByCard}
            onPrUrlChange={(cardId, value) => setPrUrlByCard((prev) => ({ ...prev, [cardId]: value }))}
            onSetPrUrl={(cardId) => {
              const value = (prUrlByCard[cardId] || '').trim()
              if (!value) return
              setPrUrl.mutate(
                { id: cardId, pr_url: value },
                {
                  onSuccess: () => setPrUrlByCard((prev) => ({ ...prev, [cardId]: '' })),
                }
              )
            }}
          />
        ))}
      </div>

      <Modal
        isOpen={!!selectedCardId}
        onClose={() => setSelectedCardId(null)}
        title={selectedCard ? selectedCard.title || 'Untitled' : 'Card details'}
        size="lg"
      >
        {selectedCard ? (
          <div className="space-y-4">
            <div className="text-[10px] uppercase tracking-tui text-tui-dim font-bold">
              Lane: {selectedCard.lane.toUpperCase()}
            </div>

            <div>
              <div className="text-[10px] uppercase tracking-tui text-tui-dim font-bold">Body</div>
              <div className="mt-2 text-xs whitespace-pre-wrap font-mono">{selectedCard.body}</div>
            </div>

            {selectedCard.prd_path && (
              <div className="text-xs">
                <span className="text-tui-dim uppercase tracking-tui font-bold">PRD:</span>{' '}
                <span className="font-mono text-tui-accent">{selectedCard.prd_path}</span>
              </div>
            )}

            {selectedIssues.length > 0 && (
              <div>
                <div className="text-[10px] uppercase tracking-tui text-tui-dim font-bold">GitHub issues</div>
                <div className="mt-2 space-y-1">
                  {selectedIssues.map((iss) => (
                    <a
                      key={`${iss.repo}#${iss.number}`}
                      href={iss.url}
                      target="_blank"
                      rel="noreferrer"
                      className="block text-xs font-mono text-tui-accent hover:underline"
                      title={iss.title}
                    >
                      {iss.repo}#{iss.number}
                      <span className="ml-2 text-[10px] text-tui-dim">
                        {iss.github_state || '—'} / {iss.soft_state || 'open'}
                      </span>
                    </a>
                  ))}
                </div>
              </div>
            )}

            {selectedCard.pr_url && (
              <div className="text-xs">
                <span className="text-tui-dim uppercase tracking-tui font-bold">PR:</span>{' '}
                <a
                  className="font-mono text-tui-accent hover:underline"
                  href={selectedCard.pr_url}
                  target="_blank"
                  rel="noreferrer"
                >
                  {selectedCard.pr_url}
                </a>
              </div>
            )}

            {selectedCard.ai_review && (
              <div className="border border-tui-border bg-ctp-crust/40 p-2">
                <div className="text-[10px] uppercase tracking-tui text-tui-dim font-bold">AI review</div>
                <div className="text-xs text-tui-dim/80 mt-1 whitespace-pre-wrap">
                  {(selectedCard.ai_review as any).summary || JSON.stringify(selectedCard.ai_review)}
                </div>
              </div>
            )}

            {(selectedCard.human_review_status || selectedCard.human_review_feedback) && (
              <div className="border border-tui-border bg-ctp-crust/40 p-2">
                <div className="text-[10px] uppercase tracking-tui text-tui-dim font-bold">Human review</div>
                {selectedCard.human_review_status && (
                  <div className="text-xs text-tui-dim/80 mt-1">
                    Status: <span className="font-mono">{selectedCard.human_review_status}</span>
                  </div>
                )}
                {selectedCard.human_review_feedback && (
                  <div className="text-xs text-tui-dim/80 mt-2 whitespace-pre-wrap">{selectedCard.human_review_feedback}</div>
                )}
              </div>
            )}

            {selectedCard.lane === 'build' && (
              <div className="flex gap-2">
                <input
                  value={prUrlByCard[selectedCard.id] || ''}
                  onChange={(e) => setPrUrlByCard((prev) => ({ ...prev, [selectedCard.id]: e.target.value }))}
                  placeholder="Set PR URL (triggers soft-close)"
                  className="flex-1 bg-ctp-crust border border-tui-border-dim p-2 text-xs outline-none focus:border-tui-accent font-mono"
                />
                <button
                  onClick={() => {
                    const value = (prUrlByCard[selectedCard.id] || '').trim()
                    if (!value) return
                    setPrUrl.mutate(
                      { id: selectedCard.id, pr_url: value },
                      { onSuccess: () => setPrUrlByCard((prev) => ({ ...prev, [selectedCard.id]: '' })) }
                    )
                  }}
                  className="px-3 py-2 border border-tui-accent text-tui-accent text-[10px] uppercase font-bold hover:bg-tui-accent hover:text-tui-bg transition-colors"
                >
                  Set
                </button>
              </div>
            )}

            <div className="flex flex-wrap gap-2 pt-2 border-t border-tui-border">
              {selectedSessionId && (
                <button
                  onClick={() => {
                    setChatSessionId(selectedSessionId)
                    setSelectedCardId(null)
                  }}
                  className="inline-flex items-center gap-1 px-2 py-1 border border-tui-border text-tui-dim text-[10px] uppercase font-bold hover:border-tui-accent hover:text-tui-accent transition-colors"
                >
                  <MessageSquare size={12} />
                  Chat
                </button>
              )}

              {(selectedCard.lane === 'plan' || selectedCard.lane === 'build' || selectedCard.lane === 'review') && (
                <button
                  onClick={() => syncArtifacts.mutate(selectedCard.id)}
                  className="inline-flex items-center gap-1 px-2 py-1 border border-tui-border text-tui-dim text-[10px] uppercase font-bold hover:border-tui-accent hover:text-tui-accent transition-colors"
                >
                  <RefreshCw size={12} />
                  Sync
                </button>
              )}

              {selectedCard.lane === 'plan' && (
                <button
                  onClick={() => createIssues.mutate(selectedCard.id)}
                  className="inline-flex items-center gap-1 px-2 py-1 border border-tui-border text-tui-dim text-[10px] uppercase font-bold hover:border-tui-accent hover:text-tui-accent transition-colors"
                >
                  Create issues
                </button>
              )}

              {selectedCard.lane === 'build' && (
                <button
                  onClick={() => createPr.mutate(selectedCard.id)}
                  className="inline-flex items-center gap-1 px-2 py-1 border border-tui-border text-tui-dim text-[10px] uppercase font-bold hover:border-tui-accent hover:text-tui-accent transition-colors"
                >
                  Create PR
                </button>
              )}

              {selectedNextLane && (
                <button
                  onClick={() => moveCard.mutate({ id: selectedCard.id, lane: selectedNextLane })}
                  className="inline-flex items-center gap-1 px-2 py-1 border border-tui-accent text-tui-accent text-[10px] uppercase font-bold hover:bg-tui-accent hover:text-tui-bg transition-colors"
                >
                  Move to {selectedNextLane.toUpperCase()}
                </button>
              )}
            </div>
          </div>
        ) : (
          <div className="text-sm text-tui-dim">Card not found.</div>
        )}
      </Modal>

      {chatSessionId && (
        <SessionChatFlyout
          sessionId={chatSessionId}
          open={!!chatSessionId}
          onOpenChange={(open) => {
            if (!open) setChatSessionId(null)
          }}
        />
      )}
    </div>
  )
}

function SquadSection(props: {
  squad: Squad
  cards: BoardCard[]
  assignmentsByKey: Map<string, BoardLaneAssignment>
  composerValue: string
  onComposerChange: (value: string) => void
  onCreateCard: () => void
  onAssignLane: (lane: BoardLane, agentId: string | null) => void
  onMoveCard: (cardId: string, lane: BoardLane) => void
  onOpenChat: (sessionId: string) => void
  onOpenCard: (cardId: string) => void
  onSync: (cardId: string) => void
  onCreateIssues: (cardId: string) => void
  onCreatePr: (cardId: string) => void
  prUrlByCard: Record<string, string>
  onPrUrlChange: (cardId: string, value: string) => void
  onSetPrUrl: (cardId: string) => void
}) {
  const { squad, cards } = props

  const cardsByLane = useMemo(() => {
    const map = new Map<BoardLane, BoardCard[]>()
    for (const lane of LANES.map((l) => l.lane)) map.set(lane, [])
    for (const card of cards) {
      const list = map.get(card.lane) || []
      list.push(card)
      map.set(card.lane, list)
    }
    for (const lane of map.keys()) {
      map.set(
        lane,
        (map.get(lane) || []).slice().sort((a, b) => (a.position || 0) - (b.position || 0))
      )
    }
    return map
  }, [cards])

  return (
    <section className="border border-tui-border bg-ctp-mantle/50">
      <div className="p-3 border-b border-tui-border flex items-center justify-between">
        <div className="flex items-center gap-2">
          <span className="text-xs font-bold uppercase tracking-tui text-tui-dim">Squad</span>
          <span className="text-sm font-bold">{squad.name}</span>
        </div>
        <div className="text-xs text-tui-dim">{cards.length} cards</div>
      </div>

      <div className="p-3 border-b border-tui-border bg-ctp-crust/40">
        <div className="flex flex-col md:flex-row gap-3">
          <textarea
            value={props.composerValue}
            onChange={(e) => props.onComposerChange(e.target.value)}
            placeholder="What do you want to build?"
            className="flex-1 bg-ctp-crust border border-tui-border-dim p-3 text-xs md:text-sm outline-none focus:border-tui-accent font-mono min-h-[80px]"
          />
          <button
            onClick={props.onCreateCard}
            className="px-4 py-2 bg-tui-accent text-tui-bg text-xs font-bold uppercase tracking-tui hover:bg-tui-accent/90 transition-colors"
          >
            Add to TODO
          </button>
        </div>
      </div>

      <div className="p-3">
        <div className="grid grid-cols-1 md:grid-cols-5 gap-4">
          {LANES.map((lane) => (
            <LaneColumn
              key={`${squad.id}:${lane.lane}`}
              lane={lane}
              squad={squad}
              cards={cardsByLane.get(lane.lane) || []}
              assignment={props.assignmentsByKey.get(`${squad.id}:${lane.lane}`)}
              onAssign={(agentId) => props.onAssignLane(lane.lane, agentId)}
              onMoveCard={props.onMoveCard}
              onOpenChat={props.onOpenChat}
              onOpenCard={props.onOpenCard}
              onSync={props.onSync}
              onCreateIssues={props.onCreateIssues}
              onCreatePr={props.onCreatePr}
              prUrlByCard={props.prUrlByCard}
              onPrUrlChange={props.onPrUrlChange}
              onSetPrUrl={props.onSetPrUrl}
            />
          ))}
        </div>
      </div>
    </section>
  )
}

function LaneColumn(props: {
  lane: LaneConfig
  squad: Squad
  cards: BoardCard[]
  assignment?: BoardLaneAssignment
  onAssign: (agentId: string | null) => void
  onMoveCard: (cardId: string, lane: BoardLane) => void
  onOpenChat: (sessionId: string) => void
  onOpenCard: (cardId: string) => void
  onSync: (cardId: string) => void
  onCreateIssues: (cardId: string) => void
  onCreatePr: (cardId: string) => void
  prUrlByCard: Record<string, string>
  onPrUrlChange: (cardId: string, value: string) => void
  onSetPrUrl: (cardId: string) => void
}) {
  const { lane, squad, cards, assignment } = props
  const agents = squad.agents || []

  return (
    <div className="flex flex-col border border-tui-border bg-ctp-mantle/60 min-h-[280px]">
      <div className={`p-3 border-b border-tui-border flex items-center justify-between bg-ctp-mantle ${lane.color}`}>
        <div className="flex items-center gap-2">
          {lane.icon}
          <span className="font-bold tracking-widest text-xs uppercase">{lane.label}</span>
        </div>
        <span className="text-xs bg-ctp-surface0 px-1.5 py-0.5 rounded font-mono text-ctp-text">{cards.length}</span>
      </div>

      {lane.lane !== 'done' ? (
        <div className="p-3 border-b border-tui-border bg-ctp-crust/40">
          <label className="block text-[10px] uppercase tracking-tui text-tui-dim font-bold mb-1">
            Assigned agent
          </label>
          <select
            value={assignment?.agent_id || ''}
            onChange={(e) => props.onAssign(e.target.value || null)}
            className="w-full bg-ctp-crust border border-tui-border-dim p-2 text-xs outline-none focus:border-tui-accent"
          >
            <option value="">Unassigned</option>
            {agents.map((a) => (
              <option key={a.id} value={a.id}>
                {a.name} ({a.slug})
              </option>
            ))}
          </select>
        </div>
      ) : (
        <div className="p-3 border-b border-tui-border bg-ctp-crust/40">
          <div className="text-[10px] uppercase tracking-tui text-tui-dim font-bold">Done lane</div>
          <div className="mt-1 text-xs text-tui-dim/70">
            Cards enter DONE only after approval in <Link to="/review" className="text-tui-accent hover:underline">/review</Link>.
          </div>
        </div>
      )}

      <div className="flex-1 p-3 space-y-3 overflow-y-auto custom-scrollbar">
        {cards.map((card) => (
          <BoardCardItem
            key={card.id}
            card={card}
            lane={lane.lane}
            onMove={props.onMoveCard}
            onOpenChat={props.onOpenChat}
            onOpenDetails={() => props.onOpenCard(card.id)}
            onSync={props.onSync}
            onCreateIssues={props.onCreateIssues}
            onCreatePr={props.onCreatePr}
            prUrlValue={props.prUrlByCard[card.id] || ''}
            onPrUrlChange={(value) => props.onPrUrlChange(card.id, value)}
            onSetPrUrl={() => props.onSetPrUrl(card.id)}
          />
        ))}
        {cards.length === 0 && (
          <div className="h-16 flex items-center justify-center border border-dashed border-tui-border/30 opacity-20">
            <span className="text-xs uppercase italic tracking-tui">Empty</span>
          </div>
        )}
      </div>
    </div>
  )
}

function BoardCardItem(props: {
  card: BoardCard
  lane: BoardLane
  onMove: (cardId: string, lane: BoardLane) => void
  onOpenChat: (sessionId: string) => void
  onOpenDetails: () => void
  onSync: (cardId: string) => void
  onCreateIssues: (cardId: string) => void
  onCreatePr: (cardId: string) => void
  prUrlValue: string
  onPrUrlChange: (value: string) => void
  onSetPrUrl: () => void
}) {
  const { card, lane } = props

  const issues = card.issue_refs?.issues || []

  const nextLane: BoardLane | null =
    lane === 'todo' ? 'plan' : lane === 'plan' ? 'build' : lane === 'build' ? 'review' : null

  const sessionId = lane === 'plan' ? card.plan_session_id : lane === 'build' ? card.build_session_id : lane === 'review' ? card.review_session_id : null

  return (
    <div
      role="button"
      tabIndex={0}
      onClick={props.onOpenDetails}
      onKeyDown={(e) => {
        if (e.key === 'Enter' || e.key === ' ') {
          e.preventDefault()
          props.onOpenDetails()
        }
      }}
      className="border border-tui-border p-3 bg-ctp-mantle/50 hover:border-tui-accent transition-colors cursor-pointer focus:outline-none focus:border-tui-accent"
    >
      <div className="flex items-start justify-between gap-2">
        <div className="min-w-0">
          <div className="text-xs font-bold text-tui-dim truncate">{card.title || 'Untitled'}</div>
          <div className="text-[11px] text-tui-dim/70 mt-1 whitespace-pre-wrap line-clamp-3">{card.body}</div>
        </div>
        {sessionId && (
          <button
            onClick={(e) => {
              e.stopPropagation()
              props.onOpenChat(sessionId)
            }}
            className="shrink-0 inline-flex items-center gap-1 px-2 py-1 border border-tui-border text-tui-dim text-[10px] uppercase font-bold hover:border-tui-accent hover:text-tui-accent transition-colors"
          >
            <MessageSquare size={12} />
            Chat
          </button>
        )}
      </div>

      {card.prd_path && (
        <div className="mt-3 text-[11px]">
          <span className="text-tui-dim uppercase tracking-tui font-bold">PRD:</span>{' '}
          <span className="font-mono text-tui-accent">{card.prd_path}</span>
        </div>
      )}

      {issues.length > 0 && (
        <div className="mt-3 space-y-1">
          <div className="text-[10px] uppercase tracking-tui text-tui-dim font-bold">Issues</div>
          {issues.slice(0, 6).map((iss) => (
            <a
              key={`${iss.repo}#${iss.number}`}
              href={iss.url}
              target="_blank"
              rel="noreferrer"
              onClick={(e) => e.stopPropagation()}
              className="block text-[11px] font-mono text-tui-accent hover:underline"
              title={iss.title}
            >
              {iss.repo}#{iss.number}
              <span className="ml-2 text-[10px] text-tui-dim">
                {iss.github_state || '—'} / {iss.soft_state || 'open'}
              </span>
            </a>
          ))}
          {issues.length > 6 && (
            <div className="text-[10px] text-tui-dim">+{issues.length - 6} more…</div>
          )}
        </div>
      )}

      {card.pr_url && (
        <div className="mt-3 text-[11px]">
          <span className="text-tui-dim uppercase tracking-tui font-bold">PR:</span>{' '}
          <a
            className="font-mono text-tui-accent hover:underline"
            href={card.pr_url}
            target="_blank"
            rel="noreferrer"
            onClick={(e) => e.stopPropagation()}
          >
            {card.pr_url}
          </a>
        </div>
      )}

      {lane === 'build' && (
        <div className="mt-3 flex gap-2">
          <input
            value={props.prUrlValue}
            onClick={(e) => e.stopPropagation()}
            onChange={(e) => props.onPrUrlChange(e.target.value)}
            placeholder="Set PR URL (triggers soft-close)"
            className="flex-1 bg-ctp-crust border border-tui-border-dim p-2 text-[11px] outline-none focus:border-tui-accent font-mono"
          />
          <button
            onClick={(e) => {
              e.stopPropagation()
              props.onSetPrUrl()
            }}
            className="px-3 py-2 border border-tui-accent text-tui-accent text-[10px] uppercase font-bold hover:bg-tui-accent hover:text-tui-bg transition-colors"
          >
            Set
          </button>
        </div>
      )}

      {lane === 'review' && card.ai_review && (
        <div className="mt-3 border border-tui-border bg-ctp-crust/40 p-2">
          <div className="text-[10px] uppercase tracking-tui text-tui-dim font-bold">AI review</div>
          <div className="text-[11px] text-tui-dim/80 mt-1 whitespace-pre-wrap">
            {(card.ai_review as any).summary || JSON.stringify(card.ai_review)}
          </div>
        </div>
      )}

      <div className="mt-3 flex flex-wrap gap-2">
        {(lane === 'plan' || lane === 'build' || lane === 'review') && (
          <button
            onClick={(e) => {
              e.stopPropagation()
              props.onSync(card.id)
            }}
            className="inline-flex items-center gap-1 px-2 py-1 border border-tui-border text-tui-dim text-[10px] uppercase font-bold hover:border-tui-accent hover:text-tui-accent transition-colors"
          >
            <RefreshCw size={12} />
            Sync
          </button>
        )}

        {lane === 'plan' && (
          <button
            onClick={(e) => {
              e.stopPropagation()
              props.onCreateIssues(card.id)
            }}
            className="inline-flex items-center gap-1 px-2 py-1 border border-tui-border text-tui-dim text-[10px] uppercase font-bold hover:border-tui-accent hover:text-tui-accent transition-colors"
          >
            Create issues
          </button>
        )}

        {lane === 'build' && (
          <button
            onClick={(e) => {
              e.stopPropagation()
              props.onCreatePr(card.id)
            }}
            className="inline-flex items-center gap-1 px-2 py-1 border border-tui-border text-tui-dim text-[10px] uppercase font-bold hover:border-tui-accent hover:text-tui-accent transition-colors"
          >
            Create PR
          </button>
        )}

        {nextLane && (
          <button
            onClick={(e) => {
              e.stopPropagation()
              props.onMove(card.id, nextLane)
            }}
            className="inline-flex items-center gap-1 px-2 py-1 border border-tui-accent text-tui-accent text-[10px] uppercase font-bold hover:bg-tui-accent hover:text-tui-bg transition-colors"
          >
            Move to {nextLane.toUpperCase()}
          </button>
        )}
      </div>
    </div>
  )
}
