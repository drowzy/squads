defmodule Squads.MCP do
  @moduledoc """
  The MCP context for handling Model Context Protocol logic.
  """

  import Ecto.Query, warn: false

  alias Squads.MCP.Catalog
  alias Squads.MCP.DockerCLI
  alias Squads.MCP.Server
  alias Squads.Mail
  alias Squads.Repo
  alias Squads.Sessions
  alias Squads.Tickets

  @doc """
  Lists MCP servers for a squad.
  """
  def list_servers(squad_id) do
    Server
    |> where(squad_id: ^squad_id)
    |> order_by([s], asc: s.name)
    |> Repo.all()
  end

  @doc """
  Gets an MCP server by id.
  """
  def get_server(id), do: Repo.get(Server, id)

  @doc """
  Gets an MCP server by name within a squad.
  """
  def get_server_by_name(squad_id, name) do
    Repo.get_by(Server, squad_id: squad_id, name: name)
  end

  @doc """
  Creates an MCP server.
  """
  def create_server(attrs) do
    %Server{}
    |> Server.changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Updates an MCP server.
  """
  def update_server(%Server{} = server, attrs) do
    server
    |> Server.changeset(attrs)
    |> Repo.update()
  end

  @doc """
  Deletes an MCP server.
  """
  def delete_server(%Server{} = server), do: Repo.delete(server)

  @doc """
  Returns an MCP server changeset.
  """
  def change_server(%Server{} = server, attrs \\ %{}) do
    Server.changeset(server, attrs)
  end

  @doc """
  Lists Docker MCP catalog entries with optional filters.
  """
  def list_catalog(opts \\ []) do
    catalog_adapter().list(opts)
  end

  @doc """
  Checks whether the Docker MCP CLI is available.
  """
  def cli_status do
    docker_cli().available?()
  end

  @doc """
  Enables an MCP server for a squad and calls Docker MCP CLI.
  """
  def enable_server(squad_id, name) do
    case get_server_by_name(squad_id, name) do
      nil ->
        {:error, :not_found}

      server ->
        case docker_cli().server_enable(name) do
          {:ok, _output} ->
            update_server(server, %{enabled: true, last_error: nil})

          {:error, reason} ->
            _ = update_server(server, %{last_error: format_error(reason)})
            {:error, reason}
        end
    end
  end

  @doc """
  Disables an MCP server for a squad and calls Docker MCP CLI.
  """
  def disable_server(squad_id, name) do
    case get_server_by_name(squad_id, name) do
      nil ->
        {:error, :not_found}

      server ->
        case docker_cli().server_disable(name) do
          {:ok, _output} ->
            update_server(server, %{enabled: false, last_error: nil})

          {:error, reason} ->
            _ = update_server(server, %{last_error: format_error(reason)})
            {:error, reason}
        end
    end
  end

  @doc """
  Syncs server status from Docker MCP CLI for a squad.
  """
  def sync_status(squad_id) do
    servers = list_servers(squad_id)

    case docker_cli().server_ls() do
      {:ok, output} ->
        statuses = parse_server_statuses(output)

        servers
        |> Enum.map(fn server ->
          status = Map.get(statuses, server.name, server.status || "unknown")
          update_server(server, %{status: status, last_error: nil})
        end)
        |> collect_results()

      {:error, reason} ->
        Enum.each(servers, fn server ->
          _ = update_server(server, %{status: "error", last_error: format_error(reason)})
        end)

        {:error, reason}
    end
  end

  @doc """
  Syncs tool metadata from Docker MCP CLI for a squad.
  """
  def sync_tools(squad_id) do
    servers = list_servers(squad_id)

    with {:ok, tools} <- docker_cli().tools_ls() do
      grouped = group_tools_by_server(tools)

      servers
      |> Enum.map(fn server ->
        tool_items = Map.get(grouped, server.name, [])
        update_server(server, %{tools: %{"items" => tool_items}})
      end)
      |> collect_results()
    end
  end

  @doc """
  Initiates OAuth authorization for a provider.
  """
  def oauth_authorize(provider) do
    docker_cli().oauth_authorize(provider)
  end

  @doc """
  Lists OAuth authorized providers.
  """
  def oauth_list do
    case docker_cli().oauth_ls() do
      {:ok, output} ->
        # The output from `docker mcp oauth ls` is usually a table or JSON.
        # DockerCLI.oauth_ls uses run_cmd which returns {:ok, trimmed_output}.
        # For now, let's just return the output. If it's JSON, we might want to decode it.
        # DockerCLI doesn't have a run_json_cmd for oauth_ls yet.
        {:ok, output}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Revokes OAuth authorization for a provider.
  """
  def oauth_revoke(provider) do
    docker_cli().oauth_revoke(provider)
  end

  @doc """
  Lists MCP secrets.
  """
  def secret_list do
    case docker_cli().secret_list() do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, reason}
    end
  end

  @doc """
  Sets an MCP secret.
  """
  def secret_set(key, value) do
    docker_cli().secret_set(key, value)
  end

  @doc """
  Removes an MCP secret.
  """
  def secret_remove(key) do
    docker_cli().secret_remove(key)
  end

  @doc """
  Handles an MCP request.
  """
  def handle_request("agent_mail", %{"method" => "list_tools"}) do
    tools = [
      %{
        name: "send_message",
        description: "Sends a new message to one or more agents.",
        inputSchema: %{
          type: "object",
          properties: %{
            project_id: %{type: "string", description: "The project ID."},
            subject: %{type: "string", description: "The message subject."},
            body_md: %{type: "string", description: "The message body in Markdown."},
            to: %{
              type: "array",
              items: %{type: "string"},
              description: "List of recipient agent IDs."
            },
            cc: %{
              type: "array",
              items: %{type: "string"},
              description: "List of CC recipient agent IDs."
            },
            importance: %{type: "string", enum: ["low", "normal", "high", "urgent"]},
            ack_required: %{type: "boolean"}
          },
          required: ["project_id", "subject", "body_md", "to"]
        }
      },
      %{
        name: "list_inbox",
        description: "Lists messages in an agent's inbox.",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string", description: "The agent ID."},
            limit: %{type: "integer", default: 20},
            since_ts: %{type: "string", format: "date-time"},
            urgent_only: %{type: "boolean"}
          },
          required: ["agent_id"]
        }
      },
      %{
        name: "search_messages",
        description: "Searches messages by subject or body.",
        inputSchema: %{
          type: "object",
          properties: %{
            project_id: %{type: "string", description: "The project ID."},
            query: %{type: "string", description: "The search query."},
            limit: %{type: "integer", default: 20}
          },
          required: ["project_id", "query"]
        }
      },
      %{
        name: "escalate",
        description: "Escalates a message to the agent's mentor or a specific senior.",
        inputSchema: %{
          type: "object",
          properties: %{
            agent_id: %{type: "string", description: "The agent ID."},
            project_id: %{type: "string", description: "The project ID."},
            body_md: %{type: "string", description: "The reason for escalation."},
            to_agent_id: %{
              type: "string",
              description: "Optional specific agent ID to escalate to."
            }
          },
          required: ["agent_id", "project_id", "body_md"]
        }
      },
      %{
        name: "squads_status",
        description: "Gets a summary of the squad status.",
        inputSchema: %{
          type: "object",
          properties: %{
            squad_id: %{type: "string", description: "The squad ID."}
          },
          required: ["squad_id"]
        }
      },
      %{
        name: "squads_tickets",
        description: "Gets a summary of the ticket board status.",
        inputSchema: %{
          type: "object",
          properties: %{
            project_id: %{type: "string", description: "The project ID."}
          },
          required: ["project_id"]
        }
      }
    ]

    {:ok, %{tools: tools}}
  end

  def handle_request("agent_mail", %{
        "method" => "call_tool",
        "params" => %{"name" => "send_message", "arguments" => args}
      }) do
    case Mail.send_message(args) do
      {:ok, message} ->
        {:ok, %{content: [%{type: "text", text: "Message sent with ID: #{message.id}"}]}}

      {:error, reason} ->
        {:error, %{code: -32000, message: "Failed to send message: #{inspect(reason)}"}}
    end
  end

  def handle_request("agent_mail", %{
        "method" => "call_tool",
        "params" => %{"name" => "list_inbox", "arguments" => args}
      }) do
    agent_id = args["agent_id"]

    opts = [
      limit: args["limit"],
      since_ts: args["since_ts"],
      urgent_only: args["urgent_only"]
    ]

    messages = Mail.list_inbox(agent_id, opts)

    text =
      messages
      |> Enum.map(fn m -> "[#{m.id}] #{m.sender.name}: #{m.subject}" end)
      |> Enum.join("\n")

    {:ok, %{content: [%{type: "text", text: text}]}}
  end

  def handle_request("agent_mail", %{
        "method" => "call_tool",
        "params" => %{"name" => "search_messages", "arguments" => args}
      }) do
    project_id = args["project_id"]
    query = args["query"]
    limit = args["limit"] || 20

    messages = Mail.search_messages(project_id, query, limit)

    text =
      messages
      |> Enum.map(fn m -> "[#{m.id}] #{m.sender.name}: #{m.subject}" end)
      |> Enum.join("\n")

    {:ok, %{content: [%{type: "text", text: text}]}}
  end

  def handle_request("agent_mail", %{
        "method" => "call_tool",
        "params" => %{"name" => "escalate", "arguments" => args}
      }) do
    agent_id = args["agent_id"]
    body_md = args["body_md"]
    project_id = args["project_id"]
    to_agent_id = args["to_agent_id"]

    with {:ok, agent} <- Squads.Agents.fetch_agent(agent_id),
         target_id <- to_agent_id || agent.mentor_id,
         true <- not is_nil(target_id) do
      Mail.send_message(%{
        project_id: project_id,
        sender_id: agent_id,
        subject: "ESCALATION: Assistance Required",
        body_md: body_md,
        importance: "high",
        ack_required: true,
        to: [target_id]
      })
      |> case do
        {:ok, _message} ->
          {:ok, %{content: [%{type: "text", text: "Escalated to mentor."}]}}

        {:error, reason} ->
          {:error, %{code: -32000, message: "Failed to escalate: #{inspect(reason)}"}}
      end
    else
      false -> {:error, %{code: -32001, message: "No mentor assigned"}}
      {:error, :not_found} -> {:error, %{code: -32002, message: "Agent not found"}}
    end
  end

  def handle_request("agent_mail", %{
        "method" => "call_tool",
        "params" => %{"name" => "squads_status", "arguments" => args}
      }) do
    squad_id = args["squad_id"]
    status = Sessions.get_squad_status(squad_id)
    {:ok, %{content: [%{type: "text", text: Jason.encode!(status, pretty: true)}]}}
  end

  def handle_request("agent_mail", %{
        "method" => "call_tool",
        "params" => %{"name" => "squads_tickets", "arguments" => args}
      }) do
    project_id = args["project_id"]
    summary = Tickets.get_tickets_summary(project_id)
    {:ok, %{content: [%{type: "text", text: Jason.encode!(summary, pretty: true)}]}}
  end

  def handle_request(_name, _params) do
    {:error, %{code: -32601, message: "Method not found"}}
  end

  defp docker_cli do
    Application.get_env(:squads, __MODULE__, [])[:docker_cli] || DockerCLI
  end

  defp catalog_adapter do
    Application.get_env(:squads, __MODULE__, [])[:catalog] || Catalog
  end

  defp collect_results(results) do
    results
    |> Enum.reduce_while({:ok, []}, fn
      {:ok, server}, {:ok, acc} -> {:cont, {:ok, [server | acc]}}
      {:error, reason}, _acc -> {:halt, {:error, reason}}
    end)
    |> case do
      {:ok, servers} -> {:ok, Enum.reverse(servers)}
      error -> error
    end
  end

  defp format_error(reason) when is_binary(reason), do: reason
  defp format_error(reason), do: inspect(reason)

  defp parse_server_statuses(output) do
    trimmed = String.trim(output)

    case Jason.decode(trimmed) do
      {:ok, decoded} -> parse_server_statuses_json(decoded)
      _ -> parse_server_statuses_table(trimmed)
    end
  end

  defp parse_server_statuses_json(%{"servers" => servers}) when is_list(servers) do
    parse_server_statuses_json(servers)
  end

  defp parse_server_statuses_json(servers) when is_list(servers) do
    Enum.reduce(servers, %{}, fn entry, acc ->
      name = entry["name"] || entry["server"]
      status = entry["status"] || entry["state"]

      if is_binary(name) and is_binary(status) do
        Map.put(acc, name, status)
      else
        acc
      end
    end)
  end

  defp parse_server_statuses_json(_), do: %{}

  defp parse_server_statuses_table(""), do: %{}

  defp parse_server_statuses_table(output) do
    case String.split(output, "\n", trim: true) do
      [] ->
        %{}

      [header | rows] ->
        columns =
          header
          |> String.split(~r/\s+/, trim: true)
          |> Enum.map(&String.downcase/1)

        name_index = Enum.find_index(columns, &(&1 in ["name", "server"]))
        status_index = Enum.find_index(columns, &(&1 in ["status", "state"]))

        if is_integer(name_index) and is_integer(status_index) do
          Enum.reduce(rows, %{}, fn row, acc ->
            values = String.split(row, ~r/\s+/, trim: true)
            name = Enum.at(values, name_index)
            status = Enum.at(values, status_index)

            if is_binary(name) and is_binary(status) do
              Map.put(acc, name, status)
            else
              acc
            end
          end)
        else
          %{}
        end
    end
  end

  defp group_tools_by_server(%{"tools" => tools}) when is_list(tools),
    do: group_tools_by_server(tools)

  defp group_tools_by_server(tools) when is_list(tools) do
    tools
    |> Enum.reduce(%{}, fn tool, acc ->
      case tool_server_name(tool) do
        nil -> acc
        server -> Map.update(acc, server, [tool], &[tool | &1])
      end
    end)
    |> Map.new(fn {server, tool_list} -> {server, Enum.reverse(tool_list)} end)
  end

  defp group_tools_by_server(_), do: %{}

  defp tool_server_name(tool) when is_map(tool) do
    tool["server"] || tool["server_name"] || tool["serverName"] ||
      server_from_tool_name(tool["name"])
  end

  defp tool_server_name(_), do: nil

  defp server_from_tool_name(name) when is_binary(name) do
    case String.split(name, ".", parts: 2) do
      [server, _] -> server
      _ -> nil
    end
  end

  defp server_from_tool_name(_), do: nil
end
