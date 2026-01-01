defmodule SquadsWeb.API.MailJSON do
  def index(%{messages: messages}) do
    %{data: Enum.map(messages, &data/1)}
  end

  def threads_index(%{threads: threads}) do
    %{data: Enum.map(threads, &thread_data/1)}
  end

  def show(%{message: message}) do
    %{data: data(message)}
  end

  def data(message) do
    %{
      id: message.id,
      subject: message.subject,
      body_md: message.body_md,
      importance: message.importance,
      ack_required: message.ack_required,
      kind: message.kind,
      thread_id: message.thread_id,
      sender: sender(message.sender),
      recipients: Enum.map(message.recipients, &recipient/1),
      inserted_at: message.inserted_at,
      updated_at: message.updated_at
    }
  end

  defp sender(nil), do: nil

  defp sender(agent) do
    %{
      id: agent.id,
      name: agent.name,
      slug: agent.slug
    }
  end

  defp recipient(recipient) do
    %{
      agent_id: recipient.agent_id,
      recipient_type: recipient.recipient_type,
      read_at: recipient.read_at,
      acknowledged_at: recipient.acknowledged_at
    }
  end

  defp thread_data(thread) do
    # Calculate derived fields from preloaded messages if available
    {message_count, unread_count, participants} =
      if Ecto.assoc_loaded?(thread.messages) do
        msgs = thread.messages
        count = length(msgs)

        # For now we don't have per-user read state on threads easily available here without more context
        # So we'll just placeholder unread_count or calculate it if we had a current user context
        unread = 0

        parts =
          msgs
          |> Enum.flat_map(fn m ->
            [m.sender_id] ++ Enum.map(m.recipients || [], & &1.agent_id)
          end)
          |> Enum.uniq()
          |> Enum.reject(&is_nil/1)

        {count, unread, parts}
      else
        {0, 0, []}
      end

    %{
      id: thread.id,
      subject: thread.subject,
      last_message_at: thread.last_message_at,
      project_id: thread.project_id,
      ticket_id: thread.ticket_id,
      message_count: message_count,
      unread_count: unread_count,
      participants: participants,
      inserted_at: thread.inserted_at,
      updated_at: thread.updated_at
    }
  end
end
