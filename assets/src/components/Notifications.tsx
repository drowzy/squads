import React, { createContext, useContext, useState, useCallback } from 'react'

export type NotificationType = 'info' | 'success' | 'warning' | 'error' | 'system'

export interface Notification {
  id: string
  message: string
  type: NotificationType
  title?: string
  duration?: number
}

interface NotificationContextType {
  notifications: Notification[]
  addNotification: (notification: Omit<Notification, 'id'>) => void
  removeNotification: (id: string) => void
}

const NotificationContext = createContext<NotificationContextType | undefined>(undefined)

export function NotificationProvider({ children }: { children: React.ReactNode }) {
  const [notifications, setNotifications] = useState<Notification[]>([])

  const removeNotification = useCallback((id: string) => {
    setNotifications((prev) => prev.filter((n) => n.id !== id))
  }, [])

  const addNotification = useCallback((n: Omit<Notification, 'id'>) => {
    const id = Math.random().toString(36).substring(2, 9)
    const notification = { ...n, id }
    setNotifications((prev) => [...prev, notification])

    if (n.duration !== 0) {
      setTimeout(() => {
        removeNotification(id)
      }, n.duration || 5000)
    }
  }, [removeNotification])

  return (
    <NotificationContext.Provider value={{ notifications, addNotification, removeNotification }}>
      {children}
      <NotificationContainer />
    </NotificationContext.Provider>
  )
}

export function useNotifications() {
  const context = useContext(NotificationContext)
  if (!context) {
    throw new Error('useNotifications must be used within a NotificationProvider')
  }
  return context
}

function NotificationContainer() {
  const { notifications, removeNotification } = useNotifications()

  return (
    <div className="fixed bottom-4 left-4 right-4 md:left-auto md:right-6 md:bottom-6 z-50 flex flex-col gap-3 md:w-80">
      {notifications.map((n) => (
        <Toast key={n.id} notification={n} onClose={() => removeNotification(n.id)} />
      ))}
    </div>
  )
}

function Toast({ notification, onClose }: { notification: Notification; onClose: () => void }) {
  const typeStyles: Record<NotificationType, string> = {
    info: 'border-tui-text text-tui-text bg-tui-bg',
    success: 'border-tui-accent text-tui-accent bg-tui-bg',
    warning: 'border-yellow-500 text-yellow-500 bg-tui-bg',
    error: 'border-red-500 text-red-500 bg-tui-bg',
    system: 'border-tui-border-dim text-tui-dim bg-tui-bg/80',
  }

  return (
    <div 
      className={`border p-3 font-mono text-xs shadow-[4px_4px_0px_0px_rgba(0,0,0,1)] animate-in slide-in-from-right duration-300 ${typeStyles[notification.type]}`}
      onClick={onClose}
    >
      <div className="flex justify-between items-start mb-1">
        <span className="font-bold tracking-widest uppercase">
          [{notification.type}] {notification.title || 'SYSTEM MSG'}
        </span>
        <button className="opacity-50 hover:opacity-100">×</button>
      </div>
      <p className="leading-tight">{notification.message}</p>
      <div className="mt-2 h-0.5 w-full bg-tui-border/20">
        <div 
          className="h-full bg-current opacity-30 animate-out fade-out fill-mode-forwards"
          style={{ animationDuration: `${notification.duration || 5000}ms` }}
        />
      </div>
    </div>
  )
}
