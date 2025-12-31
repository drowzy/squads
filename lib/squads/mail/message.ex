defmodule Squads.Mail.Message do
  @moduledoc """
  A single mail message within a thread.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Mail.{Thread, Recipient, Attachment}
  alias Squads.Agents.Agent

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @importances ~w(low normal high urgent)
  @kinds ~w(text activity notification)

  schema "mail_messages" do
    field :subject, :string
    field :body_md, :string
    field :importance, :string, default: "normal"
    field :ack_required, :boolean, default: false
    field :kind, :string, default: "text"

    belongs_to :thread, Thread
    belongs_to :sender, Agent
    has_many :recipients, Recipient
    has_many :attachments, Attachment

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(message, attrs) do
    message
    |> cast(attrs, [:subject, :body_md, :importance, :ack_required, :kind, :thread_id, :sender_id])
    |> validate_required([:body_md, :thread_id, :sender_id])
    |> validate_inclusion(:importance, @importances)
    |> validate_inclusion(:kind, @kinds)
    |> foreign_key_constraint(:thread_id)
    |> foreign_key_constraint(:sender_id)
  end
end
