defmodule SquadsWeb.Router do
  use SquadsWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {SquadsWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json", "sse"]
  end

  scope "/", SquadsWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  # Other scopes may use custom stacks.
  scope "/api", SquadsWeb.API do
    pipe_through :api

    # Filesystem browser for project selection (must be before resources)
    get "/projects/browse", ProjectController, :browse

    resources "/projects", ProjectController, only: [:index, :show, :create, :delete] do
      # Squad endpoints nested under projects
      resources "/squads", SquadController, only: [:index, :create]
      get "/events/stream", EventController, :stream

      # Agent listing for a project (across all squads)
      get "/agents", AgentController, :index_by_project

      # Provider endpoints nested under projects
      get "/providers", ProviderController, :index
      post "/providers/sync", ProviderController, :sync
      get "/models", ProviderController, :models
      get "/models/default", ProviderController, :default_model

      # Board (cards grouped by squad)
      get "/board", BoardController, :show
      post "/board/cards", BoardController, :create_card
      put "/board/lanes/assign", BoardController, :assign_lane

      get "/mail/threads", MailController, :threads_index
      post "/mail/send", MailController, :create
      post "/mail/threads/:thread_id/reply", MailController, :reply

      # Worktree endpoints nested under projects
      resources "/worktrees", WorktreeController, only: [:index, :create, :delete]

      # Autocomplete endpoints
      get "/files", ProjectController, :files
    end

    # Standalone provider endpoint
    get "/providers/:id", ProviderController, :show

    # Board card actions
    patch "/board/cards/:id", BoardController, :update_card
    post "/board/cards/:id/actions/sync", BoardController, :sync_artifacts
    post "/board/cards/:id/actions/create_issues", BoardController, :create_issues
    post "/board/cards/:id/actions/create_pr", BoardController, :create_pr
    post "/board/cards/:id/human_review", BoardController, :submit_human_review

    # Standalone squad endpoints
    resources "/squads", SquadController, only: [:show, :update, :delete] do
      # Agent endpoints nested under squads
      resources "/agents", AgentController, only: [:index, :create]
      post "/message", SquadController, :message
    end

    # Standalone agent endpoints
    get "/agents/roles", AgentController, :roles

    resources "/agents", AgentController, only: [:show, :update, :delete] do
      patch "/status", AgentController, :update_status
      post "/sessions/new", SessionController, :new_session
    end

    post "/sessions/start", SessionController, :start

    resources "/sessions", SessionController, only: [:index, :show, :create] do
      post "/start", SessionController, :start_existing
      post "/stop", SessionController, :stop
      post "/abort", SessionController, :abort
      post "/archive", SessionController, :archive
      post "/cancel", SessionController, :cancel
      get "/messages", SessionController, :messages
      get "/transcript", SessionController, :transcript
      get "/diff", SessionController, :diff
      get "/todos", SessionController, :todos
      post "/prompt", SessionController, :prompt
      post "/prompt_async", SessionController, :prompt_async
      post "/prompt_stream", SessionController, :prompt_stream
      post "/command", SessionController, :command
      post "/shell", SessionController, :shell
    end

    get "/events", EventController, :index

    # Human review queue (board cards)
    get "/reviews", ReviewController, :index
    get "/reviews/:id", ReviewController, :show
    post "/reviews/:id/submit", ReviewController, :submit

    # External Node endpoints
    get "/external_nodes", ExternalNodeController, :index
    post "/external_nodes/probe", ExternalNodeController, :probe

    # Squad Connections
    get "/fleet/connections", SquadConnectionController, :index
    post "/fleet/connections", SquadConnectionController, :create
    delete "/fleet/connections/:id", SquadConnectionController, :delete

    # Mail endpoints
    get "/mail", MailController, :index
    get "/mail/search", MailController, :search
    get "/mail/threads", MailController, :threads_index
    get "/mail/:id", MailController, :show
    post "/mail", MailController, :create
    post "/mail/:id/reply", MailController, :reply
    post "/mail/:id/read", MailController, :read
    post "/mail/:id/acknowledge", MailController, :acknowledge
    get "/mail/threads/:thread_id", MailController, :thread

    # MCP endpoints
    get "/mcp", MCPController, :index
    get "/mcp/catalog", MCPController, :catalog
    get "/mcp/cli", MCPController, :cli
    get "/mcp/oauth", MCPController, :oauth_list
    post "/mcp/oauth/:provider/authorize", MCPController, :oauth_authorize
    post "/mcp/oauth/:provider/revoke", MCPController, :oauth_revoke
    get "/mcp/secrets", MCPController, :secret_list
    post "/mcp/secrets", MCPController, :secret_set
    delete "/mcp/secrets/:key", MCPController, :secret_remove
    post "/mcp", MCPController, :create
    patch "/mcp/:name", MCPController, :update
    get "/mcp/:name/connect", MCPController, :connect_stream
    post "/mcp/:name/connect", MCPController, :connect
    post "/mcp/:name/disconnect", MCPController, :disconnect
    get "/mcp/:name/auth", MCPController, :auth
    post "/mcp/:name/auth", MCPController, :auth
    post "/mcp/:name/auth/callback", MCPController, :auth_callback
  end

  # Enable LiveDashboard and Swoosh mailbox preview in development
  if Application.compile_env(:squads, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: SquadsWeb.Telemetry
      forward "/mailbox", Plug.Swoosh.MailboxPreview
    end
  end

  # SPA catch-all for client-side routing
  # MUST be defined last, after all API and dev routes
  scope "/", SquadsWeb do
    pipe_through :browser

    get "/*path", PageController, :home
  end
end
