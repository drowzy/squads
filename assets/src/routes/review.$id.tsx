import { createFileRoute, useNavigate } from '@tanstack/react-router'
import { useEffect } from 'react'

export const Route = createFileRoute('/review/$id')({
  component: ReviewIdRedirect,
})

function ReviewIdRedirect() {
  const { id } = Route.useParams()
  const navigate = useNavigate()

  useEffect(() => {
    const target = id.startsWith('rev_') ? `/fs-reviews/${id}` : '/review'
    navigate({ to: target as any, replace: true })
  }, [id, navigate])

  return null
}
