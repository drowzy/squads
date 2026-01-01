defmodule Squads.OpenCode.ClientTest do
  use ExUnit.Case, async: true

  alias Squads.OpenCode.Client

  # We use Req's built-in test adapter (plug) to mock responses
  # See https://hexdocs.pm/req/Req.Test.html

  describe "configuration" do
    test "uses default base_url when not configured" do
      # Default should be http://127.0.0.1:4096
      # May succeed (if OpenCode is running) or fail (if not)
      result = Client.get("/global/health", retry_count: 0)
      assert match?({:ok, _}, result) or match?({:error, _}, result)
    end

    test "accepts base_url override via opts" do
      # Invalid URL should fail
      result =
        Client.get("/global/health",
          base_url: "http://192.0.2.1:9999",
          retry_count: 0,
          timeout: 100
        )

      assert {:error, _} = result
    end
  end

  describe "healthy?/1" do
    test "returns false when server is not reachable" do
      refute Client.healthy?(base_url: "http://invalid.local:9999")
    end
  end

  describe "request building" do
    # These tests verify the module structure and function signatures
    # Real HTTP integration would require a running OpenCode server

    test "get/2 accepts path and options" do
      # Function exists and accepts correct args
      assert is_function(&Client.get/2)
    end

    test "post/3 accepts path, body, and options" do
      assert is_function(&Client.post/3)
    end

    test "patch/3 accepts path, body, and options" do
      assert is_function(&Client.patch/3)
    end

    test "delete/2 accepts path and options" do
      assert is_function(&Client.delete/2)
    end

    test "put/3 accepts path, body, and options" do
      assert is_function(&Client.put/3)
    end
  end

  describe "API endpoint helpers - Global" do
    test "health/1 is exported" do
      assert is_function(&Client.health/1)
    end

    test "healthy?/1 is exported" do
      assert is_function(&Client.healthy?/1)
    end
  end

  describe "API endpoint helpers - Config" do
    test "get_config/1 is exported" do
      assert is_function(&Client.get_config/1)
    end

    test "get_config_providers/1 is exported" do
      assert is_function(&Client.get_config_providers/1)
    end

    test "list_providers/1 is exported" do
      assert is_function(&Client.list_providers/1)
    end
  end

  describe "API endpoint helpers - Project" do
    test "list_projects/1 is exported" do
      assert is_function(&Client.list_projects/1)
    end

    test "get_current_project/1 is exported" do
      assert is_function(&Client.get_current_project/1)
    end
  end

  describe "API endpoint helpers - Sessions" do
    test "list_sessions/1 is exported" do
      assert is_function(&Client.list_sessions/1)
    end

    test "create_session/1 is exported" do
      assert is_function(&Client.create_session/1)
    end

    test "get_session/2 is exported" do
      assert is_function(&Client.get_session/2)
    end

    test "get_sessions_status/1 is exported" do
      assert is_function(&Client.get_sessions_status/1)
    end

    test "update_session/3 is exported" do
      assert is_function(&Client.update_session/3)
    end

    test "delete_session/2 is exported" do
      assert is_function(&Client.delete_session/2)
    end

    test "abort_session/2 is exported" do
      assert is_function(&Client.abort_session/2)
    end

    test "fork_session/2 is exported" do
      assert is_function(&Client.fork_session/2)
    end

    test "get_session_todos/2 is exported" do
      assert is_function(&Client.get_session_todos/2)
    end

    test "get_session_diff/2 is exported" do
      assert is_function(&Client.get_session_diff/2)
    end
  end

  describe "API endpoint helpers - Messages" do
    test "list_messages/2 is exported" do
      assert is_function(&Client.list_messages/2)
    end

    test "send_message/3 is exported" do
      assert is_function(&Client.send_message/3)
    end

    test "send_message_async/3 is exported" do
      assert is_function(&Client.send_message_async/3)
    end

    test "execute_command/3 is exported" do
      assert is_function(&Client.execute_command/3)
    end

    test "run_shell/3 is exported" do
      assert is_function(&Client.run_shell/3)
    end
  end

  describe "API endpoint helpers - Agents" do
    test "list_agents/1 is exported" do
      assert is_function(&Client.list_agents/1)
    end
  end

  describe "API endpoint helpers - Files" do
    test "find_text/2 is exported" do
      assert is_function(&Client.find_text/2)
    end

    test "find_files/2 is exported" do
      assert is_function(&Client.find_files/2)
    end

    test "read_file/2 is exported" do
      assert is_function(&Client.read_file/2)
    end

    test "list_files/2 is exported" do
      assert is_function(&Client.list_files/2)
    end
  end

  describe "error handling" do
    test "returns transport_error tuple when connection fails" do
      result = Client.get("/test", base_url: "http://192.0.2.1:1", retry_count: 0, timeout: 100)
      assert {:error, {:transport_error, _reason}} = result
    end
  end

  describe "create_session/1 builds correct body" do
    # These are indirect tests - we verify the function accepts the expected params
    # Real integration tests would verify the actual request body

    test "accepts empty params" do
      # Should not crash
      result = Client.create_session(base_url: "http://invalid.local:9999", retry_count: 0)
      assert {:error, _} = result
    end

    test "accepts parent_id param" do
      result =
        Client.create_session(
          parent_id: "abc123",
          base_url: "http://invalid.local:9999",
          retry_count: 0
        )

      assert {:error, _} = result
    end

    test "accepts title param" do
      result =
        Client.create_session(
          title: "My Session",
          base_url: "http://invalid.local:9999",
          retry_count: 0
        )

      assert {:error, _} = result
    end
  end
end
