defmodule SquadsWeb.API.SessionControllerTest do
  use SquadsWeb.ConnCase, async: true

  alias Squads.Projects
  alias Squads.Squads, as: SquadsContext
  alias Squads.Agents
  alias Squads.Sessions

  # Helper to create an agent for testing
  defp create_test_agent(context) do
    tmp_dir =
      context[:tmp_dir] ||
        System.tmp_dir!() |> Path.join("squads_test_#{:rand.uniform(1_000_000)}")

    File.mkdir_p!(tmp_dir)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, agent} =
      Agents.create_agent(%{squad_id: squad.id, name: "BlueOcean", slug: "blue-ocean"})

    %{agent: agent, project: project, squad: squad, tmp_dir: tmp_dir}
  end

  describe "GET /api/sessions" do
    @tag :tmp_dir
    test "returns empty list when no sessions", %{conn: conn} do
      conn = get(conn, ~p"/api/sessions")
      assert json_response(conn, 200)["data"] == []
    end

    @tag :tmp_dir
    test "returns list of sessions", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, _session} = Sessions.create_session(%{agent_id: agent.id, ticket_key: "bd-1"})

      conn = get(conn, ~p"/api/sessions")
      response = json_response(conn, 200)

      assert length(response["data"]) >= 1
      assert Enum.any?(response["data"], fn s -> s["ticket_key"] == "bd-1" end)
    end

    @tag :tmp_dir
    test "filters by status", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, _s1} = Sessions.create_session(%{agent_id: agent.id, status: "pending"})
      {:ok, _s2} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      conn = get(conn, ~p"/api/sessions?status=running")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["status"] == "running"
    end

    @tag :tmp_dir
    test "filters by agent_id", %{conn: conn} = context do
      %{agent: agent, squad: squad} = create_test_agent(context)

      {:ok, agent2} =
        Agents.create_agent(%{squad_id: squad.id, name: "RedLake", slug: "red-lake"})

      {:ok, _s1} = Sessions.create_session(%{agent_id: agent.id})
      {:ok, _s2} = Sessions.create_session(%{agent_id: agent2.id})

      conn = get(conn, ~p"/api/sessions?agent_id=#{agent.id}")
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["agent_id"] == agent.id
    end
  end

  describe "GET /api/sessions/:id" do
    @tag :tmp_dir
    test "returns session by id", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, ticket_key: "bd-42"})

      conn = get(conn, ~p"/api/sessions/#{session.id}")
      response = json_response(conn, 200)

      assert response["data"]["id"] == session.id
      assert response["data"]["ticket_key"] == "bd-42"
      assert response["data"]["status"] == "pending"
    end

    test "returns 404 for unknown id", %{conn: conn} do
      conn = get(conn, ~p"/api/sessions/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)["errors"]["detail"] == "Not Found"
    end
  end

  describe "POST /api/sessions" do
    @tag :tmp_dir
    test "creates a new session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)

      conn =
        post(conn, ~p"/api/sessions", %{
          "agent_id" => agent.id,
          "ticket_key" => "bd-123"
        })

      response = json_response(conn, 201)
      assert response["data"]["agent_id"] == agent.id
      assert response["data"]["ticket_key"] == "bd-123"
      assert response["data"]["status"] == "pending"
    end

    @tag :tmp_dir
    test "creates session with metadata", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)

      conn =
        post(conn, ~p"/api/sessions", %{
          "agent_id" => agent.id,
          "metadata" => %{"custom" => "data"}
        })

      response = json_response(conn, 201)
      assert response["data"]["metadata"] == %{"custom" => "data"}
    end

    test "returns error without agent_id", %{conn: conn} do
      conn = post(conn, ~p"/api/sessions", %{})

      response = json_response(conn, 422)
      assert response["errors"]["agent_id"] != nil
    end
  end

  describe "POST /api/sessions/:session_id/cancel" do
    @tag :tmp_dir
    test "cancels a pending session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      conn = post(conn, ~p"/api/sessions/#{session.id}/cancel")
      response = json_response(conn, 200)

      assert response["data"]["status"] == "cancelled"
    end

    @tag :tmp_dir
    test "returns conflict for running session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      conn = post(conn, ~p"/api/sessions/#{session.id}/cancel")
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session has already been started"
    end
  end

  describe "POST /api/sessions/:session_id/stop" do
    @tag :tmp_dir
    test "returns conflict for pending session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      conn = post(conn, ~p"/api/sessions/#{session.id}/stop")
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session is not running"
    end
  end

  describe "GET /api/sessions/:session_id/messages" do
    @tag :tmp_dir
    test "returns error for session without opencode session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      conn = get(conn, ~p"/api/sessions/#{session.id}/messages")
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session has no OpenCode session"
    end
  end

  describe "GET /api/sessions/:session_id/diff" do
    @tag :tmp_dir
    test "returns error for session without opencode session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      conn = get(conn, ~p"/api/sessions/#{session.id}/diff")
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session has no OpenCode session"
    end
  end

  describe "GET /api/sessions/:session_id/todos" do
    @tag :tmp_dir
    test "returns error for session without opencode session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      conn = get(conn, ~p"/api/sessions/#{session.id}/todos")
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session has no OpenCode session"
    end
  end

  # ============================================================================
  # Dispatch Endpoint Tests
  # ============================================================================

  describe "POST /api/sessions/:session_id/prompt" do
    @tag :tmp_dir
    test "returns error for pending session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "pending"})

      conn = post(conn, ~p"/api/sessions/#{session.id}/prompt", %{"prompt" => "Hello"})
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session is not running"
    end

    @tag :tmp_dir
    test "returns error for session without opencode session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      conn = post(conn, ~p"/api/sessions/#{session.id}/prompt", %{"prompt" => "Hello"})
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session is not running"
    end

    @tag :tmp_dir
    test "returns bad request when prompt is missing", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      conn = post(conn, ~p"/api/sessions/#{session.id}/prompt", %{})
      response = json_response(conn, 400)

      assert response["errors"]["detail"] == "missing_prompt"
    end

    test "returns 404 for unknown session", %{conn: conn} do
      conn = post(conn, ~p"/api/sessions/#{Ecto.UUID.generate()}/prompt", %{"prompt" => "Hello"})
      assert json_response(conn, 404)["errors"]["detail"] == "Not Found"
    end
  end

  describe "POST /api/sessions/:session_id/prompt_async" do
    @tag :tmp_dir
    test "returns error for session without opencode session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      conn = post(conn, ~p"/api/sessions/#{session.id}/prompt_async", %{"prompt" => "Hello"})
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session is not running"
    end

    @tag :tmp_dir
    test "returns bad request when prompt is missing", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      conn = post(conn, ~p"/api/sessions/#{session.id}/prompt_async", %{})
      response = json_response(conn, 400)

      assert response["errors"]["detail"] == "missing_prompt"
    end
  end

  describe "POST /api/sessions/:session_id/command" do
    @tag :tmp_dir
    test "returns error for session without opencode session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      conn = post(conn, ~p"/api/sessions/#{session.id}/command", %{"command" => "/help"})
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session has no OpenCode session"
    end

    @tag :tmp_dir
    test "returns bad request when command is missing", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      conn = post(conn, ~p"/api/sessions/#{session.id}/command", %{})
      response = json_response(conn, 400)

      assert response["errors"]["detail"] == "missing_command"
    end

    @tag :tmp_dir
    test "returns error for pending session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)

      {:ok, session} =
        Sessions.create_session(%{
          agent_id: agent.id,
          status: "pending",
          opencode_session_id: "oc-123"
        })

      conn = post(conn, ~p"/api/sessions/#{session.id}/command", %{"command" => "/help"})
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session is not running"
    end
  end

  describe "POST /api/sessions/:session_id/shell" do
    @tag :tmp_dir
    test "returns error for session without opencode session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id, status: "running"})

      conn = post(conn, ~p"/api/sessions/#{session.id}/shell", %{"command" => "mix test"})
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session has no OpenCode session"
    end

    @tag :tmp_dir
    test "returns bad request when command is missing", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)
      {:ok, session} = Sessions.create_session(%{agent_id: agent.id})

      conn = post(conn, ~p"/api/sessions/#{session.id}/shell", %{})
      response = json_response(conn, 400)

      assert response["errors"]["detail"] == "missing_command"
    end

    @tag :tmp_dir
    test "returns error for completed session", %{conn: conn} = context do
      %{agent: agent} = create_test_agent(context)

      {:ok, session} =
        Sessions.create_session(%{
          agent_id: agent.id,
          status: "completed",
          opencode_session_id: "oc-123"
        })

      conn = post(conn, ~p"/api/sessions/#{session.id}/shell", %{"command" => "mix test"})
      response = json_response(conn, 409)

      assert response["errors"]["detail"] == "Session is not running"
    end
  end
end

defmodule SquadsWeb.API.SessionControllerPromptIntegrationTest do
  use SquadsWeb.ConnCase, async: false

  alias Squads.Agents
  alias Squads.Projects
  alias Squads.Sessions
  alias Squads.Squads, as: SquadsContext

  defp create_test_agent(context) do
    tmp_dir =
      context[:tmp_dir] ||
        System.tmp_dir!() |> Path.join("squads_test_#{:rand.uniform(1_000_000)}")

    File.mkdir_p!(tmp_dir)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, agent} =
      Agents.create_agent(%{squad_id: squad.id, name: "BlueOcean", slug: "blue-ocean"})

    %{agent: agent, project: project, squad: squad, tmp_dir: tmp_dir}
  end

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  @tag :tmp_dir
  @tag :integration
  @tag timeout: 180_000
  test "prompt async returns response via messages", %{conn: conn} = context do
    if System.find_executable("opencode") == nil or System.get_env("OPENCODE_INTEGRATION") != "1" do
      :ok
    else
      pid = Process.whereis(Squads.OpenCode.Server)

      if pid do
        Ecto.Adapters.SQL.Sandbox.allow(Squads.Repo, self(), pid)
      end

      %{agent: agent} = create_test_agent(context)

      {:ok, session} =
        Sessions.create_and_start_session(%{
          agent_id: agent.id,
          title: "Prompt Integration"
        })

      conn =
        post(conn, ~p"/api/sessions/#{session.id}/prompt_async", %{
          "prompt" => "Hello",
          "agent" => "plan"
        })

      assert json_response(conn, 202)["data"]

      {found?, messages} = await_assistant_message(session.id, 48, 2_500)

      assert found?,
             "Expected assistant response; last messages: #{inspect(messages)}"
    end
  end

  defp await_assistant_message(session_id, attempts, delay_ms) do
    Enum.reduce_while(1..attempts, {false, []}, fn _, _acc ->
      messages = fetch_messages(session_id)

      if has_assistant_message?(messages) do
        {:halt, {true, messages}}
      else
        Process.sleep(delay_ms)
        {:cont, {false, messages}}
      end
    end)
  end

  defp fetch_messages(session_id) do
    build_conn()
    |> put_req_header("accept", "application/json")
    |> get(~p"/api/sessions/#{session_id}/messages?limit=100")
    |> json_response(200)
    |> Map.get("data", [])
  end

  defp has_assistant_message?(messages) do
    Enum.any?(messages, fn message ->
      case message do
        %{"info" => %{"role" => role}} -> role == "assistant"
        _ -> false
      end
    end)
  end
end
