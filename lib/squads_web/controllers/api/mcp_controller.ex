defmodule SquadsWeb.API.MCPController do
  use SquadsWeb, :controller

  alias Squads.MCP

  action_fallback SquadsWeb.FallbackController

  def index(conn, _params) do
    # Returns an empty JSON object as the listing of MCP servers and their status
    # is not yet implemented. Future implementation will query the `mcp_servers` table.
    json(conn, %{})
  end

  def create(conn, %{"name" => _name, "config" => _config}) do
    # Returns an empty JSON object as adding an MCP server is not yet implemented.
    # Future implementation will insert a new record into the `mcp_servers` table.
    json(conn, %{})
  end

  def connect(conn, %{"name" => name} = params) do
    # OpenCode's connect might send a JSON-RPC request in the body or 
    # expect the server to initiate SSE. For agent_mail, we treat it as 
    # a standard JSON-RPC over HTTP endpoint.
    case MCP.handle_request(name, params) do
      {:ok, result} ->
        json(conn, %{jsonrpc: "2.0", id: params["id"], result: result})

      {:error, %{code: code, message: message}} ->
        conn
        |> put_status(:bad_request)
        |> json(%{jsonrpc: "2.0", id: params["id"], error: %{code: code, message: message}})
    end
  end

  def disconnect(conn, %{"name" => _name}) do
    json(conn, true)
  end

  def auth(conn, _params) do
    # Returns a success status as the MCP auth flow is not yet implemented.
    # Future implementation will handle the authentication handshake with the MCP server.
    json(conn, %{status: "ok"})
  end

  def auth_callback(conn, _params) do
    # Returns a success status as the MCP auth callback is not yet implemented.
    # Future implementation will process the callback from the MCP server authentication.
    json(conn, %{status: "ok"})
  end
end
