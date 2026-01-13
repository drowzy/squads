import { createFileRoute, Link } from '@tanstack/react-router'
import { useActiveProject } from './__root'
import { useFsReview, useSubmitFsReview } from '../api/queries'
import { PatchDiff } from '@pierre/diffs/react'
import { ArrowLeft, FileDiff, AlertCircle, MessageSquare, Trash2 } from 'lucide-react'
import { useMemo, useState } from 'react'

type ReviewCommentType = 'summary' | 'file' | 'line'

type ReviewCommentSide = 'new' | 'old'

type DraftReviewComment = {
  type: ReviewCommentType
  body: string
  file: string
  line: string
  side: ReviewCommentSide
}

function generateCommentId() {
  try {
    return `cmt_${crypto.randomUUID()}`
  } catch {
    return `cmt_${Date.now()}_${Math.random().toString(16).slice(2)}`
  }
}

function buildCommentPayload(draft: DraftReviewComment): Record<string, unknown> | null {
  const body = draft.body.trim()
  if (!body) return null

  const type = draft.type
  const file = draft.file.trim()

  const payload: Record<string, unknown> = {
    id: generateCommentId(),
    created_at: new Date().toISOString(),
    author: 'human',
    type,
    body,
    file: null,
    line: null,
    side: draft.side,
  }

  if (type === 'file') {
    if (!file) return null
    payload.file = file
  }

  if (type === 'line') {
    if (!file) return null

    const lineNumber = Number(draft.line)
    if (!Number.isFinite(lineNumber) || lineNumber < 1) return null

    payload.file = file
    payload.line = Math.floor(lineNumber)
  }

  return payload
}

function formatCommentLabel(comment: any) {
  const type = comment?.type ? String(comment.type) : 'comment'
  const file = comment?.file ? String(comment.file) : ''
  const line = comment?.line != null ? String(comment.line) : ''
  const side = comment?.side ? String(comment.side) : ''

  const loc = file ? (line ? `${file}:${line}${side ? ` (${side})` : ''}` : file) : ''
  return loc ? `${type} • ${loc}` : type
}

const DIFF_VIEW_OPTIONS = { theme: 'catppuccin-mocha' as const }

export const Route = createFileRoute('/fs-reviews/$id')({
  component: FsReviewDetailPage,
})

function FsReviewDetailPage() {
  const { activeProject } = useActiveProject()
  const projectId = activeProject?.id

  const { id } = Route.useParams()
  const { data, isLoading } = useFsReview(projectId, id)
  const submitReview = useSubmitFsReview(projectId)

  const [feedback, setFeedback] = useState('')

  const [draftComment, setDraftComment] = useState<DraftReviewComment>({
    type: 'summary',
    body: '',
    file: '',
    line: '',
    side: 'new',
  })

  const [pendingComments, setPendingComments] = useState<Record<string, unknown>[]>([])

  const review = useMemo(() => (data?.review || {}) as any, [data])
  const diff = data?.diff || ''

  const filesChanged = useMemo(() => {
    const raw = Array.isArray(review.files_changed) ? review.files_changed : []
    return raw
      .map((entry: any) => (entry && typeof entry.path === 'string' ? entry.path : null))
      .filter((path: string | null): path is string => !!path && path.length > 0)
  }, [review])

  const existingComments = useMemo(() => {
    const raw = Array.isArray(review.comments) ? review.comments : []
    return raw.filter(Boolean)
  }, [review])

  const handleSubmit = (status: 'approved' | 'changes_requested') => {
    submitReview.mutate(
      { id, status, feedback, comments: pendingComments },
      {
        onSuccess: () => {
          setFeedback('')
          setPendingComments([])
          setDraftComment((prev) => ({ ...prev, body: '', line: '' }))
        },
      }
    )
  }

  const addPendingComment = () => {
    const payload = buildCommentPayload(draftComment)
    if (!payload) return

    setPendingComments((prev) => [...prev, payload])
    setDraftComment((prev) => ({ ...prev, body: '', line: '' }))
  }

  const removePendingComment = (index: number) => {
    setPendingComments((prev) => prev.filter((_, idx) => idx !== index))
  }

  const quickSetDraftFile = (path: string) => {
    setDraftComment((prev) => ({ ...prev, file: path }))
  }

  const isDraftValid =
    draftComment.body.trim().length > 0 &&
    (draftComment.type === 'summary' || draftComment.file.trim().length > 0) &&
    (draftComment.type !== 'line' || (Number.isFinite(Number(draftComment.line)) && Number(draftComment.line) >= 1))

  return (
    <div className="space-y-6 font-mono">
      <div className="flex items-center justify-between gap-4">
        <div className="min-w-0">
          <div className="flex items-center gap-2 text-xs text-tui-dim">
            <Link
              to="/fs-reviews" as any
              className="inline-flex items-center gap-2 text-tui-accent hover:underline"
            >
              <ArrowLeft size={14} />
              FS Reviews
            </Link>
            <span className="text-tui-dim/60">/</span>
            <span className="truncate">{id}</span>
          </div>
          <h1 className="mt-2 text-xl md:text-2xl font-bold tracking-tight truncate">
            {review.title || 'Filesystem Review'}
          </h1>
          {review.status ? (
            <div className="mt-1 text-[10px] uppercase tracking-widest text-tui-dim">
              Status: <span className="text-tui-text font-bold">{review.status}</span>
            </div>
          ) : null}
        </div>
      </div>

      {isLoading || !data ? (
        <div className="border border-tui-border bg-ctp-mantle/50 p-6 text-tui-dim text-xs">
          Loading review...
        </div>
      ) : (
        <>
          {data.diff_error ? (
            <div className="border border-yellow-500/30 bg-yellow-500/10 p-3 text-xs text-yellow-200 flex items-start gap-2">
              <AlertCircle size={14} className="mt-0.5" />
              <div>
                <div className="font-bold uppercase tracking-widest text-[10px]">Diff Warning</div>
                <div className="mt-1 break-words">{data.diff_error}</div>
              </div>
            </div>
          ) : null}

          <div className="border border-tui-border bg-ctp-mantle/50 p-4 space-y-4">
            {review.summary ? (
              <div>
                <div className="text-[10px] uppercase tracking-widest text-tui-dim font-bold mb-1">Summary</div>
                <div className="text-sm text-tui-text whitespace-pre-wrap">{review.summary}</div>
              </div>
            ) : null}

            {Array.isArray(review.highlights) && review.highlights.length ? (
              <div>
                <div className="text-[10px] uppercase tracking-widest text-tui-dim font-bold mb-1">Highlights</div>
                <ul className="list-disc list-inside text-sm text-tui-text space-y-1">
                  {review.highlights.map((h: string, idx: number) => (
                    <li key={idx}>{h}</li>
                  ))}
                </ul>
              </div>
            ) : null}
          </div>

          {filesChanged.length ? (
            <div className="border border-tui-border bg-ctp-mantle/50 p-4 space-y-2">
              <div className="text-[10px] uppercase tracking-widest text-tui-dim font-bold">Files Changed</div>
              <div className="flex flex-wrap gap-2">
                {filesChanged.map((path) => (
                  <button
                    key={path}
                    type="button"
                    onClick={() => quickSetDraftFile(path)}
                    className="text-[10px] font-mono px-2 py-1 border border-tui-border/40 text-tui-dim hover:text-tui-text hover:bg-tui-dim/5 truncate max-w-full"
                    title={path}
                  >
                    {path}
                  </button>
                ))}
              </div>
              <div className="text-[10px] text-tui-dim/70">Click a file to prefill the comment target.</div>
            </div>
          ) : null}

          <div className="border border-tui-border bg-ctp-mantle/50 p-4 space-y-3">
            <div className="flex items-center justify-between gap-3">
              <div className="text-[10px] uppercase tracking-widest text-tui-dim font-bold flex items-center gap-2">
                <MessageSquare size={14} className="text-tui-accent" />
                Comments
              </div>
              <div className="text-[10px] uppercase tracking-widest text-tui-dim">
                {existingComments.length} existing • {pendingComments.length} pending
              </div>
            </div>

            {existingComments.length ? (
              <div className="space-y-2">
                {existingComments.map((comment: any, idx: number) => (
                  <div
                    key={(comment && comment.id) || `existing-${idx}`}
                    className="border border-tui-border/40 bg-ctp-crust/30 p-3"
                  >
                    <div className="flex items-center justify-between gap-3 text-[10px] uppercase tracking-widest text-tui-dim mb-1">
                      <span className="truncate">{formatCommentLabel(comment)}</span>
                      {comment?.created_at ? (
                        <span className="shrink-0 opacity-70">
                          {new Date(comment.created_at).toLocaleString()}
                        </span>
                      ) : null}
                    </div>
                    <div className="text-sm text-tui-text whitespace-pre-wrap">{String(comment?.body || '')}</div>
                  </div>
                ))}
              </div>
            ) : (
              <div className="text-xs text-tui-dim">No comments yet.</div>
            )}

            <div className="border-t border-tui-border/30 pt-3 space-y-3">
              <div className="text-[10px] uppercase tracking-widest text-tui-dim font-bold">Add Comment</div>

              <div className="flex flex-col sm:flex-row gap-3">
                <label className="flex-1 space-y-1">
                  <div className="text-[10px] uppercase tracking-widest text-tui-dim">Type</div>
                  <select
                    value={draftComment.type}
                    onChange={(e) =>
                      setDraftComment((prev) => ({ ...prev, type: e.target.value as ReviewCommentType }))
                    }
                    className="w-full bg-ctp-crust border border-tui-border-dim px-2 py-2 text-xs outline-none focus:border-tui-accent"
                  >
                    <option value="summary">summary</option>
                    <option value="file">file</option>
                    <option value="line">line</option>
                  </select>
                </label>

                {draftComment.type !== 'summary' ? (
                  <label className="flex-[2] space-y-1">
                    <div className="text-[10px] uppercase tracking-widest text-tui-dim">File</div>
                    <input
                      value={draftComment.file}
                      onChange={(e) => setDraftComment((prev) => ({ ...prev, file: e.target.value }))}
                      placeholder="path/to/file.ts"
                      className="w-full bg-ctp-crust border border-tui-border-dim px-2 py-2 text-xs outline-none focus:border-tui-accent font-mono"
                    />
                  </label>
                ) : null}

                {draftComment.type === 'line' ? (
                  <label className="w-32 space-y-1">
                    <div className="text-[10px] uppercase tracking-widest text-tui-dim">Line</div>
                    <input
                      value={draftComment.line}
                      onChange={(e) => setDraftComment((prev) => ({ ...prev, line: e.target.value }))}
                      placeholder="123"
                      inputMode="numeric"
                      className="w-full bg-ctp-crust border border-tui-border-dim px-2 py-2 text-xs outline-none focus:border-tui-accent font-mono"
                    />
                  </label>
                ) : null}

                {draftComment.type === 'line' ? (
                  <label className="w-28 space-y-1">
                    <div className="text-[10px] uppercase tracking-widest text-tui-dim">Side</div>
                    <select
                      value={draftComment.side}
                      onChange={(e) =>
                        setDraftComment((prev) => ({ ...prev, side: e.target.value as ReviewCommentSide }))
                      }
                      className="w-full bg-ctp-crust border border-tui-border-dim px-2 py-2 text-xs outline-none focus:border-tui-accent"
                    >
                      <option value="new">new</option>
                      <option value="old">old</option>
                    </select>
                  </label>
                ) : null}
              </div>

              {filesChanged.length > 0 && draftComment.type !== 'summary' ? (
                <div className="flex flex-wrap gap-2">
                  {filesChanged.slice(0, 10).map((path) => (
                    <button
                      key={`chip-${path}`}
                      type="button"
                      onClick={() => quickSetDraftFile(path)}
                      className="text-[10px] px-2 py-1 border border-tui-border/40 text-tui-dim hover:text-tui-text hover:bg-tui-dim/5"
                    >
                      {path}
                    </button>
                  ))}
                </div>
              ) : null}

              <label className="space-y-1">
                <div className="text-[10px] uppercase tracking-widest text-tui-dim">Body</div>
                <textarea
                  value={draftComment.body}
                  onChange={(e) => setDraftComment((prev) => ({ ...prev, body: e.target.value }))}
                  placeholder="Write your comment..."
                  className="w-full min-h-[90px] bg-ctp-crust border border-tui-border-dim p-3 text-sm focus:border-tui-accent outline-none font-mono resize-none placeholder:text-tui-dim/30"
                />
              </label>

              <div className="flex items-center justify-between gap-3">
                <button
                  type="button"
                  onClick={addPendingComment}
                  disabled={!isDraftValid}
                  className="border border-tui-accent/40 text-tui-accent bg-tui-accent/10 px-3 py-2 text-xs font-bold hover:bg-tui-accent hover:text-tui-bg disabled:opacity-50 disabled:hover:bg-tui-accent/10 disabled:hover:text-tui-accent"
                >
                  Add Comment
                </button>
                <div className="text-[10px] uppercase tracking-widest text-tui-dim">
                  Pending: {pendingComments.length}
                </div>
              </div>

              {pendingComments.length ? (
                <div className="space-y-2">
                  {pendingComments.map((comment: any, idx: number) => (
                    <div
                      key={(comment && comment.id) || `pending-${idx}`}
                      className="border border-tui-border/40 bg-ctp-crust/30 p-3 flex items-start justify-between gap-3"
                    >
                      <div className="min-w-0">
                        <div className="text-[10px] uppercase tracking-widest text-tui-dim mb-1 truncate">
                          {formatCommentLabel(comment)}
                        </div>
                        <div className="text-sm text-tui-text whitespace-pre-wrap">{String(comment?.body || '')}</div>
                      </div>
                      <button
                        type="button"
                        onClick={() => removePendingComment(idx)}
                        className="shrink-0 border border-tui-border/40 text-tui-dim hover:text-ctp-red hover:border-ctp-red/40 px-2 py-2"
                        title="Remove"
                      >
                        <Trash2 size={14} />
                      </button>
                    </div>
                  ))}
                </div>
              ) : null}
            </div>
          </div>

          <div className="border border-tui-border bg-ctp-crust/40 overflow-hidden">
            <div className="px-4 py-2 border-b border-tui-border/40 flex items-center gap-2 text-xs font-bold text-tui-accent">
              <FileDiff size={14} />
              Diff
            </div>
            <div className="p-4 overflow-x-auto">
              {diff.trim() ? (
                <PatchDiff patch={diff} options={DIFF_VIEW_OPTIONS} />
              ) : (
                <div className="text-xs text-tui-dim italic">No diff available.</div>
              )}
            </div>
          </div>

          <div className="border border-tui-border bg-ctp-mantle/50 p-4 space-y-3">
            <div className="text-[10px] uppercase tracking-widest text-tui-dim font-bold">Submit</div>
            <textarea
              value={feedback}
              onChange={(e) => setFeedback(e.target.value)}
              placeholder="Enter feedback..."
              className="w-full min-h-[120px] bg-ctp-crust border border-tui-border-dim p-3 text-sm focus:border-tui-accent outline-none font-mono resize-none placeholder:text-tui-dim/30"
            />
            <div className="flex flex-col sm:flex-row gap-3">
              <button
                onClick={() => handleSubmit('approved')}
                disabled={submitReview.isPending}
                className="flex-1 border border-ctp-green bg-ctp-green/10 text-ctp-green py-3 text-xs font-bold hover:bg-ctp-green hover:text-ctp-base disabled:opacity-50"
              >
                {submitReview.isPending ? 'Submitting…' : 'Approve'}
              </button>
              <button
                onClick={() => handleSubmit('changes_requested')}
                disabled={submitReview.isPending}
                className="flex-1 border border-ctp-red bg-ctp-red/10 text-ctp-red py-3 text-xs font-bold hover:bg-ctp-red hover:text-ctp-base disabled:opacity-50"
              >
                {submitReview.isPending ? 'Submitting…' : 'Request Changes'}
              </button>
            </div>
          </div>
        </>
      )}
    </div>
  )
}
