defmodule Squads.Reservations do
  @moduledoc """
  The Reservations context for advisory file locking.
  """
  import Ecto.Query, warn: false
  alias Squads.Repo
  alias Squads.Reservations.FileReservation

  @doc """
  Lists active reservations for a project.
  """
  def list_active_reservations(project_id) do
    now = DateTime.utc_now()

    FileReservation
    |> where([r], r.project_id == ^project_id)
    |> where([r], r.expires_at > ^now)
    |> preload([:agent])
    |> Repo.all()
  end

  @doc """
  Reserves paths for an agent.
  """
  def reserve_paths(project_id, agent_id, paths, opts \\ []) do
    ttl = opts[:ttl_seconds] || 3600
    exclusive = opts[:exclusive] || false
    reason = opts[:reason]
    expires_at = DateTime.utc_now() |> DateTime.add(ttl, :second) |> DateTime.truncate(:second)

    Repo.transaction(fn ->
      # 1. Check for conflicts
      active = list_active_reservations(project_id)

      conflicts =
        Enum.filter(paths, fn path ->
          Enum.any?(active, fn res ->
            # Very simple conflict check: exact match or overlapping patterns
            # If either is exclusive, it's a conflict
            (res.exclusive or exclusive) and res.agent_id != agent_id and
              patterns_overlap?(res.path_pattern, path)
          end)
        end)

      if length(conflicts) > 0 do
        Repo.rollback({:conflict, conflicts})
      end

      # 2. Create reservations
      results =
        Enum.reduce_while(paths, [], fn path, acc ->
          changeset =
            FileReservation.changeset(%FileReservation{}, %{
              project_id: project_id,
              agent_id: agent_id,
              path_pattern: path,
              exclusive: exclusive,
              reason: reason,
              expires_at: expires_at
            })

          case Repo.insert(changeset) do
            {:ok, res} -> {:cont, [res | acc]}
            {:error, changeset} -> {:halt, {:error, changeset}}
          end
        end)

      case results do
        {:error, changeset} ->
          Repo.rollback({:validation_error, changeset})

        results ->
          Squads.Events.create_event(%{
            project_id: project_id,
            agent_id: agent_id,
            kind: "file_reserved",
            occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
            payload: %{
              paths: paths,
              exclusive: exclusive,
              reason: reason,
              expires_at: expires_at
            }
          })

          Enum.reverse(results)
      end
    end)
  end

  @doc """
  Releases reservations for an agent.
  """
  def release_reservations(agent_id, paths \\ nil) do
    # Get project_id before deleting
    project_id =
      FileReservation
      |> where(agent_id: ^agent_id)
      |> limit(1)
      |> select([r], r.project_id)
      |> Repo.one()

    query = from r in FileReservation, where: r.agent_id == ^agent_id

    query =
      if paths do
        where(query, [r], r.path_pattern in ^paths)
      else
        query
      end

    {count, _} = Repo.delete_all(query)

    if project_id && count > 0 do
      Squads.Events.create_event(%{
        project_id: project_id,
        agent_id: agent_id,
        kind: "file_released",
        occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
        payload: %{paths: paths, count: count}
      })
    end

    {:ok, count}
  end

  # Check if two patterns overlap (symmetric)
  defp patterns_overlap?(p1, p2) do
    # Exact match is always an overlap
    # Use fnmatch if available or a simple glob-to-regex conversion
    # For now, let's implement a symmetric glob check using Regex
    p1 == p2 or
      glob_match?(p1, p2) or glob_match?(p2, p1)
  end

  defp glob_match?(pattern, path) do
    # Convert glob pattern to regex
    # ** matches any depth, * matches within directory
    regex_pattern =
      pattern
      |> Regex.escape()
      |> String.replace("\\*\\*", ".*")
      |> String.replace("\\*", "[^/]*")

    Regex.match?(~r/^#{regex_pattern}$/, path)
  end
end
