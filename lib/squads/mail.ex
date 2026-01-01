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
    |> preload([:sender, :thread, :recipients])
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
    |> Repo.preload(messages: [:sender, :recipients])
  end

  @doc """
  Gets a message by ID.
  """
  def get_message!(id),
    do: Repo.get!(Message, id) |> Repo.preload([:sender, :thread, :recipients])

  @doc """
  Lists all messages in a thread.
  """
  def list_thread_messages(thread_id) do
    Message
    |> where(thread_id: ^thread_id)
    |> order_by(asc: :inserted_at)
    |> preload([:sender, :recipients, :attachments])
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
      # 1. Create or find thread
      project_id = attrs[:project_id] || attrs["project_id"]
      ticket_id = attrs[:ticket_id] || attrs["ticket_id"]
      subject = attrs[:subject] || attrs["subject"]
      thread_id = attrs[:thread_id] || attrs["thread_id"]

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
            |> Repo.insert!()

          id ->
            Repo.get!(Thread, id)
            |> Thread.changeset(%{last_message_at: thread_attrs.last_message_at})
            |> Repo.update!()
        end

      # 2. Create message
      message_attrs =
        attrs
        |> Enum.map(fn {k, v} ->
          {if(is_binary(k), do: String.to_existing_atom(k), else: k), v}
        end)
        |> Map.new()
        |> Map.take([
          :subject,
          :body_md,
          :importance,
          :ack_required,
          :kind,
          :sender_id,
          :author_name
        ])
        |> Map.put(:thread_id, thread.id)

      message =
        %Message{}
        |> Message.changeset(message_attrs)
        |> Repo.insert!()

      # 3. Create recipients
      to = attrs[:to] || attrs["to"] || []
      cc = attrs[:cc] || attrs["cc"] || []
      bcc = attrs[:bcc] || attrs["bcc"] || []

      create_recipients(to, "to", message.id)
      create_recipients(cc, "cc", message.id)
      create_recipients(bcc, "bcc", message.id)

      # 4. Handle attachments (simplified)
      attachments = attrs[:attachments] || attrs["attachments"]

      if attachments do
        Enum.each(attachments, fn attach_attrs ->
          %Attachment{}
          |> Attachment.changeset(Map.put(attach_attrs, :message_id, message.id))
          |> Repo.insert!()
        end)
      end

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

  defp create_recipients(list, type, message_id) do
    Enum.each(list, fn recipient_data ->
      recipient_attrs =
        case recipient_data do
          id when is_binary(id) ->
            %{agent_id: id, message_id: message_id, recipient_type: type}

          map when is_map(map) ->
            map |> Map.put(:message_id, message_id) |> Map.put_new(:recipient_type, type)
        end

      %Recipient{}
      |> Recipient.changeset(recipient_attrs)
      |> Repo.insert!()
    end)
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
