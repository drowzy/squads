defmodule SquadsWeb.FallbackController do
  @moduledoc """
  Translates controller action results into valid `Plug.Conn` responses.
  """
  use SquadsWeb, :controller

  def call(conn, {:error, :not_found}) do
    conn
    |> put_status(:not_found)
    |> put_view(json: SquadsWeb.ErrorJSON)
    |> render(:"404")
  end

  def call(conn, {:error, :unprocessable_entity, message}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SquadsWeb.ErrorJSON)
    |> render(:error, message: message)
  end

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    conn
    |> put_status(:unprocessable_entity)
    |> put_view(json: SquadsWeb.ErrorJSON)
    |> render(:changeset_error, changeset: changeset)
  end

  def call(conn, {:error, {:opencode_error, reason}}) do
    conn
    |> put_status(:bad_gateway)
    |> put_view(json: SquadsWeb.ErrorJSON)
    |> render(:error, message: "OpenCode error: #{inspect(reason)}")
  end

  def call(conn, {:error, :session_not_active}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SquadsWeb.ErrorJSON)
    |> render(:error, message: "Session is not running")
  end

  def call(conn, {:error, :no_opencode_session}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SquadsWeb.ErrorJSON)
    |> render(:error, message: "Session has no OpenCode session")
  end

  def call(conn, {:error, :already_started}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SquadsWeb.ErrorJSON)
    |> render(:error, message: "Session has already been started")
  end

  def call(conn, {:error, :not_running}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SquadsWeb.ErrorJSON)
    |> render(:error, message: "Session is not running")
  end

  def call(conn, {:error, :not_paused}) do
    conn
    |> put_status(:conflict)
    |> put_view(json: SquadsWeb.ErrorJSON)
    |> render(:error, message: "Session is not paused")
  end

  def call(conn, {:error, reason}) when is_atom(reason) do
    conn
    |> put_status(:bad_request)
    |> put_view(json: SquadsWeb.ErrorJSON)
    |> render(:error, message: to_string(reason))
  end
end
