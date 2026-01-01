defmodule SquadsWeb.API.MCPController do
  use SquadsWeb, :controller

  alias Squads.MCP

  action_fallback SquadsWeb.FallbackController

  def index(conn, _params) do
    # Placeholder for listing MCP servers and their status
    json(conn, %{})
  end

  def create(conn, %{"name" => _name, "config" => _config}) do
    # Placeholder for adding an MCP server
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
    # Placeholder for MCP auth flow
    json(conn, %{status: "ok"})
  end

  def auth_callback(conn, _params) do
    # Placeholder for MCP auth callback
    json(conn, %{status: "ok"})
  end
end
