import { createFileRoute, Link } from '@tanstack/react-router'
import { useActiveProject } from './__root'
import { useFsIssues } from '../api/queries'
import { FileText, Hash, Clock } from 'lucide-react'

export const Route = createFileRoute('/issues')({
  component: IssuesPage,
})

function IssuesPage() {
  const { activeProject } = useActiveProject()
  const projectId = activeProject?.id

  const { data: issues = [], isLoading } = useFsIssues(projectId)

  return (
    <div className="space-y-6 font-mono">
      <div className="flex flex-col sm:flex-row sm:items-center justify-between gap-4">
        <div>
          <h1 className="text-2xl font-bold tracking-tight flex items-center gap-2">
            <FileText className="text-tui-accent" size={18} />
            Issues
          </h1>
          <p className="text-tui-dim text-sm mt-1 uppercase tracking-widest">
            Filesystem issues for {activeProject?.name || 'active project'}
          </p>
        </div>
        <div className="text-xs text-tui-dim bg-ctp-crust/40 px-2 py-1 border border-tui-border">
          Total: {issues.length}
        </div>
      </div>

      {isLoading ? (
        <div className="flex items-center justify-center text-tui-dim text-xs uppercase tracking-widest">
          Loading issues...
        </div>
      ) : issues.length === 0 ? (
        <div className="border border-tui-border bg-ctp-mantle/50 p-6 text-tui-dim text-xs">
          No filesystem issues yet.
        </div>
      ) : (
        <div className="border border-tui-border bg-ctp-mantle/50">
          {issues.map((issue) => (
            <Link
              key={issue.id}
              to={`/issues/${issue.id}` as any}
              className="block px-4 py-3 border-b border-tui-border/50 last:border-0 hover:bg-tui-dim/5"
            >
              <div className="flex items-start justify-between gap-4">
                <div className="min-w-0 flex-1">
                  <div className="flex items-center gap-2 text-[10px] uppercase tracking-widest text-tui-dim">
                    <Hash size={12} />
                    <span className="truncate">{issue.id}</span>
                  </div>
                  <div className="mt-1 font-bold text-sm text-tui-text truncate">{issue.title}</div>
                </div>
                <div className="flex flex-col items-end gap-2 shrink-0">
                  <span className="text-[10px] px-1.5 py-0.5 font-bold border border-tui-border text-tui-dim">
                    {issue.status}
                  </span>
                  {issue.updated_at ? (
                    <div className="flex items-center gap-1 text-[10px] text-tui-dim">
                      <Clock size={12} />
                      {new Date(issue.updated_at).toLocaleString()}
                    </div>
                  ) : null}
                </div>
              </div>
            </Link>
          ))}
        </div>
      )}
    </div>
  )
}
