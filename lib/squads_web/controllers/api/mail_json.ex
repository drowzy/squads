defmodule SquadsWeb.API.MailJSON do
  def index(%{messages: messages}) do
    %{data: Enum.map(messages, &data/1)}
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
end
