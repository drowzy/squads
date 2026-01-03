defmodule SquadsWeb.Vite do
  use Phoenix.Component

  def vite_assets(assigns \\ %{}) do
    if Mix.env() == :dev && System.get_env("VITE_DEV") == "true" do
      ~H"""
      <script type="module" src={"http://#{get_vite_host()}:5173/assets/@vite/client"}>
      </script>
      <script type="module" src={"http://#{get_vite_host()}:5173/assets/src/main.tsx"}>
      </script>
      """
    else
      ~H"""
      <link rel="stylesheet" href="/assets/main.css" />
      <script type="module" src="/assets/vendor.js">
      </script>
      <script type="module" src="/assets/syntax-highlighter.js">
      </script>
      <script type="module" src="/assets/main.js">
      </script>
      """
    end
  end

  defp get_vite_host do
    System.get_env("VITE_HOST") || "simons-macbook-pro.tailf7556c.ts.net"
  end
end
