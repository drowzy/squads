import { useState } from 'react'
import { Folder, FolderGit, ChevronRight, ChevronUp, Home, RefreshCw } from 'lucide-react'
import { useBrowseDirectories, type DirectoryEntry } from '../api/queries'

interface FolderBrowserProps {
  onSelect: (path: string, name: string) => void
  initialPath?: string
}

export function FolderBrowser({ onSelect, initialPath = '' }: FolderBrowserProps) {
  const [currentPath, setCurrentPath] = useState(initialPath || '')
  const { data, isLoading, error, refetch } = useBrowseDirectories(currentPath)

  const handleNavigate = (path: string) => {
    setCurrentPath(path)
  }

  const handleSelect = (entry: DirectoryEntry) => {
    // Extract folder name from path for auto-naming
    const folderName = entry.name
      .split(/[-_]/)
      .map(word => word.charAt(0).toUpperCase() + word.slice(1))
      .join(' ')
    onSelect(entry.path, folderName)
  }

  const goToParent = () => {
    if (data?.parent_path && data.parent_path !== data.current_path) {
      setCurrentPath(data.parent_path)
    }
  }

  const goHome = () => {
    setCurrentPath('')
  }

  return (
    <div className="border border-tui-border bg-tui-bg">
      {/* Navigation bar */}
      <div className="flex items-center gap-2 p-2 border-b border-tui-border bg-tui-dim/10">
        <button
          onClick={goHome}
          className="p-1.5 text-tui-dim hover:text-tui-accent hover:bg-tui-dim/20 rounded"
          title="Go to home directory"
        >
          <Home size={14} />
        </button>
        <button
          onClick={goToParent}
          disabled={!data || data.parent_path === data.current_path}
          className="p-1.5 text-tui-dim hover:text-tui-accent hover:bg-tui-dim/20 rounded disabled:opacity-30 disabled:cursor-not-allowed"
          title="Go up one level"
        >
          <ChevronUp size={14} />
        </button>
        <button
          onClick={() => refetch()}
          className="p-1.5 text-tui-dim hover:text-tui-accent hover:bg-tui-dim/20 rounded"
          title="Refresh"
        >
          <RefreshCw size={14} className={isLoading ? 'animate-spin' : ''} />
        </button>
        <div className="flex-1 text-xs text-tui-dim truncate font-mono px-2">
          {data?.current_path || '~'}
        </div>
      </div>

      {/* Directory listing */}
      <div className="max-h-64 overflow-y-auto">
        {isLoading ? (
          <div className="p-4 text-center text-xs text-tui-dim animate-pulse uppercase tracking-widest">
            Loading...
          </div>
        ) : error ? (
          <div className="p-4 text-center text-xs text-ctp-red">
            {error instanceof Error ? error.message : 'Failed to load directories'}
          </div>
        ) : data?.directories.length === 0 ? (
          <div className="p-4 text-center text-xs text-tui-dim uppercase tracking-widest">
            No subdirectories
          </div>
        ) : (
          <div className="divide-y divide-tui-border/30">
            {data?.directories.map((entry) => (
              <DirectoryRow
                key={entry.path}
                entry={entry}
                onNavigate={() => handleNavigate(entry.path)}
                onSelect={() => handleSelect(entry)}
              />
            ))}
          </div>
        )}
      </div>
    </div>
  )
}

interface DirectoryRowProps {
  entry: DirectoryEntry
  onNavigate: () => void
  onSelect: () => void
}

function DirectoryRow({ entry, onNavigate, onSelect }: DirectoryRowProps) {
  return (
    <div className="flex items-center group hover:bg-tui-dim/10">
      {/* Expand button (if has children) */}
      <button
        onClick={onNavigate}
        disabled={!entry.has_children}
        className="p-2 text-tui-dim hover:text-tui-accent disabled:opacity-30 disabled:cursor-not-allowed"
        title={entry.has_children ? 'Open folder' : 'No subfolders'}
      >
        <ChevronRight size={14} />
      </button>

      {/* Folder icon and name - clickable to select */}
      <button
        onClick={onSelect}
        className="flex-1 flex items-center gap-2 py-2 pr-3 text-left hover:text-tui-accent"
      >
        {entry.is_git_repo ? (
          <FolderGit size={16} className="text-tui-accent shrink-0" />
        ) : (
          <Folder size={16} className="text-tui-dim shrink-0" />
        )}
        <span className="truncate text-sm">{entry.name}</span>
        {entry.is_git_repo && (
          <span className="text-xs px-1.5 py-0.5 bg-tui-accent/20 text-tui-accent rounded shrink-0">
            git
          </span>
        )}
      </button>
    </div>
  )
}

export default FolderBrowser
