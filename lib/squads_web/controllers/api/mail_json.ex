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
      sender_name:
        message.author_name || if(message.sender, do: message.sender.name, else: "Unknown"),
      to:
        Enum.filter(message.recipients, &(&1.recipient_type == "to"))
        |> Enum.map(&recipient_name/1),
      cc:
        Enum.filter(message.recipients, &(&1.recipient_type == "cc"))
        |> Enum.map(&recipient_name/1),
      recipients: Enum.map(message.recipients, &recipient/1),
      inserted_at: message.inserted_at,
      updated_at: message.updated_at
    }
  end

  defp recipient_name(r) do
    if Ecto.assoc_loaded?(r.agent) && r.agent do
      r.agent.name
    else
      r.agent_id
    end
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

        # Per-user read state on threads is not currently available in this context.
        # Returning 0 as the unread count. Future implementation will calculate this based on user context.
        unread = 0

        parts =
          msgs
          |> Enum.flat_map(fn m ->
            sender_name = m.author_name || (m.sender && m.sender.name) || "Unknown"

            recipients =
              Enum.map(m.recipients || [], fn r ->
                if Ecto.assoc_loaded?(r.agent) && r.agent, do: r.agent.name, else: "Unknown"
              end)

            [sender_name] ++ recipients
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
