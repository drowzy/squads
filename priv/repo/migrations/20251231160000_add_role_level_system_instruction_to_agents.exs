defmodule Squads.Repo.Migrations.AddRoleLevelSystemInstructionToAgents do
  use Ecto.Migration

  def change do
    alter table(:agents) do
      add :role, :string, null: false, default: "fullstack_engineer"
      add :level, :string, null: false, default: "senior"
      add :system_instruction, :text
    end
  end
end
