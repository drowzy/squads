defmodule SquadsWeb.PageControllerTest do
  use SquadsWeb.ConnCase

  test "GET / returns SPA shell", %{conn: conn} do
    conn = get(conn, ~p"/")
    # SPA shell contains the root div and assets
    assert html_response(conn, 200) =~ ~s(<div id="root"></div>)
    assert html_response(conn, 200) =~ "/assets/main.js"
  end

  test "GET /board returns SPA shell (client-side routing)", %{conn: conn} do
    conn = get(conn, ~p"/board")
    # All client routes return the same SPA shell
    assert html_response(conn, 200) =~ ~s(<div id="root"></div>)
  end

  test "GET /mail returns SPA shell (client-side routing)", %{conn: conn} do
    conn = get(conn, ~p"/mail")
    assert html_response(conn, 200) =~ ~s(<div id="root"></div>)
  end

  test "GET /nonexistent returns SPA shell (catch-all)", %{conn: conn} do
    conn = get(conn, ~p"/some/nonexistent/path")
    # Even unknown paths return the SPA shell; React Router handles 404
    assert html_response(conn, 200) =~ ~s(<div id="root"></div>)
  end
end
