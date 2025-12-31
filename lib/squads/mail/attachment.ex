defmodule Squads.Mail.Attachment do
  @moduledoc """
  An attachment associated with a mail message.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Mail.Message

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mail_attachments" do
    field :filename, :string
    field :content_type, :string
    field :file_path, :string
    field :file_hash, :string
    field :size, :integer

    belongs_to :message, Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(attachment, attrs) do
    attachment
    |> cast(attrs, [:filename, :content_type, :file_path, :file_hash, :size, :message_id])
    |> validate_required([:filename, :file_path, :message_id])
    |> foreign_key_constraint(:message_id)
  end
end
