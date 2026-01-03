defmodule SquadsWeb.API.SquadJSON do
  @moduledoc """
  JSON rendering for squad resources.
  """

  alias Squads.Squads.Squad
  alias Squads.Agents.Agent
  alias Squads.OpenCode.Status

  def index(%{squads: squads}) do
    %{data: Enum.map(squads, &squad_data/1)}
  end

  def show(%{squad: squad}) do
    %{data: squad_data(squad)}
  end

  def agents(%{agents: agents}) do
    %{data: Enum.map(agents, &agent_data/1)}
  end

  def message_sent(%{message: message}) do
    %{
      data: %{
        id: message.id,
        subject: message.subject,
        recipient_count: length(message.recipients)
      }
    }
  end

  defp squad_data(%Squad{} = squad) do
    base = %{
      id: squad.id,
      name: squad.name,
      description: squad.description,
      project_id: squad.project_id,
      opencode_status: opencode_status(squad),
      inserted_at: squad.inserted_at,
      updated_at: squad.updated_at
    }

    # Include agents if preloaded
    if Ecto.assoc_loaded?(squad.agents) do
      Map.put(base, :agents, Enum.map(squad.agents, &agent_data/1))
    else
      base
    end
  end

  defp opencode_status(%Squad{} = squad) do
    project_path =
      if Ecto.assoc_loaded?(squad.project) && squad.project do
        squad.project.path
      end

    status = if is_binary(project_path), do: Status.get(project_path), else: :provisioning
    Atom.to_string(status)
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
