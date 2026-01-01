defmodule Squads.Agents do
  @moduledoc """
  Context module for managing agents.
  """

  import Ecto.Query, warn: false

  alias Squads.Repo
  alias Squads.Agents.Agent
  alias Squads.Agents.NameGenerator
  alias Squads.Agents.Roles

  @doc """
  Lists all agents for a squad.
  """
  @spec list_agents_for_squad(Ecto.UUID.t()) :: [Agent.t()]
  def list_agents_for_squad(squad_id) do
    Agent
    |> where([a], a.squad_id == ^squad_id)
    |> Repo.all()
  end

  @doc """
  Lists all agents for a project (across all squads).
  """
  @spec list_agents_for_project(Ecto.UUID.t()) :: [Agent.t()]
  def list_agents_for_project(project_id) do
    Agent
    |> join(:inner, [a], s in Squads.Squads.Squad, on: a.squad_id == s.id)
    |> where([a, s], s.project_id == ^project_id)
    |> preload(:squad)
    |> Repo.all()
  end

  @doc """
  Gets an agent by ID.
  """
  @spec get_agent(Ecto.UUID.t()) :: Agent.t() | nil
  def get_agent(id) do
    Repo.get(Agent, id)
  end

  @doc """
  Gets an agent by ID, raising if not found.
  """
  @spec get_agent!(Ecto.UUID.t()) :: Agent.t()
  def get_agent!(id) do
    Repo.get!(Agent, id)
  end

  @doc """
  Gets an agent by slug within a squad.
  """
  @spec get_agent_by_slug(Ecto.UUID.t(), String.t()) :: Agent.t() | nil
  def get_agent_by_slug(squad_id, slug) do
    Repo.get_by(Agent, squad_id: squad_id, slug: slug)
  end

  @doc """
  Gets an agent by name within a project.
  """
  @spec get_agent_by_name(Ecto.UUID.t(), String.t()) :: Agent.t() | nil
  def get_agent_by_name(project_id, name) do
    Agent
    |> join(:inner, [a], s in Squads.Squads.Squad, on: a.squad_id == s.id)
    |> where([a, s], s.project_id == ^project_id and a.name == ^name)
    |> Repo.one()
  end

  @doc """
  Resolves a list of agent names to their UUIDs within a project.
  Returns {:ok, uuids} if all names are found, {:error, missing_names} otherwise.
  """
  @spec resolve_agent_names(Ecto.UUID.t(), [String.t()]) ::
          {:ok, [Ecto.UUID.t()]} | {:error, [String.t()]}
  def resolve_agent_names(project_id, names) when is_list(names) do
    agents =
      Agent
      |> join(:inner, [a], s in Squads.Squads.Squad, on: a.squad_id == s.id)
      |> where([a, s], s.project_id == ^project_id and a.name in ^names)
      |> select([a], {a.name, a.id})
      |> Repo.all()
      |> Map.new()

    missing = Enum.filter(names, fn name -> not Map.has_key?(agents, name) end)

    if missing == [] do
      {:ok, Enum.map(names, fn name -> Map.get(agents, name) end)}
    else
      {:error, missing}
    end
  end

  @doc """
  Creates an agent for a squad, either with an auto-generated name or explicit attributes.
  """
  def create_agent_for_squad(squad_id, params) do
    if params["name"] && params["slug"] do
      # Explicit name/slug provided
      attrs = %{
        squad_id: squad_id,
        name: params["name"],
        slug: params["slug"],
        model: params["model"],
        role: params["role"] || Roles.default_role_id(),
        level: params["level"] || Roles.default_level_id(),
        system_instruction: params["system_instruction"],
        status: params["status"] || "idle"
      }

      create_agent(attrs)
    else
      # Auto-generate name
      opts = [
        model: params["model"],
        status: params["status"],
        role: params["role"],
        level: params["level"],
        system_instruction: params["system_instruction"]
      ]

      create_agent_with_name(squad_id, opts)
    end
  end

  @doc """
  Creates an agent with auto-generated name.
  """
  @spec create_agent_with_name(Ecto.UUID.t(), keyword()) ::
          {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def create_agent_with_name(squad_id, opts \\ []) do
    name = NameGenerator.generate()
    slug = NameGenerator.to_slug(name)

    attrs = %{
      squad_id: squad_id,
      name: name,
      slug: slug,
      model: opts[:model],
      role: opts[:role] || Roles.default_role_id(),
      level: opts[:level] || Roles.default_level_id(),
      system_instruction: opts[:system_instruction],
      status: opts[:status] || "idle"
    }

    create_agent(attrs)
  end

  @doc """
  Creates an agent with explicit attributes.
  """
  @spec create_agent(map()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def create_agent(attrs) do
    %Agent{}
    |> Agent.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an agent.
  """
  @spec update_agent(Agent.t(), map()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def update_agent(%Agent{} = agent, attrs) do
    agent
    |> Agent.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an agent.
  """
  @spec delete_agent(Agent.t()) :: {:ok, Agent.t()} | {:error, Ecto.Changeset.t()}
  def delete_agent(%Agent{} = agent) do
    Repo.delete(agent)
  end

  @doc """
  Gets a squad by ID.
  """
  def get_squad(id) do
    case Repo.get(Squads.Agents.Squad, id) do
      nil -> {:error, :not_found}
      squad -> {:ok, squad}
    end
  end
end
