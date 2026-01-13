import { useState } from 'react'
import { MultiFileDiff, PatchDiff, type FileContents } from '@pierre/diffs/react'
import { X, Check, XCircle, ChevronDown, ChevronUp, Copy } from 'lucide-react'
import { cn } from '../lib/cn'
import type { SessionDiffEntry } from '../api/queries'

const DIFF_VIEW_OPTIONS = { theme: 'catppuccin-mocha' as const }

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null
}

function looksLikePatch(text: string) {
  const trimmed = text.trim()
  if (!trimmed) return false
  return /^diff --git /m.test(trimmed) || /^@@/m.test(trimmed) || /^(---|\+\+\+)/m.test(trimmed)
}

function extractDiffText(value: unknown): string | null {
  if (typeof value === 'string') return value
  if (!value) return null
  if (Array.isArray(value)) return null
  if (!isRecord(value)) return null

  const nested = (value as Record<string, unknown>).data
  if (nested) {
    const nestedText = extractDiffText(nested)
    if (nestedText) return nestedText
  }

  const candidates = [
    (value as Record<string, unknown>).diff,
    (value as Record<string, unknown>).patch,
    (value as Record<string, unknown>).text,
    (value as Record<string, unknown>).output,
  ]

  for (const candidate of candidates) {
    if (typeof candidate === 'string') return candidate
  }

  return null
}

function extractDiffEntries(value: unknown): SessionDiffEntry[] | null {
  if (!value) return null

  if (Array.isArray(value)) {
    if (value.length === 0) return []
    const entries = value.filter(isRecord) as SessionDiffEntry[]
    return entries.length > 0 ? entries : null
  }

  if (!isRecord(value)) return null

  const candidates = [
    (value as Record<string, unknown>).diffs,
    (value as Record<string, unknown>).files,
    (value as Record<string, unknown>).data,
  ]

  for (const candidate of candidates) {
    const entries = extractDiffEntries(candidate)
    if (entries) return entries
  }

  return null
}

function getDiffEntryTitle(entry: SessionDiffEntry, index: number) {
  return entry.path || entry.file || entry.filename || `Change ${index + 1}`
}

function formatDiffEntryStats(entry: SessionDiffEntry) {
  const additions = typeof entry.additions === 'number' ? entry.additions : null
  const deletions = typeof entry.deletions === 'number' ? entry.deletions : null

  if (additions == null && deletions == null) return null

  const parts: string[] = []
  if (additions != null) parts.push(`+${additions}`)
  if (deletions != null) parts.push(`-${deletions}`)
  return parts.join(' ')
}

function extractLatestSummaryDiffEntries(
  messages: Array<{ info?: { summary?: unknown } }> | undefined
): SessionDiffEntry[] | null {
  if (!Array.isArray(messages)) return null

  for (let idx = messages.length - 1; idx >= 0; idx -= 1) {
    const summary = messages[idx]?.info?.summary
    if (!summary || typeof summary !== 'object' || Array.isArray(summary)) continue

    const diffs = (summary as Record<string, unknown>).diffs
    const entries = extractDiffEntries(diffs)
    if (entries && entries.length > 0) return entries
  }

  return null
}

function safeStringify(value: unknown): string {
  if (value === null || value === undefined) return ''
  try {
    return JSON.stringify(value, null, 2)
  } catch {
    return String(value)
  }
}

interface DiffCard {
  key: string
  title: string
  stats: string | null
  type: 'patch' | 'file' | 'text'
  patch?: string
  oldFile?: FileContents
  newFile?: FileContents
  text?: string
  entry: SessionDiffEntry
}

interface DiffPanelProps {
  diffs?: SessionDiffEntry[]
  messages?: Array<{ info?: { summary?: unknown } }>
  isOpen: boolean
  onClose: () => void
}

export function DiffPanel({ diffs, messages, isOpen, onClose }: DiffPanelProps) {
  const [expandedCards, setExpandedCards] = useState<Set<string>>(new Set())

  const diffEntries = extractDiffEntries(diffs)
  const summaryEntries = extractLatestSummaryDiffEntries(messages)
  const entriesToRender = diffEntries && diffEntries.length > 0 ? diffEntries : summaryEntries

  const diffCards = entriesToRender?.map((entry, idx) => {
    const title = getDiffEntryTitle(entry, idx)
    const stats = formatDiffEntryStats(entry)
    const entryText = extractDiffText(entry)
    const beforeText = typeof entry.before === 'string' ? entry.before : null
    const afterText = typeof entry.after === 'string' ? entry.after : null

    const fileName = entry.path || entry.file || entry.filename || title
    const keyBase = entry.path || entry.file || entry.filename || 'change'

    if (entryText && entryText.trim() !== '' && looksLikePatch(entryText)) {
      return {
        key: `${keyBase}-${idx}`,
        title,
        stats,
        type: 'patch' as const,
        patch: entryText,
        entry,
      }
    }

    if (beforeText != null || afterText != null) {
      const oldFile: FileContents = {
        name: fileName,
        contents: beforeText ?? '',
      }

      const newFile: FileContents = {
        name: fileName,
        contents: afterText ?? '',
      }

      return {
        key: `${keyBase}-${idx}`,
        title,
        stats,
        type: 'file' as const,
        oldFile,
        newFile,
        entry,
      }
    }

    const fallbackText = entryText && entryText.trim() !== '' ? entryText : safeStringify(entry)

    return {
      key: `${keyBase}-${idx}`,
      title,
      stats,
      type: 'text' as const,
      text: fallbackText,
      entry,
    }
  }) || []

  const toggleCard = (key: string) => {
    setExpandedCards((prev) => {
      const next = new Set(prev)
      if (next.has(key)) {
        next.delete(key)
      } else {
        next.add(key)
      }
      return next
    })
  }

  const expandAll = () => {
    setExpandedCards(new Set(diffCards.map((c) => c.key)))
  }

  const collapseAll = () => {
    setExpandedCards(new Set())
  }

  if (!isOpen) return null

  return (
    <div className="h-full flex flex-col border-l border-tui-border bg-ctp-mantle/50 animate-in slide-in-from-right duration-200">
      <div className="flex items-center justify-between px-3 py-2 border-b border-tui-border bg-ctp-crust/40 shrink-0">
        <div className="flex items-center gap-2">
          <div className="text-xs font-bold text-tui-text">Diff</div>
          {diffCards.length > 0 && (
            <span className="text-[10px] text-tui-dim">{diffCards.length} {diffCards.length === 1 ? 'file' : 'files'}</span>
          )}
        </div>
        <div className="flex items-center gap-1">
          {diffCards.length > 0 && (
            <>
              <button
                onClick={expandAll}
                className="p-1 text-tui-dim hover:text-tui-accent transition-colors"
                title="Expand all"
              >
                <ChevronDown size={14} />
              </button>
              <button
                onClick={collapseAll}
                className="p-1 text-tui-dim hover:text-tui-accent transition-colors"
                title="Collapse all"
              >
                <ChevronUp size={14} />
              </button>
            </>
          )}
          <button
            onClick={onClose}
            className="p-1 text-tui-dim hover:text-tui-accent transition-colors"
            title="Close diff panel"
          >
            <X size={14} />
          </button>
        </div>
      </div>

      <div className="flex-1 overflow-y-auto custom-scrollbar">
        {!entriesToRender || entriesToRender.length === 0 ? (
          <div className="h-full flex items-center justify-center text-tui-dim text-sm">
            No diffs available
          </div>
        ) : (
          <div className="p-3 space-y-3">
            {diffCards.map((card) => (
              <div
                key={card.key}
                className="border border-tui-border bg-ctp-crust/20 rounded-sm overflow-hidden"
              >
                <div
                  className="px-2 py-1.5 border-b border-tui-border bg-ctp-crust/40 flex items-center justify-between gap-2 cursor-pointer hover:bg-ctp-crust/60 transition-colors"
                  onClick={() => toggleCard(card.key)}
                >
                  <div className="flex items-center gap-2 min-w-0 flex-1">
                    <div className="text-[10px] font-bold text-tui-text truncate">{card.title}</div>
                    {card.stats && (
                      <div className="text-[9px] font-mono text-tui-dim shrink-0">{card.stats}</div>
                    )}
                  </div>
                  <div className="flex items-center gap-1 shrink-0">
                    {expandedCards.has(card.key) ? (
                      <ChevronDown size={12} className="text-tui-dim" />
                    ) : (
                      <ChevronUp size={12} className="text-tui-dim" />
                    )}
                  </div>
                </div>

                {expandedCards.has(card.key) && (
                  <div className="bg-ctp-base">
                    {card.type === 'patch' && card.patch && (
                      <PatchDiff patch={card.patch} options={DIFF_VIEW_OPTIONS} />
                    )}
                    {card.type === 'file' && card.oldFile && card.newFile && (
                      <MultiFileDiff oldFile={card.oldFile} newFile={card.newFile} options={DIFF_VIEW_OPTIONS} />
                    )}
                    {card.type === 'text' && card.text && (
                      <pre className="text-[10px] leading-relaxed overflow-x-auto whitespace-pre-wrap text-tui-text/90 p-2">
                        {card.text}
                      </pre>
                    )}
                  </div>
                )}
              </div>
            ))}
          </div>
        )}
      </div>

      <div className="border-t border-tui-border p-2 bg-ctp-crust/40 shrink-0">
        <div className="flex items-center justify-between text-[9px] text-tui-dim">
          <div className="flex items-center gap-3">
            <div className="flex items-center gap-1">
              <kbd className="px-1 py-0.5 rounded border border-tui-border bg-tui-dim/10">a</kbd>
              <span>Accept</span>
            </div>
            <div className="flex items-center gap-1">
              <kbd className="px-1 py-0.5 rounded border border-tui-border bg-tui-dim/10">r</kbd>
              <span>Reject</span>
            </div>
            <div className="flex items-center gap-1">
              <kbd className="px-1 py-0.5 rounded border border-tui-border bg-tui-dim/10">A</kbd>
              <span>Accept All</span>
            </div>
            <div className="flex items-center gap-1">
              <kbd className="px-1 py-0.5 rounded border border-tui-border bg-tui-dim/10">R</kbd>
              <span>Reject All</span>
            </div>
          </div>
          <div className="flex items-center gap-1">
            <kbd className="px-1 py-0.5 rounded border border-tui-border bg-tui-dim/10">[</kbd>
            <span>Close</span>
          </div>
        </div>
      </div>
    </div>
  )
}
