import { createFileRoute, Link } from '@tanstack/react-router'
import { useActiveProject } from './__root'
import { useFsIssue, useUpdateFsIssue } from '../api/queries'
import { ArrowLeft, FileText } from 'lucide-react'
import ReactMarkdown from 'react-markdown'
import remarkGfm from 'remark-gfm'

export const Route = createFileRoute('/issues/$id')({
  component: IssueDetailPage,
})

const STATUSES = ['open', 'in_progress', 'blocked', 'done'] as const

function IssueDetailPage() {
  const { activeProject } = useActiveProject()
  const projectId = activeProject?.id

  const { id } = Route.useParams()
  const { data: issue, isLoading } = useFsIssue(projectId, id)
  const updateIssue = useUpdateFsIssue(projectId)

  return (
    <div className="space-y-6 font-mono">
      <div className="flex items-center justify-between gap-4">
        <div className="min-w-0">
          <div className="flex items-center gap-2 text-xs text-tui-dim">
            <Link
              to="/issues" as any
              className="inline-flex items-center gap-2 text-tui-accent hover:underline"
            >
              <ArrowLeft size={14} />
              Issues
            </Link>
            <span className="text-tui-dim/60">/</span>
            <span className="truncate">{id}</span>
          </div>
          <h1 className="mt-2 text-xl md:text-2xl font-bold tracking-tight flex items-center gap-2">
            <FileText className="text-tui-accent" size={18} />
            <span className="truncate">{issue?.title || 'Loading…'}</span>
          </h1>
        </div>
      </div>

      {isLoading || !issue ? (
        <div className="border border-tui-border bg-ctp-mantle/50 p-6 text-tui-dim text-xs">
          Loading issue...
        </div>
      ) : (
        <>
          <div className="border border-tui-border bg-ctp-mantle/50 p-4 flex flex-col sm:flex-row sm:items-center justify-between gap-4">
            <div className="text-xs text-tui-dim uppercase tracking-widest">
              Status: <span className="text-tui-text font-bold">{(issue.frontmatter as any)?.status || 'open'}</span>
            </div>
            <div className="flex flex-wrap gap-2">
              {STATUSES.map((status) => (
                <button
                  key={status}
                  onClick={() => updateIssue.mutate({ id, status })}
                  disabled={updateIssue.isPending}
                  className={`px-3 py-1 text-[10px] font-bold uppercase tracking-widest border transition-colors ${
                    ((issue.frontmatter as any)?.status || 'open') === status
                      ? 'border-tui-accent text-tui-accent bg-tui-accent/10'
                      : 'border-tui-border text-tui-dim hover:text-tui-text hover:bg-tui-dim/5'
                  }`}
                >
                  {status}
                </button>
              ))}
            </div>
          </div>

          <div className="border border-tui-border bg-ctp-crust/40 p-4 prose prose-invert prose-sm max-w-none break-words">
            <ReactMarkdown remarkPlugins={[remarkGfm]}>{issue.body_md}</ReactMarkdown>
          </div>
        </>
      )}
    </div>
  )
}
