defmodule Squads.Sessions.Transcripts do
  @moduledoc """
  Persisted transcript support for Sessions.

  This module syncs OpenCode messages into SQLite and serves paginated reads.

  v1 goals:
  - store raw OpenCode message payloads (JSON)
  - store indefinitely
  - support on-demand sync and pagination
  """

  import Ecto.Query, warn: false

  alias Squads.Repo
  alias Squads.Sessions.{Session, TranscriptEntry}
  alias Squads.Sessions.Messages

  @default_limit 200

  @spec sync_session_transcript(Session.t(), keyword()) ::
          {:ok, non_neg_integer()} | {:error, term()}
  def sync_session_transcript(%Session{} = session, opts \\ []) do
    with {:ok, messages} <- Messages.get_messages(session, opts) do
      now = DateTime.utc_now() |> DateTime.truncate(:second)

      now_unix = DateTime.to_unix(now)

      count =
        messages
        |> List.wrap()
        |> Enum.with_index()
        |> Enum.sort_by(fn {message, original_index} ->
          {message_sort_ts(message, now_unix), original_index}
        end)
        |> Enum.with_index()
        |> Enum.reduce(0, fn {{message, _original_index}, position}, acc ->
          case upsert_message(session, message, position, now) do
            {:ok, _} -> acc + 1
            {:error, _} -> acc
          end
        end)

      {:ok, count}
    end
  end

  @spec list_entries_for_session(Ecto.UUID.t(), keyword()) :: {list(TranscriptEntry.t()), map()}
  def list_entries_for_session(session_id, opts \\ []) do
    limit = Keyword.get(opts, :limit, @default_limit)
    after_position = Keyword.get(opts, :after_position, -1)

    query =
      TranscriptEntry
      |> where(session_id: ^session_id)
      |> where([e], e.position > ^after_position)
      |> order_by(asc: :position)
      |> limit(^limit)

    entries = Repo.all(query)

    meta = %{
      next_after_position:
        entries
        |> List.last()
        |> then(fn
          nil -> nil
          entry -> entry.position
        end)
    }

    {entries, meta}
  end

  @spec list_entries_for_sessions([Ecto.UUID.t()], keyword()) ::
          {list(TranscriptEntry.t()), map()}
  def list_entries_for_sessions(session_ids, opts \\ []) when is_list(session_ids) do
    limit = Keyword.get(opts, :limit, @default_limit)
    before_id = Keyword.get(opts, :before_id)

    query =
      TranscriptEntry
      |> where([e], e.session_id in ^session_ids)
      |> order_by(desc: :inserted_at)
      |> order_by(desc: :id)
      |> maybe_before(before_id)
      |> limit(^limit)

    entries = Repo.all(query)

    meta = %{
      next_before_id:
        entries
        |> List.last()
        |> then(fn
          nil -> nil
          entry -> entry.id
        end)
    }

    {Enum.reverse(entries), meta}
  end

  defp maybe_before(query, nil), do: query

  defp maybe_before(query, before_id) when is_binary(before_id) do
    case Repo.get(TranscriptEntry, before_id) do
      nil ->
        query

      cursor ->
        where(
          query,
          [e],
          e.inserted_at < ^cursor.inserted_at or
            (e.inserted_at == ^cursor.inserted_at and e.id < ^cursor.id)
        )
    end
  end

  defp upsert_message(%Session{} = session, message, position, now)
       when is_map(message) and is_integer(position) do
    opencode_message_id = message_id(message)

    attrs = %{
      session_id: session.id,
      opencode_message_id: opencode_message_id,
      position: position,
      role: message_role(message),
      payload: message,
      occurred_at: message_time(message) || now
    }

    changeset = TranscriptEntry.changeset(%TranscriptEntry{}, attrs)

    Repo.insert(
      changeset,
      on_conflict: {:replace, [:position, :role, :payload, :occurred_at, :updated_at]},
      conflict_target: [:session_id, :opencode_message_id]
    )
  end

  defp upsert_message(%Session{} = session, message, position, now) do
    upsert_message(session, %{"data" => message}, position, now)
  end

  defp message_id(%{"id" => id}) when is_binary(id), do: id
  defp message_id(%{id: id}) when is_binary(id), do: id

  defp message_id(%{"info" => %{"id" => id}}) when is_binary(id), do: id
  defp message_id(%{"info" => %{id: id}}) when is_binary(id), do: id

  defp message_id(_), do: "unknown-#{Ecto.UUID.generate()}"

  defp message_role(%{"role" => role}) when is_binary(role), do: role
  defp message_role(%{role: role}) when is_binary(role), do: role
  defp message_role(%{"info" => %{"role" => role}}) when is_binary(role), do: role
  defp message_role(_), do: nil

  defp message_sort_ts(message, default_unix) when is_integer(default_unix) do
    case message_time(message) do
      %DateTime{} = dt -> DateTime.to_unix(dt)
      _ -> default_unix
    end
  end

  defp message_time(%{"createdAt" => ts}) when is_binary(ts), do: parse_dt(ts)
  defp message_time(%{"time" => ts}) when is_binary(ts), do: parse_dt(ts)
  defp message_time(%{"info" => %{"createdAt" => ts}}) when is_binary(ts), do: parse_dt(ts)
  defp message_time(%{"info" => %{"time" => ts}}) when is_binary(ts), do: parse_dt(ts)
  defp message_time(_), do: nil

  defp parse_dt(ts) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> DateTime.truncate(dt, :second)
      _ -> nil
    end
  end
end
