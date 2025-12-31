defmodule Squads.Mail.Recipient do
  @moduledoc """
  A recipient for a mail message, tracking read and acknowledgement status.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Mail.Message
  alias Squads.Agents.Agent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @recipient_types ~w(to cc bcc)

  schema "mail_recipients" do
    field :recipient_type, :string, default: "to"
    field :read_at, :utc_datetime
    field :acknowledged_at, :utc_datetime

    belongs_to :message, Message
    belongs_to :agent, Agent

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(recipient, attrs) do
    recipient
    |> cast(attrs, [:recipient_type, :read_at, :acknowledged_at, :message_id, :agent_id])
    |> validate_required([:message_id, :agent_id])
    |> validate_inclusion(:recipient_type, @recipient_types)
    |> foreign_key_constraint(:message_id)
    |> foreign_key_constraint(:agent_id)
    |> unique_constraint([:message_id, :agent_id])
  end

  @doc """
  Changeset for marking as read.
  """
  def read_changeset(recipient) do
    change(recipient, %{read_at: DateTime.utc_now() |> DateTime.truncate(:second)})
  end

  @doc """
  Changeset for acknowledging.
  """
  def acknowledge_changeset(recipient) do
    recipient
    |> change(%{
      acknowledged_at: DateTime.utc_now() |> DateTime.truncate(:second),
      read_at: recipient.read_at || DateTime.utc_now() |> DateTime.truncate(:second)
    })
  end
end
