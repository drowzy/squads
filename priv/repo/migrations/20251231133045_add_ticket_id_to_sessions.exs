defmodule Squads.Repo.Migrations.AddTicketIdToSessions do
  use Ecto.Migration

  def change do
    alter table(:sessions) do
      add :ticket_id, references(:tickets, type: :binary_id, on_delete: :nilify_all)
    end

    create index(:sessions, [:ticket_id])
  end
end
