import { createFileRoute, Link } from '@tanstack/react-router'
import { 
  GitPullRequest, 
  FileText, 
  CheckSquare, 
  XSquare, 
  MessageSquare,
  Clock,
  ExternalLink,
  AlertCircle,
  ChevronRight,
  User,
  Hash,
  Send,
  Plus,
  Navigation,
  ChevronUp,
  ChevronDown,
  ArrowLeft,
  ShieldCheck,
  Search
} from 'lucide-react'
import { useState, useMemo, useEffect, useRef } from 'react'
import { useReviews, useReview, useSubmitReview, Review } from '../api/queries'
import { useActiveProject } from './__root'
import { PatchDiff } from '@pierre/diffs/react'

const DIFF_VIEW_OPTIONS = { theme: 'catppuccin-mocha' as const }

export const Route = createFileRoute('/review')({
  component: ReviewQueue,
})

function ReviewQueue() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [feedback, setFeedback] = useState('')
  const scrollContainerRef = useRef<HTMLDivElement>(null)
  
  const { activeProject } = useActiveProject()
  const projectId = activeProject?.id

  const { data: reviews = [], isLoading } = useReviews(projectId)
  const { data: selectedReviewDetail } = useReview(selectedId || '')
  const submitReview = useSubmitReview()

  const selectedReview = useMemo(() => 
    selectedReviewDetail || reviews.find(r => r.id === selectedId) || null,
    [selectedReviewDetail, reviews, selectedId])

  const diffText = selectedReview?.diff ?? ''

  const fileDiffs = useMemo(() => {
    if (!diffText) return []

    const diffs = diffText.split(/^diff --git /gm).filter(Boolean)

    return diffs.map((diff) => {
      const match = diff.match(/^a\/(.+?)\s+b\/(.+)$/m)
      const path = match ? (match[2] || match[1]) : 'unknown'

      return {
        path,
        patch: diff.trim()
      }
    })
  }, [diffText])

  const diffFiles = useMemo(() => {
    return fileDiffs.map((d) => d.path)
  }, [fileDiffs])

  const diffStats = useMemo(() => {
    if (!diffText) return { files: 0, additions: 0, deletions: 0 }

    let files = 0
    let additions = 0
    let deletions = 0

    for (const line of diffText.split('\n')) {
      if (line.startsWith('diff --git ')) files += 1
      if (line.startsWith('+') && !line.startsWith('+++')) additions += 1
      if (line.startsWith('-') && !line.startsWith('---')) deletions += 1
    }

    return { files, additions, deletions }
  }, [diffText])

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && selectedId) {
        setSelectedId(null)
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [selectedId])

  const scrollToSection = (id: string) => {
    const el = document.getElementById(id)
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' })
    }
  }

  const handleAction = (status: 'approved' | 'changes_requested') => {
    if (!selectedId) return

    submitReview.mutate({ id: selectedId, status, feedback }, {
      onSuccess: () => {
        setSelectedId(null)
        setFeedback('')
      }
    })
  }

  if (isLoading) {
    return (
        <div className="h-full flex flex-col items-center justify-center space-y-4">
          <div className="w-12 h-12 border-4 border-tui-accent border-t-transparent animate-spin" />
          <div className="text-tui-accent font-mono text-sm animate-pulse">
            Accessing secure vault...
          </div>
        </div>
    )
  }

  return (
    <div className="h-full flex flex-col space-y-4 md:space-y-6 font-mono">
      <div className="flex flex-col sm:flex-row justify-between items-start sm:items-end gap-4">
        <div>
          <h2 className="text-xl md:text-2xl font-bold tracking-tighter flex items-center gap-3">
            <CheckSquare className="text-tui-accent" size={20} />
            Review Queue
          </h2>
          <p className="text-tui-dim text-xs md:text-sm italic">Verification required for agent-generated deployments</p>
        </div>
        <div className="text-xs text-tui-dim bg-ctp-crust/40 px-2 py-1 border border-tui-border">
          Queue: {reviews.length} pending
        </div>
      </div>

      <div className="flex-1 flex flex-col lg:grid lg:grid-cols-12 gap-4 md:gap-6 min-h-0">
        {/* Master: Review List - Full width on mobile, side panel on desktop */}
        <div className={`${selectedId ? 'hidden lg:flex' : 'flex'} lg:col-span-4 border border-tui-border flex-col bg-ctp-mantle/50 overflow-hidden`}>
          <div className="p-3 border-b border-tui-border bg-ctp-crust/40 flex items-center justify-between">
            <div className="flex items-center gap-2 text-xs font-bold text-tui-dim">
              <Hash size={12} />
               Review registry
            </div>
          </div>
          <div className="flex-1 overflow-y-auto custom-scrollbar">
            {reviews.length === 0 ? (
              <div className="h-full flex flex-col items-center justify-center p-8 text-center space-y-4">
                <div className="relative">
                  <ShieldCheck size={48} className="text-tui-dim/20" />
                  <div className="absolute inset-0 border border-tui-dim/10 rounded-full scale-150 animate-pulse" />
                </div>
                 <div className="space-y-2">
                    <h3 className="text-sm font-bold text-tui-dim">No pending reviews</h3>
                   <p className="text-[10px] text-tui-dim/60 italic max-w-[200px] leading-relaxed">
                     System integrity verified. All agent deployments have been processed.
                   </p>
                 </div>
                 <div className="pt-4 space-y-3">
                   <div className="inline-flex items-center gap-2 px-3 py-1 border border-tui-dim/20 text-[9px] text-tui-dim animate-pulse">
                     <div className="w-1.5 h-1.5 bg-green-500 rounded-full" />
                      Registry clean
                   </div>
                   <div className="flex flex-col items-center gap-2">
                     <Link
                       to="/sessions"
                       className="px-3 py-1 border border-tui-accent text-tui-accent text-[9px] font-bold hover:bg-tui-accent hover:text-tui-bg transition-colors"
                     >
                        View sessions
                     </Link>
                    <span className="text-[9px] text-tui-dim/60">
                      Reviews appear after agents submit changes.
                    </span>
                  </div>
                </div>
              </div>
            ) : (
              reviews.map((review) => (
                <button 
                  key={review.id}
                  onClick={() => {
                    setSelectedId(review.id)
                    setFeedback('')
                  }}
                  className={`w-full text-left p-4 border-b border-tui-border/50 transition-all relative group ${
                    selectedId === review.id ? 'bg-tui-accent/10' : 'hover:bg-tui-dim/5'
                  }`}
                >
                  {selectedId === review.id && (
                    <div className="absolute left-0 top-0 bottom-0 w-1 bg-tui-accent" />
                  )}
                   <div className="flex justify-between items-start mb-2">
                    <span className={`text-xs font-bold px-1 ${
                      selectedId === review.id ? 'text-tui-accent' : 'text-tui-dim group-hover:text-tui-text'
                    }`}>
                      {review.id}
                    </span>
                    <div className="flex items-center gap-1 text-xs text-tui-dim">
                      <Clock size={12} />
                      {new Date(review.inserted_at).toLocaleTimeString()}
                    </div>
                  </div>
                  <h4 className="font-bold text-sm mb-3 group-hover:text-tui-accent transition-colors truncate">
                    {review.title}
                  </h4>
                  <div className="flex items-center justify-between">
                    <div className="flex items-center gap-2 text-xs text-tui-dim font-bold">
                      <User size={12} />
                      {review.author_name}
                    </div>
                    <span className={`text-xs px-1.5 py-0.5 font-bold ${
                      review.status === 'pending' 
                        ? 'bg-yellow-500/20 text-yellow-500 border border-yellow-500/30' 
                        : 'bg-tui-text/10 text-tui-text border border-tui-border'
                    }`}>
                      {review.status.charAt(0).toUpperCase() + review.status.slice(1)}
                    </span>
                  </div>
                </button>
              ))
            )}
          </div>
        </div>

        {/* Detail: Inspector - Full screen on mobile when selected */}
        <div className={`${selectedId ? 'flex' : 'hidden lg:flex'} lg:col-span-8 border border-tui-border flex-col bg-ctp-mantle/50 relative shadow-inner overflow-hidden flex-1`}>
          {selectedReview ? (
            <>
              {/* Detail Header */}
              <div className="p-3 md:p-4 border-b border-tui-border flex flex-col sm:flex-row justify-between items-start gap-3 bg-tui-accent/5 shrink-0">
                <div className="space-y-1 min-w-0 flex-1">
                    <div className="flex items-center gap-2">
                      {/* Mobile back button */}
                      <button 
                        aria-label="Back to queue"
                        onClick={() => setSelectedId(null)}
                        className="lg:hidden p-1 -ml-1 text-tui-accent"
                      >
                        <ArrowLeft size={20} />
                      </button>
                      <span className="text-xs text-tui-accent font-bold px-1 border border-tui-accent hidden sm:inline">PR</span>
                      <h3 className="text-base md:text-lg font-bold tracking-tight leading-none truncate">{selectedReview.title}</h3>
                    </div>
                    <div className="flex items-center gap-4 ml-0 lg:ml-0">
                      <span className="text-xs text-tui-dim font-bold flex items-center gap-1">
                        <User size={12} className="text-tui-accent/50" />
                        {selectedReview.author_name}
                      </span>
                      <span className="text-xs text-tui-dim font-bold hidden sm:flex items-center gap-1">
                        <Hash size={12} className="text-tui-accent/50" />
                        {selectedReview.id}
                      </span>
                    </div>
                </div>
                  <button 
                   aria-label="Checkout branch"
                   className="text-xs font-bold text-tui-accent border border-tui-accent/30 px-3 py-1.5 hover:bg-tui-accent hover:text-tui-bg transition-all flex items-center gap-2 shrink-0"
                 >

                  <ExternalLink size={12} />
                  <span className="hidden sm:inline">Checkout</span>
                </button>
              </div>
              
              <div ref={scrollContainerRef} className="flex-1 overflow-y-auto custom-scrollbar p-0">
                {/* Summary Section */}
                <div className="p-4 md:p-6 space-y-6 md:space-y-8">
                  <section id="review-summary">
                    <div className="flex items-center justify-between mb-4 mt-2">
                      <div className="flex items-center gap-2 text-xs font-bold text-tui-accent">
                        <FileText size={14} />
                        Submission log
                      </div>
                      <div className="h-[2px] flex-1 bg-tui-accent/10 mx-4 hidden sm:block" />
                    </div>
                    <div className="border border-tui-border bg-ctp-mantle/50 p-3 md:p-4 rounded-sm relative overflow-hidden group">
                      <div className="text-sm leading-relaxed text-tui-text/90 italic whitespace-pre-wrap">
                        {selectedReview.summary}
                      </div>
                    </div>
                  </section>

                  {/* Diff Section */}
                  {diffText.trim() && (
                    <section id="review-diffs">
                      <div className="flex items-center justify-between mb-4 mt-8">
                        <div className="flex items-center gap-2 text-xs font-bold text-tui-accent">
                          <GitPullRequest size={14} />
                          Delta analysis
                        </div>
                        <div className="h-[2px] flex-1 bg-tui-accent/10 mx-4 hidden sm:block" />
                      </div>

                      {fileDiffs.map((fileDiff, idx) => (
                        <div key={`${fileDiff.path}-${idx}`} className="border border-tui-border bg-ctp-crust/60 rounded-sm overflow-hidden mb-4">
                          <div className="bg-ctp-crust/40 px-3 py-2 border-b border-tui-border flex items-center justify-between gap-2">
                            <span className="text-xs text-tui-text font-bold flex items-center gap-2 min-w-0">
                              <FileText size={12} className="text-tui-accent shrink-0" />
                              <span className="truncate">{fileDiff.path}</span>
                            </span>
                          </div>

                          <div className="p-3 overflow-x-auto">
                            <PatchDiff patch={fileDiff.patch} options={DIFF_VIEW_OPTIONS} />
                          </div>
                        </div>
                      ))}

                       <div className="flex items-center gap-2 shrink-0 text-[10px] text-tui-dim font-mono mt-2">
                        +{diffStats.additions} / -{diffStats.deletions} • {diffStats.files} files
                      </div>
                    </section>
                  )}

                  {/* General Comments Section */}
                  <section id="review-comments" className="pb-4">
                    <div className="flex items-center justify-between mb-4 mt-8">
                      <div className="flex items-center gap-2 text-xs font-bold text-tui-accent">
                        <MessageSquare size={14} />
                        Review comments
                      </div>
                      <div className="h-[2px] flex-1 bg-tui-accent/10 mx-4 hidden sm:block" />
                    </div>
                    <div className="relative">
                      <textarea 
                        value={feedback}
                        onChange={(e) => setFeedback(e.target.value)}
                        placeholder="Enter general feedback, suggestions, or summary..."
                        className="w-full h-24 md:h-32 bg-ctp-crust border border-tui-border-dim p-3 md:p-4 text-sm focus:border-tui-accent focus:bg-tui-accent/5 transition-all outline-none resize-none placeholder:text-tui-dim/30 font-mono"
                      />
                    </div>
                  </section>
                </div>
              </div>

              {/* Navigation Sidebar (Floating) - Hidden on mobile */}
              <div className="absolute right-6 top-24 w-48 space-y-2 hidden xl:block pointer-events-none">
                <div className="bg-ctp-crust/90 border border-tui-border p-2 pointer-events-auto">
                  <div className="text-[9px] font-bold text-tui-accent mb-2 flex items-center gap-2">
                    <Navigation size={10} />
                    Quick Nav
                  </div>
                  <div className="space-y-1">
                    <button 
                      onClick={() => scrollToSection('review-summary')}
                      className="w-full text-left px-2 py-1 text-[9px] text-tui-dim hover:text-tui-accent hover:bg-tui-accent/5 flex items-center justify-between group"
                    >
                      Summary
                      <ChevronRight size={10} className="opacity-0 group-hover:opacity-100" />
                    </button>
                    <button 
                      onClick={() => scrollToSection('review-diffs')}
                      className="w-full text-left px-2 py-1 text-[9px] text-tui-dim hover:text-tui-accent hover:bg-tui-accent/5 flex items-center justify-between group"
                    >
                      Diff ({diffStats.files})
                      <ChevronRight size={10} className="opacity-0 group-hover:opacity-100" />
                    </button>
                    <button 
                      onClick={() => scrollToSection('review-comments')}
                      className="w-full text-left px-2 py-1 text-[9px] text-tui-dim hover:text-tui-accent hover:bg-tui-accent/5 flex items-center justify-between group"
                    >
                      Final comments
                      <ChevronRight size={10} className="opacity-0 group-hover:opacity-100" />
                    </button>
                  </div>
                </div>

                <div className="bg-ctp-crust/90 border border-tui-border p-2 pointer-events-auto">
                  <div className="text-[9px] font-bold text-tui-accent mb-2 flex items-center gap-2">
                    <Clock size={10} />
                    Statistics
                  </div>
                   <div className="space-y-1 text-[8px] text-tui-dim">
                     <div className="flex justify-between">
                       <span>Files:</span>
                       <span className="text-tui-accent">{diffStats.files}</span>
                     </div>
                     <div className="flex justify-between">
                       <span>Additions:</span>
                       <span className="text-green-500">+{diffStats.additions}</span>
                     </div>
                      <div className="flex justify-between">
                        <span>Deletions:</span>
                        <span className="text-red-500">-{diffStats.deletions}</span>
                      </div>
                    </div>

                </div>
              </div>

                   {/* Action Bar */}
                   <div className="p-3 md:p-4 border-t border-tui-border bg-ctp-mantle flex flex-col sm:flex-row gap-3 md:gap-4 shrink-0">
                      <button 
                        onClick={() => handleAction('approved')}
                        disabled={submitReview.isPending}
                        className="flex-1 group relative overflow-hidden border border-ctp-green bg-ctp-green/10 text-ctp-green py-3 md:py-4 text-xs font-bold hover:bg-ctp-green hover:text-ctp-base disabled:opacity-50 flex items-center justify-center gap-2 md:gap-3 transition-all"
                      >
                        <CheckSquare size={18} className="transition-transform group-hover:scale-110" />
                        {submitReview.isPending ? 'Approving...' : 'Approve'}
                      </button>
                      <button 
                        onClick={() => handleAction('changes_requested')}
                        disabled={submitReview.isPending}
                        className="flex-1 group relative overflow-hidden border border-ctp-red bg-ctp-red/10 text-ctp-red py-3 md:py-4 text-xs font-bold hover:bg-ctp-red hover:text-ctp-base disabled:opacity-50 flex items-center justify-center gap-2 md:gap-3 transition-all"
                      >
                        <XSquare size={18} className="transition-transform group-hover:scale-110" />
                        {submitReview.isPending ? 'Requesting...' : 'Request Changes'}
                      </button>

                   </div>

            </>
          ) : (
            <div className="flex-1 flex flex-col items-center justify-center text-tui-dim space-y-6">
              {reviews.length === 0 ? (
                <>
                  <div className="relative">
                    <Search size={64} className="opacity-10" />
                    <div className="absolute inset-0 border border-tui-dim/5 rounded-full scale-150" />
                  </div>
                   <div className="text-center space-y-2">
                      <p className="text-xs font-bold opacity-40">Scanning for input</p>
                     <p className="text-[10px] italic opacity-20">No active signals detected</p>
                   </div>
                 </>
               ) : (
                 <>
                   <div className="relative">
                     <AlertCircle size={64} className="opacity-10 animate-pulse" />
                     <div className="absolute inset-0 border-2 border-tui-dim/10 rounded-full animate-ping" />
                   </div>
                   <div className="text-center space-y-2">
                     <p className="text-xs font-bold opacity-40">Awaiting selection</p>
                     <p className="text-[10px] italic opacity-20">Registry monitor active</p>
                   </div>
                 </>
               )}
            </div>
          )}
        </div>
      </div>

      <style>{`
        .diff-view-container .diff {
          width: 100%;
          border-collapse: collapse;
          font-size: 11px;
        }
        .diff-view-container .diff-gutter {
          width: 40px;
          text-align: right;
          padding: 0 8px;
          color: var(--color-ctp-overlay0);
          user-select: none;
          cursor: pointer;
        }
        .diff-view-container .diff-gutter:hover {
          color: var(--color-ctp-mauve);
          background: var(--color-ctp-surface0);
        }
        .diff-view-container .diff-code {
          padding: 0 12px;
          white-space: pre;
          color: var(--color-ctp-text);
        }
        .diff-view-container .diff-code-insert {
          background: rgba(166, 227, 161, 0.1);
          color: var(--color-ctp-green);
        }
        .diff-view-container .diff-gutter-insert {
          background: rgba(166, 227, 161, 0.2);
          color: var(--color-ctp-green);
        }
        .diff-view-container .diff-code-delete {
          background: rgba(243, 139, 168, 0.1);
          color: var(--color-ctp-red);
        }
        .diff-view-container .diff-gutter-delete {
          background: rgba(243, 139, 168, 0.2);
          color: var(--color-ctp-red);
        }
        .diff-view-container .diff-hunk-header {
          background: var(--color-ctp-surface0);
          color: var(--color-ctp-blue);
          font-size: 10px;
          font-weight: bold;
        }
        .diff-view-container .diff-hunk-header-gutter {
          background: var(--color-ctp-surface1);
        }
        .diff-view-container .diff-hunk-header-content {
          padding: 4px 12px;
        }
      `}</style>
    </div>
  )
}
