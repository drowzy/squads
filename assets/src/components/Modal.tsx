import { useEffect, useRef, type ReactNode } from 'react'
import { X } from 'lucide-react'
import { cn } from '../lib/cn'

interface ModalProps {
  isOpen: boolean
  onClose: () => void
  title: string
  children: ReactNode
  size?: 'sm' | 'md' | 'lg'
}

export function Modal({ isOpen, onClose, title, children, size = 'md' }: ModalProps) {
  const dialogRef = useRef<HTMLDialogElement>(null)

  useEffect(() => {
    const dialog = dialogRef.current
    if (!dialog) return

    if (isOpen) {
      if (!dialog.open) {
        try {
          dialog.showModal()
        } catch (e) {
          console.error('Modal showModal failed:', e)
        }
      }
    } else {
      if (dialog.open) {
        dialog.close()
      }
    }
  }, [isOpen])

  useEffect(() => {
    const dialog = dialogRef.current
    if (!dialog) return

    const handleCancel = (e: Event) => {
      e.preventDefault()
      onClose()
    }

    dialog.addEventListener('cancel', handleCancel)
    return () => dialog.removeEventListener('cancel', handleCancel)
  }, [onClose])

  // Handle backdrop click
  const handleBackdropClick = (e: React.MouseEvent<HTMLDialogElement>) => {
    const dialog = dialogRef.current
    if (e.target === dialog) {
      onClose()
    }
  }

  const sizeClasses = {
    sm: 'max-w-sm',
    md: 'max-w-md',
    lg: 'max-w-lg',
  }

  return (
    <dialog
      ref={dialogRef}
      onClick={handleBackdropClick}
      className={cn(
        'backdrop:bg-black/60 bg-transparent p-0 m-auto',
        'w-full',
        sizeClasses[size]
      )}
    >
      <div className="bg-tui-bg border border-tui-border rounded-lg shadow-xl">
        <div className="flex items-center justify-between px-4 py-3 border-b border-tui-border">
          <h2 className="text-sm font-bold tracking-widest text-tui-text uppercase">
            {title}
          </h2>
          <button
            onClick={onClose}
            className="p-1 text-tui-dim hover:text-tui-text transition-colors"
          >
            <X size={18} />
          </button>
        </div>
        <div className="p-4">
          {children}
        </div>
      </div>
    </dialog>
  )
}

interface FormFieldProps {
  label: string
  children: ReactNode
  error?: string
  hint?: string
}

export function FormField({ label, children, error, hint }: FormFieldProps) {
  return (
    <div className="space-y-1.5">
      <label className="block text-xs font-bold tracking-wider text-tui-dim uppercase">
        {label}
      </label>
      {children}
      {hint && !error && (
        <p className="text-xs text-tui-dim">{hint}</p>
      )}
      {error && (
        <p className="text-xs text-ctp-red">{error}</p>
      )}
    </div>
  )
}

interface InputProps extends React.InputHTMLAttributes<HTMLInputElement> {
  error?: boolean
}

export function Input({ error, className, ...props }: InputProps) {
  return (
    <input
      {...props}
      className={cn(
        'w-full px-3 py-2 bg-tui-bg border rounded text-sm text-tui-text',
        'placeholder:text-tui-dim/50',
        'focus:outline-none focus:ring-1',
        error
          ? 'border-ctp-red focus:border-ctp-red focus:ring-ctp-red/50'
          : 'border-tui-border focus:border-tui-accent focus:ring-tui-accent/50',
        className
      )}
    />
  )
}

interface ButtonProps extends React.ButtonHTMLAttributes<HTMLButtonElement> {
  variant?: 'primary' | 'secondary' | 'danger'
  size?: 'sm' | 'md'
}

export function Button({ 
  variant = 'primary', 
  size = 'md', 
  className, 
  disabled,
  children, 
  ...props 
}: ButtonProps) {
  return (
    <button
      {...props}
      disabled={disabled}
      className={cn(
        'font-bold tracking-wider uppercase transition-colors',
        'focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-offset-tui-bg',
        size === 'sm' ? 'px-3 py-1.5 text-xs' : 'px-4 py-2 text-sm',
        variant === 'primary' && [
          'bg-tui-accent text-tui-bg',
          'hover:bg-tui-accent/80',
          'focus:ring-tui-accent',
          'disabled:bg-tui-dim disabled:cursor-not-allowed',
        ],
        variant === 'secondary' && [
          'border border-tui-border text-tui-text',
          'hover:bg-tui-dim/20',
          'focus:ring-tui-border',
          'disabled:text-tui-dim disabled:cursor-not-allowed',
        ],
        variant === 'danger' && [
          'bg-ctp-red text-white',
          'hover:bg-ctp-red/80',
          'focus:ring-ctp-red',
          'disabled:bg-tui-dim disabled:cursor-not-allowed',
        ],
        className
      )}
    >
      {children}
    </button>
  )
}
