defmodule SquadsWeb.API.MCPController do
  use SquadsWeb, :controller

  alias Squads.MCP
  alias Squads.Squads, as: SquadsContext

  action_fallback SquadsWeb.FallbackController

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

  def connect(conn, _params), do: missing_squad_id(conn)

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

  def auth(conn, _params) do
    json(conn, %{status: "ok"})
  end

  def auth_callback(conn, _params) do
    json(conn, %{status: "ok"})
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
