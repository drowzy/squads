defmodule Squads.Mail.Thread do
  @moduledoc """
  A thread groups mail messages together within a project.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Squads.Projects.Project
  alias Squads.Mail.Message

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "mail_threads" do
    field :subject, :string
    field :last_message_at, :utc_datetime

    belongs_to :project, Project
    has_many :messages, Message

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(thread, attrs) do
    thread
    |> cast(attrs, [:subject, :project_id, :last_message_at])
    |> validate_required([:subject, :project_id])
    |> foreign_key_constraint(:project_id)
  end
end
