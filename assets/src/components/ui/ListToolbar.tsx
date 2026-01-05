import React from 'react'
import { Search, X } from 'lucide-react'
import { cn } from '../../lib/cn'

interface FilterOption {
  value: string
  label: string
}

interface ListToolbarProps {
  // Search
  searchQuery?: string
  onSearchChange?: (query: string) => void
  searchPlaceholder?: string
  
  // Filters
  filters?: {
    icon?: React.ReactNode
    value: string
    onChange: (value: string) => void
    options: FilterOption[]
    placeholder?: string
  }[]
  
  // Custom children (buttons, view togglers, etc.)
  children?: React.ReactNode
  
  // Styling
  className?: string
}

export function ListToolbar({
  searchQuery,
  onSearchChange,
  searchPlaceholder = "SEARCH...",
  filters = [],
  children,
  className
}: ListToolbarProps) {
  return (
    <div className={cn("flex flex-col sm:flex-row gap-4 items-center justify-between bg-tui-dim/5 p-2 border border-tui-border font-mono", className)}>
      <div className="flex flex-1 w-full gap-2 items-center">
        {onSearchChange && (
          <div className="relative flex-1 max-w-md">
            <Search className="absolute left-3 top-1/2 -translate-y-1/2 text-tui-dim" size={14} />
            <input 
              type="text"
              placeholder={searchPlaceholder.toUpperCase()}
              value={searchQuery}
              onChange={(e) => onSearchChange(e.target.value)}
              className="w-full pl-9 pr-8 py-2 bg-tui-bg border border-tui-border text-xs uppercase focus:outline-none focus:border-tui-accent transition-colors placeholder:text-tui-dim/30"
            />
            {searchQuery && (
              <button 
                onClick={() => onSearchChange('')}
                className="absolute right-3 top-1/2 -translate-y-1/2 text-tui-dim hover:text-tui-accent transition-colors"
              >
                <X size={14} />
              </button>
            )}
          </div>
        )}

        {filters.map((filter, idx) => (
          <div key={idx} className="flex items-center gap-2 bg-tui-bg border border-tui-border px-3 py-2 shrink-0">
            {filter.icon}
            <select 
              value={filter.value}
              onChange={(e) => filter.onChange(e.target.value)}
              className="bg-transparent border-none outline-none text-[10px] md:text-xs uppercase font-mono cursor-pointer focus:ring-0"
            >
              {filter.placeholder && <option value="">{filter.placeholder.toUpperCase()}</option>}
              {filter.options.map((opt) => (
                <option key={opt.value} value={opt.value}>
                  {opt.label.toUpperCase()}
                </option>
              ))}
            </select>
          </div>
        ))}
      </div>

      {children && (
        <div className="flex items-center gap-2 w-full sm:w-auto justify-end">
          {children}
        </div>
      )}
    </div>
  )
}
