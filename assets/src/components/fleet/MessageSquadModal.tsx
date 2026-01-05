import React, { useState } from 'react'
import { useMessageSquad, Squad } from '../../api/queries'
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogFooter,
} from '../ui/dialog'
import { Button } from '../ui/button'
import { Label } from '../ui/label'

interface MessageSquadModalProps {
  fromSquad: Squad
  toSquad: Squad
  isOpen: boolean
  onClose: () => void
}

export function MessageSquadModal({
  fromSquad,
  toSquad,
  isOpen,
  onClose,
}: MessageSquadModalProps) {
  const [subject, setSubject] = useState('')
  const [body, setBody] = useState('')
  const messageSquad = useMessageSquad()

  const handleSubmit = (e: React.FormEvent) => {
    e.preventDefault()
    messageSquad.mutate(
      {
        from_squad_id: fromSquad.id,
        to_squad_id: toSquad.id,
        subject,
        body,
      },
      {
        onSuccess: () => {
          setSubject('')
          setBody('')
          onClose()
        },
      }
    )
  }

  return (
    <Dialog open={isOpen} onOpenChange={onClose}>
      <DialogContent className="sm:max-w-[500px]">
        <DialogHeader>
          <DialogTitle>Message Squad: {toSquad.name}</DialogTitle>
          <div className="text-xs text-muted-foreground">
            From: {fromSquad.name} ({fromSquad.project_name || 'Current Project'})
          </div>
        </DialogHeader>

        <form onSubmit={handleSubmit} className="space-y-4 py-4">
          <div className="space-y-2">
            <Label htmlFor="subject">Subject</Label>
            <input
              id="subject"
              className="flex h-10 w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background file:border-0 file:bg-transparent file:text-sm file:font-medium placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
              placeholder="Requirement for API..."
              value={subject}
              onChange={(e) => setSubject(e.target.value)}
              required
            />
          </div>
          <div className="space-y-2">
            <Label htmlFor="body">Message (Markdown)</Label>
            <textarea
              id="body"
              className="flex min-h-[150px] w-full rounded-md border border-input bg-background px-3 py-2 text-sm ring-offset-background placeholder:text-muted-foreground focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-ring focus-visible:ring-offset-2 disabled:cursor-not-allowed disabled:opacity-50"
              placeholder="We need a new endpoint for..."
              value={body}
              onChange={(e) => setBody(e.target.value)}
              required
            />
          </div>

          <DialogFooter>
            <Button
              type="button"
              variant="outline"
              onClick={onClose}
              disabled={messageSquad.isPending}
            >
              Cancel
            </Button>
            <Button type="submit" disabled={messageSquad.isPending}>
              {messageSquad.isPending ? 'Sending...' : 'Send Message'}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}
