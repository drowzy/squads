defmodule SquadsWeb.API.MailController do
  use SquadsWeb, :controller

  alias Squads.Mail

  action_fallback SquadsWeb.FallbackController

  def index(conn, %{"agent_id" => agent_id} = params) do
    limit = if params["limit"], do: String.to_integer(params["limit"]), else: 20

    opts = %{
      limit: limit,
      since_ts: params["since_ts"],
      urgent_only: params["urgent_only"] == "true"
    }

    messages = Mail.list_inbox(agent_id, opts)
    render(conn, :index, messages: messages)
  end

  def show(conn, %{"id" => id}) do
    message = Mail.get_message!(id)
    render(conn, :show, message: message)
  end

  def thread(conn, %{"thread_id" => thread_id}) do
    messages = Mail.list_thread_messages(thread_id)
    render(conn, :index, messages: messages)
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
end
