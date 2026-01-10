ExUnit.start()
Ecto.Adapters.SQL.Sandbox.mode(Squads.Repo, :manual)
Mox.defmock(Squads.OpenCode.ClientMock, for: Squads.OpenCode.Client)
Mox.defmock(Squads.GitHub.ClientMock, for: Squads.GitHub.Client)
