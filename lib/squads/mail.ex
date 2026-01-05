defmodule Squads.Mail do
  @moduledoc """
  The Mail context for in-house agent communication.
  """
  import Ecto.Query, warn: false
  alias Squads.Repo

  alias Squads.Mail.{Thread, Message, Recipient, Attachment}

  # ============================================================================
  # Mailbox Queries
  # ============================================================================

  @doc """
  Lists messages in an agent's inbox.
  """
  def list_inbox(agent_id, opts \\ []) do
    limit = opts[:limit] || 20
    since_ts = opts[:since_ts]
    urgent_only = opts[:urgent_only] || false

    query =
      Message
      |> join(:inner, [m], r in Recipient, on: r.message_id == m.id)
      |> where([m, r], r.agent_id == ^agent_id)
      |> order_by([m, r], desc: m.inserted_at)
      |> limit(^limit)

    query = if since_ts, do: where(query, [m, r], m.inserted_at > ^since_ts), else: query

    query =
      if urgent_only, do: where(query, [m, r], m.importance in ["high", "urgent"]), else: query

    query
    |> preload([:sender, :thread, recipients: :agent])
    |> Repo.all()
  end

  @doc """
  Lists mail threads, optionally filtered by project.
  """
  def list_threads(opts \\ []) do
    project_id = opts[:project_id]

    query =
      Thread
      |> order_by(desc: :last_message_at)

    query = if project_id, do: where(query, project_id: ^project_id), else: query

    query
    |> Repo.all()
    |> Repo.preload(messages: [:sender, recipients: :agent])
  end

  @doc """
  Gets a message by ID.
  """
  def get_message(id) do
    Message
    |> Repo.get(id)
    |> Repo.preload([:sender, :thread, recipients: :agent])
  end

  @doc """
  Fetches a message by ID with a tuple result.
  """
  def fetch_message(id) do
    case get_message(id) do
      nil -> {:error, :not_found}
      message -> {:ok, message}
    end
  end

  @doc """
  Gets a message by ID, raising if not found.
  """
  def get_message!(id) do
    case get_message(id) do
      nil -> raise Ecto.NoResultsError, queryable: Message
      message -> message
    end
  end

  @doc """
  Lists all messages in a thread.
  """
  def list_thread_messages(thread_id) do
    Message
    |> where(thread_id: ^thread_id)
    |> order_by(asc: :inserted_at)
    |> preload([:sender, :attachments, recipients: :agent])
    |> Repo.all()
  end

  # ============================================================================
  # Sending & Replying
  # ============================================================================

  @doc """
  Sends a new message by creating a thread and message.
  """
  def send_message(attrs) do
    Repo.transaction(fn ->
      project_id = get_attr(attrs, :project_id)
      ticket_id = get_attr(attrs, :ticket_id)
      subject = get_attr(attrs, :subject)
      thread_id = get_attr(attrs, :thread_id)

      if !subject || subject == "" do
        Repo.rollback(:missing_subject)
      end

      if !project_id do
        Repo.rollback(:missing_project_id)
      end

      thread_attrs = %{
        subject: subject,
        project_id: project_id,
        ticket_id: ticket_id,
        last_message_at: DateTime.utc_now() |> DateTime.truncate(:second)
      }

      thread =
        case thread_id do
          nil ->
            %Thread{}
            |> Thread.changeset(thread_attrs)
            |> Repo.insert()

          id ->
            case Repo.get(Thread, id) do
              nil ->
                {:error, :not_found}

              thread ->
                thread
                |> Thread.changeset(%{last_message_at: thread_attrs.last_message_at})
                |> Repo.update()
            end
        end
        |> case do
          {:ok, thread} -> thread
          {:error, reason} -> Repo.rollback(reason)
        end

      message_attrs =
        attrs
        |> extract_message_attrs()
        |> Map.put(:thread_id, thread.id)

      message =
        %Message{}
        |> Message.changeset(message_attrs)
        |> Repo.insert()
        |> case do
          {:ok, message} -> message
          {:error, reason} -> Repo.rollback(reason)
        end

      to = get_attr(attrs, :to) || []
      cc = get_attr(attrs, :cc) || []
      bcc = get_attr(attrs, :bcc) || []
      attachments = get_attr(attrs, :attachments)

      with :ok <- create_recipients(to, "to", message.id),
           :ok <- create_recipients(cc, "cc", message.id),
           :ok <- create_recipients(bcc, "bcc", message.id),
           :ok <- create_attachments(attachments, message.id) do
        message = message |> Repo.preload([:sender, :thread, :recipients, :attachments])

        Squads.Events.create_event(%{
          project_id: project_id,
          # Can be nil if human
          agent_id: message.sender_id,
          kind: "mail.sent",
          occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
          payload: %{
            message_id: message.id,
            subject: message.subject,
            thread_id: message.thread_id,
            recipients: Enum.map(message.recipients, & &1.agent_id),
            author_name: message.author_name
          }
        })

        message
      else
        {:error, reason} -> Repo.rollback(reason)
      end
    end)
  end

  @doc """
  Replies to a message.
  """
  def reply_to_message(original_message_id, sender_id, body_md, opts \\ []) do
    original = get_message!(original_message_id)

    # Default recipients: original sender + other original recipients (excluding new sender)
    to_ids =
      ([original.sender_id] ++ Enum.map(original.recipients, & &1.agent_id))
      |> Enum.reject(&(&1 == sender_id))
      |> Enum.uniq()

    importance = opts[:importance]
    ack_required = opts[:ack_required]

    send_message(%{
      thread_id: original.thread_id,
      project_id: original.thread.project_id,
      sender_id: sender_id,
      subject: "Re: #{original.subject}",
      body_md: body_md,
      importance: importance || original.importance,
      ack_required: ack_required || original.ack_required,
      to: to_ids
    })
  end

  # ============================================================================
  # Read & Ack
  # ============================================================================

  @doc """
  Marks a message as read for an agent.
  """
  def mark_as_read(message_id, agent_id) do
    Recipient
    |> Repo.get_by(message_id: message_id, agent_id: agent_id)
    |> case do
      nil ->
        {:error, :not_found}

      recipient ->
        with {:ok, updated} <- recipient |> Recipient.read_changeset() |> Repo.update() do
          # Load message to get project_id
          message = get_message!(message_id)

          Squads.Events.create_event(%{
            project_id: message.thread.project_id,
            agent_id: agent_id,
            kind: "mail.read",
            occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
            payload: %{message_id: message_id}
          })

          {:ok, updated}
        end
    end
  end

  @doc """
  Acknowledges a message for an agent.
  """
  def acknowledge(message_id, agent_id) do
    Recipient
    |> Repo.get_by(message_id: message_id, agent_id: agent_id)
    |> case do
      nil ->
        {:error, :not_found}

      recipient ->
        with {:ok, updated} <- recipient |> Recipient.acknowledge_changeset() |> Repo.update() do
          # Load message to get project_id
          message = get_message!(message_id)

          Squads.Events.create_event(%{
            project_id: message.thread.project_id,
            agent_id: agent_id,
            kind: "mail.acknowledged",
            occurred_at: DateTime.utc_now() |> DateTime.truncate(:second),
            payload: %{message_id: message_id}
          })

          {:ok, updated}
        end
    end
  end

  # ============================================================================
  # Internal Helpers
  # ============================================================================

  defp get_attr(attrs, key) do
    Map.get(attrs, key, Map.get(attrs, Atom.to_string(key)))
  end

  defp extract_message_attrs(attrs) do
    allowed_keys = [
      :subject,
      :body_md,
      :importance,
      :ack_required,
      :kind,
      :sender_id,
      :author_name
    ]

    Enum.reduce(allowed_keys, %{}, fn key, acc ->
      case get_attr(attrs, key) do
        nil -> acc
        value -> Map.put(acc, key, value)
      end
    end)
  end

  defp create_recipients(list, type, message_id) do
    Enum.reduce_while(list, :ok, fn recipient_data, :ok ->
      recipient_attrs =
        case recipient_data do
          id when is_binary(id) ->
            {:ok, %{agent_id: id, message_id: message_id, recipient_type: type}}

          map when is_map(map) ->
            {:ok, map |> Map.put(:message_id, message_id) |> Map.put_new(:recipient_type, type)}

          _ ->
            {:error, :invalid_recipient}
        end

      with {:ok, attrs} <- recipient_attrs,
           {:ok, _recipient} <-
             %Recipient{}
             |> Recipient.changeset(attrs)
             |> Repo.insert() do
        {:cont, :ok}
      else
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_attachments(nil, _message_id), do: :ok
  defp create_attachments([], _message_id), do: :ok

  defp create_attachments(attachments, message_id) when is_list(attachments) do
    Enum.reduce_while(attachments, :ok, fn attach_attrs, :ok ->
      %Attachment{}
      |> Attachment.changeset(Map.put(attach_attrs, :message_id, message_id))
      |> Repo.insert()
      |> case do
        {:ok, _attachment} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp create_attachments(_attachments, _message_id) do
    {:error, :invalid_attachments}
  end

  @doc """
  Searches messages by subject or body.
  """
  def search_messages(project_id, query_str, limit \\ 20) do
    pattern = "%#{query_str}%"

    Message
    |> join(:inner, [m], t in Thread, on: m.thread_id == t.id)
    |> where([m, t], t.project_id == ^project_id)
    |> where([m, t], like(m.subject, ^pattern) or like(m.body_md, ^pattern))
    |> order_by([m, t], desc: m.inserted_at)
    |> limit(^limit)
    |> preload([:sender, :thread, :recipients])
    |> Repo.all()
  end
end
