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
import { useReviews, useSubmitReview, Review } from '../api/queries'
import { parseDiff, Diff, Hunk } from 'react-diff-view'
import 'react-diff-view/style/index.css'

// Optional: Prism for syntax highlighting
import Prism from 'prismjs'
import 'prismjs/themes/prism-tomorrow.css'

export const Route = createFileRoute('/review')({
  component: ReviewQueue,
})

function ReviewQueue() {
  const [selectedId, setSelectedId] = useState<string | null>(null)
  const [feedback, setFeedback] = useState('')
  const [inlineComments, setInlineComments] = useState<Record<string, string[]>>({})
  const [activeCommentLine, setActiveCommentLine] = useState<string | null>(null)
  const [commentBuffer, setCommentBuffer] = useState('')
  const scrollContainerRef = useRef<HTMLDivElement>(null)
  
  const { data: reviews = [], isLoading } = useReviews()
  const submitReview = useSubmitReview()

  const selectedReview = useMemo(() => 
    reviews.find(r => r.id === selectedId) || null,
  [reviews, selectedId])

  const files = useMemo(() => {
    if (!selectedReview?.diff) return []
    try {
      return parseDiff(selectedReview.diff)
    } catch (e) {
      console.error('Failed to parse diff', e)
      return []
    }
  }, [selectedReview])

  useEffect(() => {
    const handleKeyDown = (e: KeyboardEvent) => {
      if (e.key === 'Escape' && selectedId) {
        if (activeCommentLine) {
          setActiveCommentLine(null)
        } else {
          setSelectedId(null)
        }
      }
    }
    window.addEventListener('keydown', handleKeyDown)
    return () => window.removeEventListener('keydown', handleKeyDown)
  }, [selectedId, activeCommentLine])

  const scrollToSection = (id: string) => {
    const el = document.getElementById(id)
    if (el) {
      el.scrollIntoView({ behavior: 'smooth', block: 'start' })
    }
  }

  const handleAction = (status: 'approved' | 'changes_requested' | 'merged') => {
    if (!selectedId) return
    
    // Combine general feedback with inline comments
    let fullFeedback = feedback
    if (Object.keys(inlineComments).length > 0) {
      fullFeedback += '\n\n--- INLINE COMMENTS ---\n'
      Object.entries(inlineComments).forEach(([lineId, comments]) => {
        fullFeedback += `\nLine ${lineId}:\n`
        comments.forEach(c => fullFeedback += `- ${c}\n`)
      })
    }

    submitReview.mutate({ id: selectedId, status, feedback: fullFeedback }, {
      onSuccess: () => {
        setSelectedId(null)
        setFeedback('')
        setInlineComments({})
      }
    })
  }

  const addInlineComment = (lineId: string) => {
    if (!commentBuffer.trim()) return
    setInlineComments(prev => ({
      ...prev,
      [lineId]: [...(prev[lineId] || []), commentBuffer.trim()]
    }))
    setCommentBuffer('')
    setActiveCommentLine(null)
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
                    setInlineComments({})
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
                  {files.length > 0 && (
                    <section id="review-diffs">
                      <div className="flex items-center justify-between mb-4 mt-8">
                        <div className="flex items-center gap-2 text-xs font-bold text-tui-accent">
                          <GitPullRequest size={14} />
                          Delta analysis
                        </div>
                        <div className="h-[2px] flex-1 bg-tui-accent/10 mx-4 hidden sm:block" />
                      </div>
                      
                      <div className="space-y-4 md:space-y-6">
                        {files.map((file, fileIdx) => (
                          <div key={fileIdx} id={`file-${fileIdx}`} className="border border-tui-border bg-ctp-crust/60 rounded-sm overflow-hidden">
                            <div className="bg-ctp-crust/40 px-3 py-2 border-b border-tui-border flex items-center justify-between gap-2">
                              <span className="text-xs text-tui-text font-bold flex items-center gap-2 min-w-0">
                                <FileText size={12} className="text-tui-accent shrink-0" />
                                <span className="truncate">
                                  {(file as any).newPath === (file as any).oldPath ? (file as any).newPath : `${(file as any).oldPath} -> ${(file as any).newPath}`}
                                </span>
                              </span>
                              <div className="flex items-center gap-2 shrink-0">
                                <span className="text-xs text-green-500 font-bold">+{(file as any).additions}</span>
                                <span className="text-xs text-red-500 font-bold">-{(file as any).deletions}</span>
                              </div>
                            </div>
                            
                            <div className="diff-view-container overflow-x-auto">
                              <Diff viewType="unified" diffType={file.type} hunks={file.hunks}>
                                {hunks => hunks.map((hunk: any) => (
                                  <Hunk 
                                    key={hunk.content} 
                                    hunk={hunk} 
                                    // @ts-ignore - gutterEvents is not typed in HunkProps but is supported
                                    gutterEvents={{
                                      onClick: ({ change }: { change: any }) => {
                                        const id = `${(file as any).newPath}:${change.newLineNumber || change.oldLineNumber}`
                                        setActiveCommentLine(activeCommentLine === id ? null : id)
                                      }
                                    } as any}
                                    widgets={{
                                      ...Object.keys(inlineComments).reduce((acc, id) => {
                                        const [path, line] = id.split(':')
                                        if (path === (file as any).newPath) {
                                          const lineNum = parseInt(line)
                                          // Find the hunk that contains this line
                                          const hunkWithLine = file.hunks.find((h: any) => 
                                            h.changes.some((c: any) => (c.newLineNumber || c.oldLineNumber) === lineNum)
                                          )
                                          
                                          if (hunkWithLine) {
                                            const change = hunkWithLine.changes.find((c: any) => (c.newLineNumber || c.oldLineNumber) === lineNum)
                                            if (change) {
                                              // @ts-ignore - lineNumber/oldLineNumber/newLineNumber type mismatch
                                              const key = `${change.type}-${change.lineNumber || change.oldLineNumber || change.newLineNumber}`
                                              acc[key] = (
                                                <div className="bg-tui-accent/10 border-y border-tui-accent/30 p-3 space-y-2">
                                                  {inlineComments[id].map((c, i) => (
                                                    <div key={i} className="flex gap-2 items-start group/comment">
                                                      <MessageSquare size={10} className="mt-1 text-tui-accent" />
                                                      <div className="flex-1">
                                                        <p className="text-[10px] text-tui-text italic whitespace-pre-wrap">{c}</p>
                                                      </div>
                                                    </div>
                                                  ))}
                                                </div>
                                              )
                                            }
                                          }
                                        }
                                        return acc
                                      }, {} as any),
                                      ...(activeCommentLine?.startsWith((file as any).newPath + ':') ? (() => {
                                        const lineNum = parseInt(activeCommentLine.split(':')[1])
                                        const hunkWithLine = file.hunks.find((h: any) => 
                                          h.changes.some((c: any) => (c.newLineNumber || c.oldLineNumber) === lineNum)
                                        )
                                        const change = (hunkWithLine as any)?.changes.find((c: any) => (c.newLineNumber || c.oldLineNumber) === lineNum)
                                        
                                        if (change) {
                                          // @ts-ignore - lineNumber/oldLineNumber/newLineNumber type mismatch
                                          const key = `${change.type}-${change.lineNumber || change.oldLineNumber || change.newLineNumber}`
                                          return {
                                            [key]: (
                                               <div className="bg-tui-accent/5 border-y border-tui-accent/20 p-3">
                        <div className="flex flex-col gap-2">
                          <div className="flex items-center gap-2 text-[8px] font-bold text-tui-accent mb-1">
                            <Plus size={10} />
                            Add inline feedback
                          </div>
                                                  <div className="flex gap-2">
                                                    <input 
                                                      autoFocus
                                                      value={commentBuffer}
                                                      onChange={e => setCommentBuffer(e.target.value)}
                                                      onKeyDown={e => {
                                                        if (e.key === 'Enter') addInlineComment(activeCommentLine)
                                                        if (e.key === 'Escape') setActiveCommentLine(null)
                                                      }}
                                                      placeholder="CMD> Enter inline comment..."
                                                      className="flex-1 bg-ctp-crust border border-tui-border-dim p-2 text-[10px] outline-none focus:border-tui-accent font-mono"
                                                    />
                                                    <button 
                                                      onClick={() => addInlineComment(activeCommentLine)}
                                                      className="bg-tui-accent text-tui-bg px-3 py-1 text-[10px] font-bold hover:opacity-80 flex items-center gap-2"
                                                    >
                                                      <Send size={12} />
                                                      Commit
                                                    </button>
                                                  </div>
                                                  <div className="text-[8px] text-tui-dim italic">
                                                    Press ESC to cancel • Enter to commit
                                                  </div>
                                                </div>
                                              </div>
                                            )
                                          }
                                        }
                                        return {}
                                      })() : {})
                                    }}
                                  />
                                ))}
                              </Diff>
                            </div>
                          </div>
                        ))}
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
                      Diff files ({files.length})
                      <ChevronRight size={10} className="opacity-0 group-hover:opacity-100" />
                    </button>
                    {files.slice(0, 5).map((f, i) => (
                      <button 
                        key={i}
                        onClick={() => scrollToSection(`file-${i}`)}
                        className="w-full text-left px-4 py-0.5 text-[8px] text-tui-dim/60 hover:text-tui-accent hover:bg-tui-accent/5 truncate"
                      >
                        - {f.newPath.split('/').pop()}
                      </button>
                    ))}
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
                      <span>Additions:</span>
                      {/* @ts-ignore - additions property exists on File but not in types */}
                      <span className="text-green-500">+{files.reduce((a, f) => a + (f as any).additions, 0)}</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Deletions:</span>
                      {/* @ts-ignore - deletions property exists on File but not in types */}
                      <span className="text-red-500">-{files.reduce((a, f) => a + (f as any).deletions, 0)}</span>
                    </div>
                    <div className="flex justify-between">
                      <span>Comments:</span>
                      <span className="text-tui-accent">{Object.keys(inlineComments).length}</span>
                    </div>
                  </div>
                </div>
              </div>

                   {/* Action Bar */}
                   <div className="p-3 md:p-4 border-t border-tui-border bg-ctp-mantle flex flex-col sm:flex-row gap-3 md:gap-4 shrink-0">
                     {selectedReview.status === 'approved' ? (
                        <button 
                         onClick={() => handleAction('merged')}
                         disabled={submitReview.isPending}
                         className="flex-1 group relative overflow-hidden border border-tui-accent bg-tui-accent/10 text-tui-accent py-3 md:py-4 text-xs font-bold hover:bg-tui-accent hover:text-tui-bg disabled:opacity-50 flex items-center justify-center gap-2 md:gap-3 transition-all"
                       >
                         <GitPullRequest size={18} className="transition-transform group-hover:scale-110" />
                          {submitReview.isPending ? 'Merging...' : 'Merge & Cleanup'}
                       </button>
                     ) : (
                       <>
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
                       </>
                     )}
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
