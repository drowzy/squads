defmodule SquadsWeb.API.AgentJSON do
  @moduledoc """
  JSON rendering for agent resources.
  """

  alias Squads.Agents.Agent

  def index(%{agents: agents}) do
    %{data: Enum.map(agents, &agent_data/1)}
  end

  def show(%{agent: agent}) do
    %{data: agent_data(agent)}
  end

  def roles(%{
        roles: roles,
        levels: levels,
        defaults: defaults,
        system_instructions: system_instructions
      }) do
    %{
      data: %{
        roles: roles,
        levels: levels,
        defaults: defaults,
        system_instructions: system_instructions
      }
    }
  end

  defp agent_data(%Agent{} = agent) do
    %{
      id: agent.id,
      name: agent.name,
      slug: agent.slug,
      model: agent.model,
      role: agent.role,
      level: agent.level,
      system_instruction: agent.system_instruction,
      status: agent.status,
      squad_id: agent.squad_id,
      mentor_id: agent.mentor_id,
      inserted_at: agent.inserted_at,
      updated_at: agent.updated_at
    }
  end
end
