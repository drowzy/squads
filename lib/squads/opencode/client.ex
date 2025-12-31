defmodule Squads.OpenCode.Client do
  @moduledoc """
  HTTP client wrapper for OpenCode server communication.

  Provides a configurable HTTP client with retry logic, error handling,
  and typed helpers for common OpenCode API endpoints.

  ## Configuration

  Configure via application env:

      config :squads, Squads.OpenCode.Client,
        base_url: "http://127.0.0.1:4096",
        timeout: 30_000,
        retry_count: 3,
        retry_delay: 1000

  Or pass options at runtime to individual calls.
  """

  require Logger

  @default_base_url "http://127.0.0.1:4096"
  @default_timeout 30_000
  @default_retry_count 3
  @default_retry_delay 1_000

  @type client_opts :: [
          base_url: String.t(),
          timeout: pos_integer(),
          retry_count: non_neg_integer(),
          retry_delay: pos_integer()
        ]

  @type response :: {:ok, map() | list() | boolean() | String.t()} | {:error, term()}

  # ============================================================================
  # Core HTTP Methods
  # ============================================================================

  @doc """
  Perform a GET request to the OpenCode server.

  ## Examples

      iex> Squads.OpenCode.Client.get("/global/health")
      {:ok, %{"healthy" => true, "version" => "1.0.0"}}

      iex> Squads.OpenCode.Client.get("/session", query: [limit: 10])
      {:ok, [%{"id" => "abc123", ...}]}
  """
  @spec get(String.t(), keyword()) :: response()
  def get(path, opts \\ []) do
    request(:get, path, nil, opts)
  end

  @doc """
  Perform a POST request to the OpenCode server.

  ## Examples

      iex> Squads.OpenCode.Client.post("/session", %{title: "My Session"})
      {:ok, %{"id" => "abc123", "title" => "My Session", ...}}

      iex> Squads.OpenCode.Client.post("/session/abc123/abort", %{})
      {:ok, true}
  """
  @spec post(String.t(), map() | nil, keyword()) :: response()
  def post(path, body \\ nil, opts \\ []) do
    request(:post, path, body, opts)
  end

  @doc """
  Perform a PATCH request to the OpenCode server.
  """
  @spec patch(String.t(), map() | nil, keyword()) :: response()
  def patch(path, body \\ nil, opts \\ []) do
    request(:patch, path, body, opts)
  end

  @doc """
  Perform a DELETE request to the OpenCode server.
  """
  @spec delete(String.t(), keyword()) :: response()
  def delete(path, opts \\ []) do
    request(:delete, path, nil, opts)
  end

  @doc """
  Perform a PUT request to the OpenCode server.
  """
  @spec put(String.t(), map() | nil, keyword()) :: response()
  def put(path, body \\ nil, opts \\ []) do
    request(:put, path, body, opts)
  end

  # ============================================================================
  # API Endpoint Helpers - Global
  # ============================================================================

  @doc """
  Check server health and get version info.

  Returns `{:ok, %{"healthy" => true, "version" => "x.x.x"}}` on success.
  """
  @spec health(keyword()) :: response()
  def health(opts \\ []) do
    get("/global/health", opts)
  end

  @doc """
  Check if the OpenCode server is reachable and healthy.
  """
  @spec healthy?(keyword()) :: boolean()
  def healthy?(opts \\ []) do
    case health(Keyword.put(opts, :retry_count, 0)) do
      {:ok, %{"healthy" => true}} -> true
      _ -> false
    end
  end

  # ============================================================================
  # API Endpoint Helpers - Config & Provider
  # ============================================================================

  @doc """
  Get the server configuration.
  """
  @spec get_config(keyword()) :: response()
  def get_config(opts \\ []) do
    get("/config", opts)
  end

  @doc """
  Get providers and default models.
  """
  @spec get_config_providers(keyword()) :: response()
  def get_config_providers(opts \\ []) do
    get("/config/providers", opts)
  end

  @doc """
  List all providers with their connection status.
  """
  @spec list_providers(keyword()) :: response()
  def list_providers(opts \\ []) do
    get("/provider", opts)
  end

  # ============================================================================
  # API Endpoint Helpers - Project
  # ============================================================================

  @doc """
  List all projects.
  """
  @spec list_projects(keyword()) :: response()
  def list_projects(opts \\ []) do
    get("/project", opts)
  end

  @doc """
  Get the current project.
  """
  @spec get_current_project(keyword()) :: response()
  def get_current_project(opts \\ []) do
    get("/project/current", opts)
  end

  # ============================================================================
  # API Endpoint Helpers - Sessions
  # ============================================================================

  @doc """
  List all sessions.
  """
  @spec list_sessions(keyword()) :: response()
  def list_sessions(opts \\ []) do
    get("/session", opts)
  end

  @doc """
  Create a new session.

  ## Options

    * `:parent_id` - Parent session ID for forking
    * `:title` - Session title
  """
  @spec create_session(keyword()) :: response()
  def create_session(params \\ []) do
    body = %{}
    body = if params[:parent_id], do: Map.put(body, :parentID, params[:parent_id]), else: body
    body = if params[:title], do: Map.put(body, :title, params[:title]), else: body

    post("/session", body, Keyword.drop(params, [:parent_id, :title]))
  end

  @doc """
  Get session details by ID.
  """
  @spec get_session(String.t(), keyword()) :: response()
  def get_session(session_id, opts \\ []) do
    get("/session/#{session_id}", opts)
  end

  @doc """
  Get session status for all sessions.
  """
  @spec get_sessions_status(keyword()) :: response()
  def get_sessions_status(opts \\ []) do
    get("/session/status", opts)
  end

  @doc """
  Update a session's properties.
  """
  @spec update_session(String.t(), map(), keyword()) :: response()
  def update_session(session_id, params, opts \\ []) do
    patch("/session/#{session_id}", params, opts)
  end

  @doc """
  Delete a session and all its data.
  """
  @spec delete_session(String.t(), keyword()) :: response()
  def delete_session(session_id, opts \\ []) do
    delete("/session/#{session_id}", opts)
  end

  @doc """
  Abort a running session.
  """
  @spec abort_session(String.t(), keyword()) :: response()
  def abort_session(session_id, opts \\ []) do
    post("/session/#{session_id}/abort", %{}, opts)
  end

  @doc """
  Fork a session, optionally at a specific message.
  """
  @spec fork_session(String.t(), keyword()) :: response()
  def fork_session(session_id, params \\ []) do
    body = if params[:message_id], do: %{messageID: params[:message_id]}, else: %{}
    post("/session/#{session_id}/fork", body, Keyword.drop(params, [:message_id]))
  end

  @doc """
  Get the todo list for a session.
  """
  @spec get_session_todos(String.t(), keyword()) :: response()
  def get_session_todos(session_id, opts \\ []) do
    get("/session/#{session_id}/todo", opts)
  end

  @doc """
  Get diffs for a session.
  """
  @spec get_session_diff(String.t(), keyword()) :: response()
  def get_session_diff(session_id, opts \\ []) do
    get("/session/#{session_id}/diff", opts)
  end

  # ============================================================================
  # API Endpoint Helpers - Messages
  # ============================================================================

  @doc """
  List messages in a session.
  """
  @spec list_messages(String.t(), keyword()) :: response()
  def list_messages(session_id, opts \\ []) do
    {query_opts, req_opts} = Keyword.split(opts, [:limit])
    query = Enum.map(query_opts, fn {k, v} -> {k, v} end)
    get("/session/#{session_id}/message", Keyword.put(req_opts, :query, query))
  end

  @doc """
  Send a message to a session and wait for response.

  ## Required params

    * `:parts` - List of message parts (e.g., `[%{type: "text", text: "Hello"}]`)

  ## Optional params

    * `:model` - Override the model (e.g., `"anthropic/claude-sonnet-4-20250514"`)
    * `:agent` - Agent to use
    * `:no_reply` - If true, don't wait for AI response
    * `:system` - Custom system prompt
    * `:tools` - List of tool IDs to enable
  """
  @spec send_message(String.t(), map(), keyword()) :: response()
  def send_message(session_id, params, opts \\ []) do
    post("/session/#{session_id}/message", normalize_message_params(params), opts)
  end

  @doc """
  Send a message asynchronously (fire and forget).
  """
  @spec send_message_async(String.t(), map(), keyword()) :: response()
  def send_message_async(session_id, params, opts \\ []) do
    post("/session/#{session_id}/prompt_async", normalize_message_params(params), opts)
  end

  @doc """
  Execute a slash command in a session.
  """
  @spec execute_command(String.t(), String.t(), keyword()) :: response()
  def execute_command(session_id, command, params \\ []) do
    body = %{command: command}
    body = if params[:arguments], do: Map.put(body, :arguments, params[:arguments]), else: body
    body = if params[:agent], do: Map.put(body, :agent, params[:agent]), else: body
    body = if params[:model], do: Map.put(body, :model, params[:model]), else: body

    post(
      "/session/#{session_id}/command",
      body,
      Keyword.drop(params, [:arguments, :agent, :model])
    )
  end

  @doc """
  Run a shell command in a session.
  """
  @spec run_shell(String.t(), String.t(), keyword()) :: response()
  def run_shell(session_id, command, params \\ []) do
    body = %{command: command, agent: params[:agent] || "default"}
    body = if params[:model], do: Map.put(body, :model, params[:model]), else: body

    post("/session/#{session_id}/shell", body, Keyword.drop(params, [:agent, :model]))
  end

  # ============================================================================
  # API Endpoint Helpers - Agents
  # ============================================================================

  @doc """
  List all available agents.
  """
  @spec list_agents(keyword()) :: response()
  def list_agents(opts \\ []) do
    get("/agent", opts)
  end

  # ============================================================================
  # API Endpoint Helpers - Files
  # ============================================================================

  @doc """
  Search for text in files.
  """
  @spec find_text(String.t(), keyword()) :: response()
  def find_text(pattern, opts \\ []) do
    get("/find", Keyword.put(opts, :query, pattern: pattern))
  end

  @doc """
  Find files by name pattern.
  """
  @spec find_files(String.t(), keyword()) :: response()
  def find_files(query, opts \\ []) do
    {query_opts, req_opts} = Keyword.split(opts, [:type, :directory, :limit])
    query_params = [{:query, query} | Enum.map(query_opts, fn {k, v} -> {k, v} end)]
    get("/find/file", Keyword.put(req_opts, :query, query_params))
  end

  @doc """
  Read file contents.
  """
  @spec read_file(String.t(), keyword()) :: response()
  def read_file(path, opts \\ []) do
    get("/file/content", Keyword.put(opts, :query, path: path))
  end

  @doc """
  List files and directories.
  """
  @spec list_files(String.t(), keyword()) :: response()
  def list_files(path, opts \\ []) do
    get("/file", Keyword.put(opts, :query, path: path))
  end

  # ============================================================================
  # Private Implementation
  # ============================================================================

  defp normalize_message_params(params) when is_map(params) do
    params =
      case Map.get(params, :no_reply) || Map.get(params, "no_reply") do
        nil ->
          params

        no_reply ->
          params
          |> Map.delete(:no_reply)
          |> Map.delete("no_reply")
          |> Map.put(:noReply, no_reply)
      end

    case Map.get(params, :model) || Map.get(params, "model") do
      model when is_binary(model) ->
        case split_model_string(model) do
          {:ok, provider_id, model_id} ->
            Map.put(params, :model, %{"providerID" => provider_id, "modelID" => model_id})

          :error ->
            params
        end

      _ ->
        params
    end
  end

  defp normalize_message_params(params), do: params

  defp split_model_string(model) when is_binary(model) do
    case String.split(model, "/", parts: 2) do
      [provider_id, model_id] when provider_id != "" and model_id != "" ->
        {:ok, provider_id, model_id}

      _ ->
        :error
    end
  end

  defp split_model_string(_), do: :error

  defp request(method, path, body, opts) do
    config = get_config_opts()
    base_url = opts[:base_url] || config[:base_url] || @default_base_url
    timeout = opts[:timeout] || config[:timeout] || @default_timeout
    retry_count = opts[:retry_count] || config[:retry_count] || @default_retry_count
    retry_delay = opts[:retry_delay] || config[:retry_delay] || @default_retry_delay

    url = "#{base_url}#{path}"

    req_opts = [
      connect_options: [timeout: timeout],
      receive_timeout: timeout,
      retry: if(retry_count > 0, do: :transient, else: false),
      retry_delay: fn _ -> retry_delay end,
      max_retries: retry_count
    ]

    # Add query params if present
    req_opts =
      if opts[:query] do
        Keyword.put(req_opts, :params, opts[:query])
      else
        req_opts
      end

    # Add JSON body if present
    req_opts =
      if body do
        Keyword.put(req_opts, :json, body)
      else
        req_opts
      end

    Logger.debug("OpenCode HTTP #{method} #{url}", body: body)

    result =
      case method do
        :get -> Req.get(url, req_opts)
        :post -> Req.post(url, req_opts)
        :patch -> Req.patch(url, req_opts)
        :delete -> Req.delete(url, req_opts)
        :put -> Req.put(url, req_opts)
      end

    handle_response(result)
  end

  defp handle_response({:ok, %Req.Response{status: 204}}) do
    {:ok, true}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}})
       when status in 200..299 do
    {:ok, body}
  end

  defp handle_response({:ok, %Req.Response{status: 404, body: body}}) do
    {:error, {:not_found, body}}
  end

  defp handle_response({:ok, %Req.Response{status: 400, body: body}}) do
    {:error, {:bad_request, body}}
  end

  defp handle_response({:ok, %Req.Response{status: 401, body: body}}) do
    {:error, {:unauthorized, body}}
  end

  defp handle_response({:ok, %Req.Response{status: 403, body: body}}) do
    {:error, {:forbidden, body}}
  end

  defp handle_response({:ok, %Req.Response{status: 500, body: body}}) do
    {:error, {:server_error, body}}
  end

  defp handle_response({:ok, %Req.Response{status: status, body: body}}) do
    {:error, {:http_error, status, body}}
  end

  defp handle_response({:error, %Req.TransportError{reason: reason}}) do
    {:error, {:transport_error, reason}}
  end

  defp handle_response({:error, reason}) do
    {:error, {:request_error, reason}}
  end

  defp get_config_opts do
    Application.get_env(:squads, __MODULE__, [])
  end
end
