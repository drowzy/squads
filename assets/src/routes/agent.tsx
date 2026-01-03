import { createFileRoute, Outlet } from '@tanstack/react-router'

export const Route = createFileRoute('/agent')({
  component: AgentLayout,
})

function AgentLayout() {
  return (
    <div className="h-full">
      <Outlet />
    </div>
  )
}
