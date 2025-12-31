defmodule SquadsWeb.PageController do
  use SquadsWeb, :controller

  def home(conn, _params) do
    render(conn, :home)
  end
end
