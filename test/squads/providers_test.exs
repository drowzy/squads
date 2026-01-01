defmodule Squads.ProvidersTest do
  use Squads.DataCase, async: true

  alias Squads.Providers
  alias Squads.Providers.Provider
  alias Squads.Projects

  # Helper to create a project for testing
  defp create_test_project(_context \\ %{}) do
    tmp_dir = System.tmp_dir!() |> Path.join("squads_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)

    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    %{project: project}
  end

  describe "list_providers/1" do
    test "returns empty list when no providers" do
      %{project: project} = create_test_project()
      assert Providers.list_providers(project.id) == []
    end

    test "returns all providers for project ordered by name" do
      %{project: project} = create_test_project()

      {:ok, _p1} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "openai",
          name: "OpenAI"
        })

      {:ok, _p2} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "anthropic",
          name: "Anthropic"
        })

      providers = Providers.list_providers(project.id)
      assert length(providers) == 2
      # Should be ordered by name
      assert hd(providers).name == "Anthropic"
    end

    test "does not return providers from other projects" do
      %{project: project1} = create_test_project()
      %{project: project2} = create_test_project()

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project1.id,
          provider_id: "openai",
          name: "OpenAI"
        })

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project2.id,
          provider_id: "anthropic",
          name: "Anthropic"
        })

      providers = Providers.list_providers(project1.id)
      assert length(providers) == 1
      assert hd(providers).provider_id == "openai"
    end
  end

  describe "list_connected_providers/1" do
    test "returns only connected providers" do
      %{project: project} = create_test_project()

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "openai",
          name: "OpenAI",
          status: "connected"
        })

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "anthropic",
          name: "Anthropic",
          status: "disconnected"
        })

      providers = Providers.list_connected_providers(project.id)
      assert length(providers) == 1
      assert hd(providers).provider_id == "openai"
    end
  end

  describe "get_provider/1 and get_provider!/1" do
    test "get_provider returns provider by id" do
      %{project: project} = create_test_project()

      {:ok, provider} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "openai",
          name: "OpenAI"
        })

      found = Providers.get_provider(provider.id)
      assert found.id == provider.id
    end

    test "get_provider returns nil for unknown id" do
      assert Providers.get_provider(Ecto.UUID.generate()) == nil
    end

    test "get_provider! raises for unknown id" do
      assert_raise Ecto.NoResultsError, fn ->
        Providers.get_provider!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_provider_by_provider_id/2" do
    test "returns provider by project and provider_id" do
      %{project: project} = create_test_project()

      {:ok, provider} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "anthropic",
          name: "Anthropic"
        })

      found = Providers.get_provider_by_provider_id(project.id, "anthropic")
      assert found.id == provider.id
    end

    test "returns nil for unknown provider_id" do
      %{project: project} = create_test_project()
      assert Providers.get_provider_by_provider_id(project.id, "unknown") == nil
    end
  end

  describe "create_provider/1" do
    test "creates provider with required fields" do
      %{project: project} = create_test_project()

      attrs = %{
        project_id: project.id,
        provider_id: "openai",
        name: "OpenAI"
      }

      assert {:ok, provider} = Providers.create_provider(attrs)
      assert provider.provider_id == "openai"
      assert provider.name == "OpenAI"
      assert provider.status == "unknown"
    end

    test "creates provider with all fields" do
      %{project: project} = create_test_project()

      attrs = %{
        project_id: project.id,
        provider_id: "anthropic",
        name: "Anthropic",
        status: "connected",
        models: [%{"id" => "claude-3-opus", "name" => "Claude 3 Opus"}],
        default_model: "claude-3-opus",
        metadata: %{"api_version" => "2024-01-01"}
      }

      assert {:ok, provider} = Providers.create_provider(attrs)
      assert provider.status == "connected"
      assert length(provider.models) == 1
      assert provider.default_model == "claude-3-opus"
    end

    test "fails without required fields" do
      assert {:error, changeset} = Providers.create_provider(%{})
      assert "can't be blank" in errors_on(changeset).project_id
      assert "can't be blank" in errors_on(changeset).provider_id
      assert "can't be blank" in errors_on(changeset).name
    end

    test "fails with invalid status" do
      %{project: project} = create_test_project()

      attrs = %{
        project_id: project.id,
        provider_id: "openai",
        name: "OpenAI",
        status: "invalid"
      }

      assert {:error, changeset} = Providers.create_provider(attrs)
      assert "is invalid" in errors_on(changeset).status
    end

    test "enforces unique constraint on project_id + provider_id" do
      %{project: project} = create_test_project()

      attrs = %{
        project_id: project.id,
        provider_id: "openai",
        name: "OpenAI"
      }

      {:ok, _} = Providers.create_provider(attrs)
      assert {:error, changeset} = Providers.create_provider(attrs)
      # The unique constraint error can appear on either field
      errors = errors_on(changeset)
      assert Map.has_key?(errors, :project_id) or Map.has_key?(errors, :provider_id)
    end
  end

  describe "update_provider/2" do
    test "updates provider fields" do
      %{project: project} = create_test_project()

      {:ok, provider} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "openai",
          name: "OpenAI"
        })

      assert {:ok, updated} = Providers.update_provider(provider, %{status: "connected"})
      assert updated.status == "connected"
    end
  end

  describe "delete_provider/1" do
    test "deletes provider" do
      %{project: project} = create_test_project()

      {:ok, provider} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "openai",
          name: "OpenAI"
        })

      assert {:ok, _} = Providers.delete_provider(provider)
      assert Providers.get_provider(provider.id) == nil
    end
  end

  describe "list_all_models/1" do
    test "returns models from all connected providers" do
      %{project: project} = create_test_project()

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "openai",
          name: "OpenAI",
          status: "connected",
          models: [
            %{"id" => "gpt-4", "name" => "GPT-4"},
            %{"id" => "gpt-3.5", "name" => "GPT-3.5"}
          ]
        })

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "anthropic",
          name: "Anthropic",
          status: "connected",
          models: [%{"id" => "claude-3", "name" => "Claude 3"}]
        })

      models = Providers.list_all_models(project.id)
      assert length(models) == 3

      # Each model should have provider info
      assert Enum.all?(models, &Map.has_key?(&1, "provider_id"))
    end

    test "excludes models from disconnected providers" do
      %{project: project} = create_test_project()

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "openai",
          name: "OpenAI",
          status: "connected",
          models: [%{"id" => "gpt-4", "name" => "GPT-4"}]
        })

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "anthropic",
          name: "Anthropic",
          status: "disconnected",
          models: [%{"id" => "claude-3", "name" => "Claude 3"}]
        })

      models = Providers.list_all_models(project.id)
      assert length(models) == 1
      assert hd(models)["id"] == "openai/gpt-4"
      assert hd(models)["model_id"] == "gpt-4"
    end
  end

  describe "get_default_model/1" do
    test "returns default model from connected provider" do
      %{project: project} = create_test_project()

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "anthropic",
          name: "Anthropic",
          status: "connected",
          models: [
            %{"id" => "claude-3-opus", "name" => "Claude 3 Opus"},
            %{"id" => "claude-3-sonnet", "name" => "Claude 3 Sonnet"}
          ],
          default_model: "claude-3-opus"
        })

      model = Providers.get_default_model(project.id)
      assert model["id"] == "anthropic/claude-3-opus"
      assert model["model_id"] == "claude-3-opus"
      assert model["provider_id"] == "anthropic"
    end

    test "returns nil when no default set" do
      %{project: project} = create_test_project()

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "anthropic",
          name: "Anthropic",
          status: "connected",
          models: [%{"id" => "claude-3", "name" => "Claude 3"}]
        })

      assert Providers.get_default_model(project.id) == nil
    end

    test "returns nil when default model not in models list" do
      %{project: project} = create_test_project()

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "anthropic",
          name: "Anthropic",
          status: "connected",
          models: [%{"id" => "claude-3", "name" => "Claude 3"}],
          default_model: "claude-missing"
        })

      assert Providers.get_default_model(project.id) == nil
    end
  end

  describe "find_model/2" do
    test "finds model by id" do
      %{project: project} = create_test_project()

      {:ok, _} =
        Providers.create_provider(%{
          project_id: project.id,
          provider_id: "openai",
          name: "OpenAI",
          status: "connected",
          models: [%{"id" => "gpt-4", "name" => "GPT-4"}]
        })

      model = Providers.find_model(project.id, "gpt-4")
      assert model["id"] == "openai/gpt-4"
      assert model["model_id"] == "gpt-4"
      assert model["provider_id"] == "openai"
    end

    test "returns nil for unknown model" do
      %{project: project} = create_test_project()
      assert Providers.find_model(project.id, "unknown") == nil
    end
  end

  describe "Provider.statuses/0" do
    test "returns valid status values" do
      statuses = Provider.statuses()
      assert "connected" in statuses
      assert "disconnected" in statuses
      assert "error" in statuses
      assert "unknown" in statuses
    end
  end
end
