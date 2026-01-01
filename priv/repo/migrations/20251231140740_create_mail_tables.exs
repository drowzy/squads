defmodule Squads.Repo.Migrations.CreateMailTables do
  use Ecto.Migration

  def change do
    # Threads group messages together
    create table(:mail_threads, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :subject, :string

      add :project_id, references(:projects, on_delete: :delete_all, type: :binary_id),
        null: false

      add :ticket_id, references(:tickets, on_delete: :nothing, type: :binary_id)
      add :last_message_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:mail_threads, [:project_id])
    create index(:mail_threads, [:ticket_id])

    # Messages
    create table(:mail_messages, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :thread_id, references(:mail_threads, on_delete: :delete_all, type: :binary_id),
        null: false

      add :sender_id, references(:agents, on_delete: :nothing, type: :binary_id), null: true
      add :author_name, :string
      add :subject, :string
      add :body_md, :text
      add :importance, :string, default: "normal"
      add :ack_required, :boolean, default: false
      # text, activity, notification
      add :kind, :string, default: "text"

      timestamps(type: :utc_datetime)
    end

    create index(:mail_messages, [:thread_id])
    create index(:mail_messages, [:sender_id])

    # Recipients (per-message delivery)
    create table(:mail_recipients, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:mail_messages, on_delete: :delete_all, type: :binary_id),
        null: false

      add :agent_id, references(:agents, on_delete: :delete_all, type: :binary_id), null: false
      # to, cc, bcc
      add :recipient_type, :string, default: "to"
      add :read_at, :utc_datetime
      add :acknowledged_at, :utc_datetime

      timestamps(type: :utc_datetime)
    end

    create index(:mail_recipients, [:message_id])
    create index(:mail_recipients, [:agent_id])
    create unique_index(:mail_recipients, [:message_id, :agent_id])

    # Attachments
    create table(:mail_attachments, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :message_id, references(:mail_messages, on_delete: :delete_all, type: :binary_id),
        null: false

      add :filename, :string
      add :content_type, :string
      # Relative to archive
      add :file_path, :string
      add :file_hash, :string
      add :size, :integer

      timestamps(type: :utc_datetime)
    end

    create index(:mail_attachments, [:message_id])
  end
end
