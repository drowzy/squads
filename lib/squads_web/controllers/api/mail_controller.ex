defmodule SquadsWeb.API.MailController do
  use SquadsWeb, :controller

  alias Squads.Mail
  alias Squads.Agents

  action_fallback SquadsWeb.FallbackController

  def index(conn, %{"agent_id" => agent_id} = params) do
    case Ecto.UUID.cast(agent_id) do
      {:ok, agent_uuid} ->
        limit = if params["limit"], do: String.to_integer(params["limit"]), else: 20

        opts = %{
          limit: limit,
          since_ts: params["since_ts"],
          urgent_only: params["urgent_only"] == "true"
        }

        messages = Mail.list_inbox(agent_uuid, opts)
        render(conn, :index, messages: messages)

      :error ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "not_found", message: "Invalid agent ID"})
    end
  end

  def show(conn, %{"id" => id}) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} ->
        message = Mail.get_message!(uuid)
        render(conn, :show, message: message)

      :error ->
        {:error, :not_found}
    end
  end

  def thread(conn, %{"thread_id" => thread_id}) do
    messages = Mail.list_thread_messages(thread_id)
    render(conn, :index, messages: messages)
  end

  def create(conn, %{"project_id" => project_id} = params) do
    # Validate project_id
    with {:ok, project_uuid} <- Ecto.UUID.cast(project_id),
         # Resolve recipient names to UUIDs
         {:ok, to_ids} <- resolve_recipients(project_uuid, params["to"] || []),
         # Resolve sender name to UUID (optional - use first recipient if not provided for now)
         # If not an agent, use author_name
         {:ok, sender_id, author_name} <- resolve_sender(project_uuid, params["sender_name"]) do
      mail_params = %{
        project_id: project_uuid,
        sender_id: sender_id,
        author_name: author_name,
        subject: params["subject"],
        body_md: params["body_md"],
        to: to_ids,
        importance: params["importance"] || "normal",
        ack_required: params["ack_required"] || false
      }

      case Mail.send_message(mail_params) do
        {:ok, message} ->
          conn
          |> put_status(:created)
          |> render(:show, message: message)

        {:error, reason} ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: "send_failed", message: inspect(reason)})
      end
    else
      :error ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "invalid_project_id", message: "Invalid project ID format"})

      {:error, :no_sender} ->
        conn
        |> put_status(:bad_request)
        |> json(%{error: "missing_sender", message: "sender_name is required"})

      {:error, missing_names} when is_list(missing_names) ->
        conn
        |> put_status(:bad_request)
        |> json(%{
          error: "unknown_recipients",
          message: "Unknown agent names: #{Enum.join(missing_names, ", ")}"
        })
    end
  end

  def create(conn, params) do
    with {:ok, message} <- Mail.send_message(params) do
      conn
      |> put_status(:created)
      |> render(:show, message: message)
    end
  end

  def reply(conn, %{"id" => id, "sender_id" => sender_id, "body_md" => body_md} = params) do
    opts = %{
      importance: params["importance"],
      ack_required: params["ack_required"] == "true"
    }

    with {:ok, message} <- Mail.reply_to_message(id, sender_id, body_md, opts) do
      conn
      |> put_status(:created)
      |> render(:show, message: message)
    end
  end

  def read(conn, %{"id" => id, "agent_id" => agent_id}) do
    with {:ok, _recipient} <- Mail.mark_as_read(id, agent_id) do
      send_resp(conn, :no_content, "")
    end
  end

  def acknowledge(conn, %{"id" => id, "agent_id" => agent_id}) do
    with {:ok, _recipient} <- Mail.acknowledge(id, agent_id) do
      send_resp(conn, :no_content, "")
    end
  end

  def search(conn, %{"project_id" => project_id, "q" => query} = params) do
    limit = String.to_integer(params["limit"] || "20")
    messages = Mail.search_messages(project_id, query, limit)
    render(conn, :index, messages: messages)
  end

  def threads_index(conn, params) do
    opts = if params["project_id"], do: [project_id: params["project_id"]], else: []
    threads = Mail.list_threads(opts)
    render(conn, :threads_index, threads: threads)
  end

  # ============================================================================
  # Private Helpers
  # ============================================================================

  defp resolve_recipients(_project_id, []), do: {:ok, []}

  defp resolve_recipients(project_id, names) when is_list(names) do
    Agents.resolve_agent_names(project_id, names)
  end

  defp resolve_sender(_project_id, nil), do: {:error, :no_sender}
  defp resolve_sender(_project_id, ""), do: {:error, :no_sender}

  defp resolve_sender(project_id, sender_name) do
    case Agents.get_agent_by_name(project_id, sender_name) do
      # Treat as human/external author
      nil -> {:ok, nil, sender_name}
      agent -> {:ok, agent.id, nil}
    end
  end
end
