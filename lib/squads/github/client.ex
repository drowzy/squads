defmodule Squads.GitHub.Client do
  @moduledoc """
  Minimal GitHub REST API client.

  This is used for GitHub Issues integration (syncing tickets, updating labels,
  and assigning issues).

  The configured implementation can be swapped in tests via:

      config :squads, :github_client, Squads.GitHub.ClientMock

  """

  @type response :: {:ok, map() | list()} | {:error, term()}

  @callback get_authenticated_user(keyword()) :: response()
  @callback list_issues(String.t(), keyword()) :: response()
  @callback get_issue(String.t(), pos_integer(), keyword()) :: response()
  @callback create_issue(String.t(), map(), keyword()) :: response()
  @callback update_issue(String.t(), pos_integer(), map(), keyword()) :: response()
  @callback get_label(String.t(), String.t(), keyword()) :: response()
  @callback create_label(String.t(), map(), keyword()) :: response()

  @api_base "https://api.github.com"

  def client do
    Application.get_env(:squads, :github_client, __MODULE__.HTTP)
  end

  defmodule HTTP do
    @moduledoc false
    @behaviour Squads.GitHub.Client

    alias Squads.GitHub.Client

    @impl true
    defdelegate get_authenticated_user(opts), to: Client

    @impl true
    defdelegate list_issues(repo, opts), to: Client

    @impl true
    defdelegate get_issue(repo, issue_number, opts), to: Client

    @impl true
    defdelegate create_issue(repo, attrs, opts), to: Client

    @impl true
    defdelegate update_issue(repo, issue_number, attrs, opts), to: Client

    @impl true
    defdelegate get_label(repo, name, opts), to: Client

    @impl true
    defdelegate create_label(repo, attrs, opts), to: Client
  end

  @doc "Returns the authenticated GitHub user."
  @spec get_authenticated_user(keyword()) :: response()
  def get_authenticated_user(opts \\ []) do
    request(:get, "/user", nil, opts)
  end

  @doc """
  Lists issues for a repository.

  Options:
  - `:labels` (comma-separated string)
  - `:state` ("open" | "closed" | "all"), default "all"

  This handles pagination and filters out pull requests.
  """
  @spec list_issues(String.t(), keyword()) :: response()
  def list_issues(repo, opts \\ []) do
    labels = Keyword.get(opts, :labels)
    state = Keyword.get(opts, :state, "all")

    params =
      %{"state" => state, "per_page" => 100}
      |> maybe_put("labels", labels)

    do_list_issues(repo, 1, params, [], opts)
  end

  defp do_list_issues(repo, page, params, acc, opts) do
    params = Map.put(params, "page", page)

    case request(:get, repo_path(repo, "/issues"), nil, Keyword.put(opts, :params, params)) do
      {:ok, issues} when is_list(issues) ->
        issues = Enum.reject(issues, &Map.has_key?(&1, "pull_request"))
        acc = acc ++ issues

        if length(issues) == params["per_page"] do
          do_list_issues(repo, page + 1, params, acc, opts)
        else
          {:ok, acc}
        end

      {:ok, other} ->
        {:error, {:unexpected_response, other}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc "Fetches a single issue."
  @spec get_issue(String.t(), pos_integer(), keyword()) :: response()
  def get_issue(repo, issue_number, opts \\ []) do
    request(:get, repo_path(repo, "/issues/#{issue_number}"), nil, opts)
  end

  @doc "Creates a new issue."
  @spec create_issue(String.t(), map(), keyword()) :: response()
  def create_issue(repo, attrs, opts \\ []) when is_map(attrs) do
    request(:post, repo_path(repo, "/issues"), attrs, opts)
  end

  @doc "Updates an issue."
  @spec update_issue(String.t(), pos_integer(), map(), keyword()) :: response()
  def update_issue(repo, issue_number, attrs, opts \\ []) when is_map(attrs) do
    request(:patch, repo_path(repo, "/issues/#{issue_number}"), attrs, opts)
  end

  @doc "Fetches a label by name."
  @spec get_label(String.t(), String.t(), keyword()) :: response()
  def get_label(repo, name, opts \\ []) when is_binary(name) do
    request(:get, repo_path(repo, "/labels/#{URI.encode(name)}"), nil, opts)
  end

  @doc "Creates a label."
  @spec create_label(String.t(), map(), keyword()) :: response()
  def create_label(repo, attrs, opts \\ []) when is_map(attrs) do
    request(:post, repo_path(repo, "/labels"), attrs, opts)
  end

  defp repo_path(repo, suffix) do
    {owner, name} = parse_repo!(repo)
    "/repos/#{owner}/#{name}#{suffix}"
  end

  defp parse_repo!(repo) when is_binary(repo) do
    case String.split(repo, "/", parts: 2) do
      [owner, name] when owner != "" and name != "" -> {owner, name}
      _ -> raise ArgumentError, "invalid repo, expected owner/repo: #{inspect(repo)}"
    end
  end

  defp request(method, path, body, opts) do
    token = github_token(opts)

    headers =
      [
        {"accept", "application/vnd.github+json"},
        {"user-agent", "squads"}
      ]
      |> maybe_add_auth(token)

    req_opts =
      [
        base_url: @api_base,
        headers: headers,
        receive_timeout: 30_000
      ]
      |> maybe_put_req(:params, Keyword.get(opts, :params))
      |> maybe_put_req(:json, body)

    case Req.request([method: method, url: path] ++ req_opts) do
      {:ok, %Req.Response{status: status, body: resp_body}} when status in 200..299 ->
        {:ok, resp_body}

      {:ok, %Req.Response{status: status, body: resp_body}} ->
        {:error, {:http_error, status, resp_body}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp github_token(opts) do
    Keyword.get(opts, :token) ||
      System.get_env("GITHUB_TOKEN") ||
      System.get_env("GH_TOKEN") ||
      System.get_env("GITHUB_PAT")
  end

  defp maybe_add_auth(headers, nil), do: headers
  defp maybe_add_auth(headers, token), do: [{"authorization", "Bearer #{token}"} | headers]

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_put_req(opts, _key, nil), do: opts
  defp maybe_put_req(opts, key, value), do: Keyword.put(opts, key, value)
end
