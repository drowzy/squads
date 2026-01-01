import { useState } from 'react'
import { FolderOpen, ChevronDown, ChevronUp } from 'lucide-react'
import { Modal, FormField, Input, Button } from './Modal'
import { useCreateProject } from '../api/queries'
import { useNotifications } from './Notifications'
import { FolderBrowser } from './FolderBrowser'

interface ProjectCreateModalProps {
  isOpen: boolean
  onClose: () => void
}

export function ProjectCreateModal({ isOpen, onClose }: ProjectCreateModalProps) {
  const [path, setPath] = useState('')
  const [name, setName] = useState('')
  const [showBrowser, setShowBrowser] = useState(true)
  const [errors, setErrors] = useState<{ path?: string; name?: string }>({})
  
  const createProject = useCreateProject()
  const { addNotification } = useNotifications()

  const handleSubmit = async (e: React.FormEvent) => {
    e.preventDefault()
    
    // Validate
    const newErrors: typeof errors = {}
    if (!path.trim()) {
      newErrors.path = 'Path is required'
    } else if (!path.startsWith('/')) {
      newErrors.path = 'Path must be absolute (start with /)'
    }
    if (!name.trim()) {
      newErrors.name = 'Name is required'
    }
    
    if (Object.keys(newErrors).length > 0) {
      setErrors(newErrors)
      return
    }
    
    try {
      await createProject.mutateAsync({ path: path.trim(), name: name.trim() })
      addNotification({
        type: 'success',
        title: 'Project Created',
        message: `Project "${name}" initialized at ${path}`,
      })
      // Reset form and close
      resetForm()
      onClose()
    } catch (err) {
      const message = err instanceof Error ? err.message : 'Failed to create project'
      addNotification({
        type: 'error',
        title: 'Creation Failed',
        message,
      })
    }
  }

  const resetForm = () => {
    setPath('')
    setName('')
    setShowBrowser(true)
    setErrors({})
  }

  const handleClose = () => {
    resetForm()
    onClose()
  }

  // Called when a folder is selected from the browser
  const handleFolderSelect = (selectedPath: string, suggestedName: string) => {
    setPath(selectedPath)
    setErrors(prev => ({ ...prev, path: undefined }))
    
    // Only set name if empty
    if (!name) {
      setName(suggestedName)
    }
    
    // Collapse browser after selection
    setShowBrowser(false)
  }

  // Auto-generate name from path when typing manually
  const handlePathChange = (value: string) => {
    setPath(value)
    setErrors(prev => ({ ...prev, path: undefined }))
    
    // Auto-fill name from last path segment if name is empty
    if (!name && value) {
      const segments = value.split('/').filter(Boolean)
      if (segments.length > 0) {
        const lastSegment = segments[segments.length - 1]
        // Convert kebab-case or snake_case to Title Case
        const formatted = lastSegment
          .replace(/[-_]/g, ' ')
          .replace(/\b\w/g, c => c.toUpperCase())
        setName(formatted)
      }
    }
  }

  return (
    <Modal isOpen={isOpen} onClose={handleClose} title="Initialize Project" size="lg">
      <form onSubmit={handleSubmit} className="space-y-4">
        {/* Folder Browser */}
        <div>
          <button
            type="button"
            onClick={() => setShowBrowser(!showBrowser)}
            className="flex items-center gap-2 text-sm text-tui-dim hover:text-tui-accent mb-2"
          >
            {showBrowser ? <ChevronUp size={14} /> : <ChevronDown size={14} />}
            <span>Browse directories</span>
          </button>
          
          {showBrowser && (
            <FolderBrowser onSelect={handleFolderSelect} />
          )}
        </div>

        <FormField 
          label="Directory Path" 
          error={errors.path}
          hint="Absolute path to the project directory"
        >
          <div className="relative">
            <Input
              type="text"
              value={path}
              onChange={(e) => handlePathChange(e.target.value)}
              placeholder="/home/user/projects/my-app"
              error={!!errors.path}
              className="pl-10"
            />
            <FolderOpen 
              size={16} 
              className="absolute left-3 top-1/2 -translate-y-1/2 text-tui-dim" 
            />
          </div>
        </FormField>

        <FormField 
          label="Project Name" 
          error={errors.name}
          hint="Human-readable name for this project"
        >
          <Input
            type="text"
            value={name}
            onChange={(e) => {
              setName(e.target.value)
              setErrors(prev => ({ ...prev, name: undefined }))
            }}
            placeholder="My Awesome App"
            error={!!errors.name}
          />
        </FormField>

        <div className="flex justify-end gap-3 pt-2">
          <Button type="button" variant="secondary" onClick={handleClose}>
            Cancel
          </Button>
          <Button 
            type="submit" 
            variant="primary"
            disabled={createProject.isPending}
          >
            {createProject.isPending ? 'Creating...' : 'Initialize'}
          </Button>
        </div>
      </form>
    </Modal>
  )
}
