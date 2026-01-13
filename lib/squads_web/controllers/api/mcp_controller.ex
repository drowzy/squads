defmodule SquadsWeb.API.MCPController do
  use SquadsWeb, :controller

  require Logger

  alias Squads.MCP
  alias Squads.Squads, as: SquadsContext

  action_fallback SquadsWeb.FallbackController

  plug :force_identity_encoding

  @server_fields ~w(name source type image url command args headers enabled status last_error catalog_meta tools)

  def index(conn, %{"squad_id" => squad_id}) do
    with_squad(squad_id, fn squad ->
      servers = MCP.list_servers(squad.id)
      json(conn, %{data: Enum.map(servers, &serialize_server/1)})
    end)
  end

  def index(conn, _params), do: missing_squad_id(conn)

  def create(conn, %{"squad_id" => squad_id} = params) do
    with_squad(squad_id, fn squad ->
      attrs =
        params
        |> Map.take(@server_fields)
        |> Map.put("squad_id", squad.id)

      case MCP.create_server(attrs) do
        {:ok, server} ->
          conn
          |> put_status(:created)
          |> json(%{data: serialize_server(server)})

        {:error, changeset} ->
          {:error, changeset}
      end
    end)
  end

  def create(conn, _params), do: missing_squad_id(conn)

  def update(conn, %{"name" => name, "squad_id" => squad_id} = params) do
    with_squad(squad_id, fn squad ->
      case MCP.get_server_by_name(squad.id, name) do
        nil ->
          {:error, :not_found}

        server ->
          attrs = Map.take(params, @server_fields)

          case MCP.update_server(server, attrs) do
            {:ok, updated} -> json(conn, %{data: serialize_server(updated)})
            {:error, changeset} -> {:error, changeset}
          end
      end
    end)
  end

  def update(conn, _params), do: missing_squad_id(conn)

  def connect(conn, %{"name" => name, "squad_id" => squad_id}) do
    with_squad(squad_id, fn squad ->
      case MCP.enable_server(squad.id, name) do
        {:ok, server} ->
          json(conn, %{data: serialize_server(server)})

        {:error, :not_found} ->
          {:error, :not_found}

        {:error, reason} ->
          cli_error(conn, reason)
      end
    end)
  end

  def connect(conn, %{"name" => name}) do
    Logger.debug("MCP connect request for #{name}, headers: #{inspect(conn.req_headers)}")
    handle_mcp_rpc(conn, name)
  end

  def connect(conn, _params), do: missing_squad_id(conn)

  def options_connect(conn, %{"name" => _name}) do
    conn
    |> put_resp_header("access-control-allow-origin", "*")
    |> put_resp_header("access-control-allow-methods", "GET,POST,OPTIONS")
    |> put_resp_header(
      "access-control-allow-headers",
      "content-type,authorization,mcp-protocol-version"
    )
    |> send_resp(:no_content, "")
  end

  def connect_stream(conn, %{"name" => name}) do
    conn =
      conn
      |> put_resp_header("content-type", "text/event-stream")
      |> put_resp_header("cache-control", "no-cache")
      |> put_resp_header("connection", "keep-alive")
      |> put_resp_header("content-encoding", "identity")
      |> send_chunked(200)

    {:ok, conn} =
      chunk(conn, "event: ping\ndata: {\"status\":\"connected\",\"name\":\"#{name}\"}\n\n")

    loop_mcp_stream(conn)
  end

  def disconnect(conn, %{"name" => name, "squad_id" => squad_id}) do
    with_squad(squad_id, fn squad ->
      case MCP.disable_server(squad.id, name) do
        {:ok, server} ->
          json(conn, %{data: serialize_server(server)})

        {:error, :not_found} ->
          {:error, :not_found}

        {:error, reason} ->
          cli_error(conn, reason)
      end
    end)
  end

  def disconnect(conn, _params), do: missing_squad_id(conn)

  def catalog(conn, params) do
    opts =
      []
      |> maybe_put(:query, params["query"])
      |> maybe_put(:category, params["category"])
      |> maybe_put(:tag, params["tag"])

    case MCP.list_catalog(opts) do
      {:ok, entries} ->
        json(conn, %{data: entries})

      {:error, reason} ->
        log_catalog_error(reason, params)

        conn
        |> put_status(:bad_gateway)
        |> json(%{error: "catalog_error", message: format_reason(reason)})
    end
  end

  def cli(conn, _params) do
    case MCP.cli_status() do
      {:ok, true} ->
        json(conn, %{available: true})

      {:ok, false, message} ->
        json(conn, %{available: false, message: message})

      {:error, reason} ->
        conn
        |> put_status(:bad_gateway)
        |> json(%{available: false, message: format_reason(reason)})
    end
  end

  def oauth_list(conn, _params) do
    case MCP.oauth_list() do
      {:ok, output} ->
        json(conn, %{data: output})

      {:error, reason} ->
        cli_error(conn, reason)
    end
  end

  def oauth_authorize(conn, %{"provider" => provider}) do
    case MCP.oauth_authorize(provider) do
      {:ok, output} ->
        json(conn, %{data: output})

      {:error, reason} ->
        cli_error(conn, reason)
    end
  end

  def oauth_revoke(conn, %{"provider" => provider}) do
    case MCP.oauth_revoke(provider) do
      {:ok, output} ->
        json(conn, %{data: output})

      {:error, reason} ->
        cli_error(conn, reason)
    end
  end

  def secret_list(conn, _params) do
    case MCP.secret_list() do
      {:ok, output} ->
        json(conn, %{data: output})

      {:error, reason} ->
        cli_error(conn, reason)
    end
  end

  def secret_set(conn, %{"key" => key, "value" => value}) do
    case MCP.secret_set(key, value) do
      {:ok, output} ->
        json(conn, %{data: output})

      {:error, reason} ->
        cli_error(conn, reason)
    end
  end

  def secret_remove(conn, %{"key" => key}) do
    case MCP.secret_remove(key) do
      {:ok, output} ->
        json(conn, %{data: output})

      {:error, reason} ->
        cli_error(conn, reason)
    end
  end

  def auth(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def auth_callback(conn, _params) do
    json(conn, %{status: "ok"})
  end

  defp force_identity_encoding(conn, _opts) do
    put_resp_header(conn, "content-encoding", "identity")
  end

  defp with_squad(squad_id, fun) do
    case Ecto.UUID.cast(squad_id) do
      {:ok, uuid} ->
        case SquadsContext.get_squad(uuid) do
          nil -> {:error, :not_found}
          squad -> fun.(squad)
        end

      :error ->
        {:error, :not_found}
    end
  end

  defp handle_mcp_rpc(conn, name) do
    payload =
      case conn.body_params do
        %{} = params -> params
        _ -> %{}
      end

    method = payload["method"] || payload[:method]
    id = payload["id"] || payload[:id]

    cond do
      is_nil(method) ->
        rpc_error(conn, id, -32600, "Invalid Request")

      is_nil(id) ->
        handle_mcp_notification(conn, name, payload)

      true ->
        handle_mcp_request(conn, name, payload)
    end
  end

  defp handle_mcp_notification(conn, name, payload) do
    method = payload["method"] || payload[:method]

    case method do
      "tools/call" ->
        _ = handle_tool_call(name, payload)
        send_resp(conn, :accepted, "")

      "call_tool" ->
        _ = handle_tool_call(name, payload)
        send_resp(conn, :accepted, "")

      "initialized" ->
        send_resp(conn, :accepted, "")

      _ ->
        send_resp(conn, :accepted, "")
    end
  end

  defp handle_mcp_request(conn, name, payload) do
    method = payload["method"] || payload[:method]
    id = payload["id"] || payload[:id]

    case method do
      "initialize" ->
        result = %{
          protocolVersion: "2025-06-18",
          serverInfo: %{
            name: "squads-#{name}",
            version: to_string(Application.spec(:squads, :vsn))
          },
          capabilities: %{tools: %{listChanged: false}}
        }

        rpc_result(conn, id, result)

      "tools/list" ->
        case MCP.handle_request(name, %{"method" => "list_tools"}) do
          {:ok, result} -> rpc_result(conn, id, result)
          {:error, reason} -> rpc_error_from_reason(conn, id, reason)
        end

      "list_tools" ->
        case MCP.handle_request(name, %{"method" => "list_tools"}) do
          {:ok, result} -> rpc_result(conn, id, result)
          {:error, reason} -> rpc_error_from_reason(conn, id, reason)
        end

      "tools/call" ->
        case handle_tool_call(name, payload) do
          {:ok, result} -> rpc_result(conn, id, result)
          {:error, reason} -> rpc_error_from_reason(conn, id, reason)
        end

      "call_tool" ->
        case handle_tool_call(name, payload) do
          {:ok, result} -> rpc_result(conn, id, result)
          {:error, reason} -> rpc_error_from_reason(conn, id, reason)
        end

      "ping" ->
        rpc_result(conn, id, %{})

      _ ->
        rpc_error(conn, id, -32601, "Method not found")
    end
  end

  defp handle_tool_call(name, payload) do
    params = payload["params"] || payload[:params] || %{}
    tool_name = params["name"] || params[:name]
    arguments = params["arguments"] || params[:arguments] || %{}

    MCP.handle_request(name, %{
      "method" => "call_tool",
      "params" => %{"name" => tool_name, "arguments" => arguments}
    })
  end

  defp rpc_result(conn, id, result) do
    conn
    |> put_resp_header("content-encoding", "identity")
    |> json(%{jsonrpc: "2.0", id: id, result: result})
  end

  defp rpc_error_from_reason(conn, id, %{code: code, message: message}) do
    rpc_error(conn, id, code, message)
  end

  defp rpc_error_from_reason(conn, id, reason) do
    rpc_error(conn, id, -32000, inspect(reason))
  end

  defp rpc_error(conn, id, code, message) do
    json(conn, %{jsonrpc: "2.0", id: id, error: %{code: code, message: message}})
  end

  defp loop_mcp_stream(conn) do
    receive do
      _ ->
        loop_mcp_stream(conn)
    after
      30_000 ->
        case chunk(conn, "event: ping\ndata: {\"status\":\"keep-alive\"}\n\n") do
          {:ok, conn} -> loop_mcp_stream(conn)
          {:error, _reason} -> conn
        end
    end
  end

  defp missing_squad_id(conn) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "missing_squad_id", message: "squad_id is required"})
  end

  defp cli_error(conn, reason) do
    conn
    |> put_status(:bad_request)
    |> json(%{error: "docker_mcp_error", message: format_reason(reason)})
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason), do: inspect(reason)

  defp log_catalog_error(reason, params) do
    Logger.error("MCP catalog error",
      reason: inspect(reason),
      query: params["query"],
      category: params["category"],
      tag: params["tag"]
    )
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: [{key, value} | opts]

  defp serialize_server(server) do
    %{
      id: server.id,
      squad_id: server.squad_id,
      name: server.name,
      source: server.source,
      type: server.type,
      image: server.image,
      url: server.url,
      command: server.command,
      args: server.args,
      headers: server.headers,
      enabled: server.enabled,
      status: server.status,
      last_error: server.last_error,
      catalog_meta: server.catalog_meta,
      tools: server.tools,
      inserted_at: server.inserted_at,
      updated_at: server.updated_at
    }
  end
end
