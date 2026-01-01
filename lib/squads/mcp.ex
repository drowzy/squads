defmodule Squads.MCP do
  @moduledoc """
  The MCP context for handling Model Context Protocol logic.
  """

  alias Squads.Mail
  alias Squads.Sessions
  alias Squads.Tickets

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

    with {:ok, agent} <- Squads.Agents.get_agent(agent_id),
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
      nil -> {:error, %{code: -32001, message: "No mentor assigned to agent."}}
      {:error, :not_found} -> {:error, %{code: -32002, message: "Agent not found."}}
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
end
