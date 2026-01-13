defmodule Squads.Artifacts.Issue do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :id, :string
    field :status, :string, default: "open"
    field :priority, :integer, default: 2
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime
    field :labels, {:array, :string}, default: []
    field :assignee, :string
    field :references, :map, default: %{}
    field :body_md, :string, default: ""

    field :title, :string, virtual: true
    field :path, :string, virtual: true
  end

  @type t :: %__MODULE__{}

  @statuses ~w(open in_progress blocked done)

  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(content) when is_binary(content) do
    with {:ok, {frontmatter_yaml, body_md}} <- split_frontmatter(content),
         {:ok, frontmatter} <- parse_frontmatter(frontmatter_yaml),
         {:ok, issue} <- from_frontmatter_and_body(frontmatter, body_md) do
      {:ok, issue}
    end
  end

  @spec render(t()) :: String.t()
  def render(%__MODULE__{} = issue) do
    yaml = issue |> frontmatter_map() |> dump_yaml()
    body_md = String.trim_leading(issue.body_md || "", "\n")

    "---\n" <> yaml <> "---\n\n" <> body_md
  end

  @spec new(String.t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(issue_id, attrs) when is_binary(issue_id) and is_map(attrs) do
    attrs = attrs |> Map.new() |> stringify_keys()

    title = Map.get(attrs, "title")
    body_md = Map.get(attrs, "body_md", "")
    dependencies = Map.get(attrs, "dependencies")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    params = %{
      "id" => issue_id,
      "status" => Map.get(attrs, "status", "open"),
      "priority" => Map.get(attrs, "priority", 2),
      "created_at" => now,
      "updated_at" => now,
      "labels" => List.wrap(Map.get(attrs, "labels", [])),
      "assignee" => Map.get(attrs, "assignee"),
      "references" => Map.get(attrs, "references", %{}),
      "body_md" => build_body(title, body_md, dependencies)
    }

    changeset = create_changeset(%__MODULE__{}, params)

    if changeset.valid? do
      {:ok, changeset |> apply_changes() |> put_virtuals_from_body()}
    else
      {:error, changeset}
    end
  end

  @spec apply_update(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def apply_update(%__MODULE__{} = issue, attrs) when is_map(attrs) do
    attrs = attrs |> Map.new() |> stringify_keys()

    title = Map.get(attrs, "title")
    body_md = Map.get(attrs, "body_md")

    body_md =
      cond do
        is_binary(body_md) and is_binary(title) -> set_title(body_md, title)
        is_binary(body_md) -> body_md
        is_binary(title) -> set_title(issue.body_md || "", title)
        true -> issue.body_md || ""
      end

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    params =
      %{
        "status" => Map.get(attrs, "status", issue.status),
        "priority" => Map.get(attrs, "priority", issue.priority),
        "labels" => Map.get(attrs, "labels", issue.labels),
        "assignee" => Map.get(attrs, "assignee", issue.assignee),
        "references" => Map.get(attrs, "references", issue.references),
        "updated_at" => now,
        "body_md" => body_md
      }

    changeset = update_changeset(issue, params)

    if changeset.valid? do
      {:ok, changeset |> apply_changes() |> put_virtuals_from_body()}
    else
      {:error, changeset}
    end
  end

  @spec updated_at_iso8601(t()) :: String.t() | nil
  def updated_at_iso8601(%__MODULE__{updated_at: %DateTime{} = dt}), do: DateTime.to_iso8601(dt)
  def updated_at_iso8601(_), do: nil

  @spec frontmatter_map(t()) :: map()
  def frontmatter_map(%__MODULE__{} = issue) do
    %{
      "id" => issue.id,
      "status" => issue.status,
      "priority" => issue.priority,
      "created_at" => datetime_iso(issue.created_at),
      "updated_at" => datetime_iso(issue.updated_at),
      "labels" => issue.labels || [],
      "assignee" => issue.assignee,
      "references" => issue.references || %{}
    }
  end

  @spec build_body(String.t() | nil, String.t() | nil, [String.t()] | nil) :: String.t()
  def build_body(title, body_md, dependencies \\ nil)
      when (is_binary(title) or is_nil(title)) and (is_binary(body_md) or is_nil(body_md)) do
    title = title || ""
    body_md = body_md || ""

    base = ["# " <> title, "", String.trim_leading(body_md, "\n")]

    deps_block =
      case List.wrap(dependencies) do
        [] ->
          []

        deps ->
          ["", "## Dependencies", "" | Enum.map(deps, &("- " <> &1))]
      end

    (base ++ deps_block)
    |> Enum.join("\n")
    |> String.trim_trailing()
    |> Kernel.<>("\n")
  end

  @spec set_title(String.t(), String.t()) :: String.t()
  def set_title(body_md, title) when is_binary(body_md) and is_binary(title) do
    if Regex.match?(~r/^\s*#\s+/m, body_md) do
      String.replace(body_md, ~r/^\s*#\s+.*$/m, "# " <> title, global: false)
    else
      build_body(title, body_md)
    end
  end

  @spec extract_title(String.t()) :: String.t() | nil
  def extract_title(body_md) when is_binary(body_md) do
    case Regex.run(~r/^\s*#\s+(.+?)\s*$/m, body_md) do
      [_, title] -> title
      _ -> nil
    end
  end

  defp from_frontmatter_and_body(frontmatter, body_md)
       when is_map(frontmatter) and is_binary(body_md) do
    params =
      frontmatter
      |> Map.put("body_md", body_md)

    changeset = create_changeset(%__MODULE__{}, params)

    if changeset.valid? do
      {:ok, changeset |> apply_changes() |> put_virtuals_from_body()}
    else
      {:error, {:validation, changeset}}
    end
  end

  defp create_changeset(issue, attrs) do
    issue
    |> cast(attrs, [
      :id,
      :status,
      :priority,
      :created_at,
      :updated_at,
      :labels,
      :assignee,
      :references,
      :body_md
    ])
    |> validate_required([:id, :status, :priority, :created_at, :updated_at, :body_md])
    |> validate_format(:id, ~r/^iss_[A-Za-z0-9\-_.]+$/)
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 4)
  end

  defp update_changeset(issue, attrs) do
    issue
    |> cast(attrs, [:status, :priority, :labels, :assignee, :references, :updated_at, :body_md])
    |> validate_required([:status, :priority, :updated_at, :body_md])
    |> validate_inclusion(:status, @statuses)
    |> validate_number(:priority, greater_than_or_equal_to: 0, less_than_or_equal_to: 4)
  end

  defp put_virtuals_from_body(%__MODULE__{} = issue) do
    title = extract_title(issue.body_md || "")
    %__MODULE__{issue | title: title}
  end

  defp split_frontmatter(content) do
    lines = String.split(content, "\n", trim: false)

    case lines do
      ["---" | rest] ->
        {yaml_lines, rest_after_yaml} = Enum.split_while(rest, &(&1 != "---"))

        case rest_after_yaml do
          ["---" | body_lines] ->
            {:ok, {Enum.join(yaml_lines, "\n"), Enum.join(body_lines, "\n")}}

          _ ->
            {:error, :invalid_frontmatter}
        end

      _ ->
        {:error, :missing_frontmatter}
    end
  end

  defp parse_frontmatter(yaml) do
    try do
      parsed =
        case YamlElixir.read_from_string(yaml) do
          {:ok, value} -> value
          value -> value
        end

      {:ok, stringify_keys_deep(parsed || %{})}
    rescue
      _ -> {:error, :invalid_yaml}
    end
  end

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end

  defp stringify_keys_deep(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), stringify_keys_deep(v)} end)
    |> Map.new()
  end

  defp stringify_keys_deep(list) when is_list(list), do: Enum.map(list, &stringify_keys_deep/1)
  defp stringify_keys_deep(value), do: value

  defp datetime_iso(nil), do: nil
  defp datetime_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime_iso(value) when is_binary(value), do: value

  defp dump_yaml(frontmatter) when is_map(frontmatter) do
    order = [
      "id",
      "status",
      "priority",
      "created_at",
      "updated_at",
      "labels",
      "assignee",
      "references"
    ]

    ordered_keys =
      order ++ (frontmatter |> Map.keys() |> Enum.reject(&(&1 in order)) |> Enum.sort())

    ordered_keys
    |> Enum.uniq()
    |> Enum.flat_map(fn key ->
      case Map.fetch(frontmatter, key) do
        {:ok, value} -> dump_yaml_kv(key, value, 0)
        :error -> []
      end
    end)
    |> Enum.join("\n")
    |> Kernel.<>("\n")
  end

  defp dump_yaml_kv(key, value, indent) when is_binary(key) do
    prefix = String.duplicate("  ", indent)

    cond do
      is_map(value) ->
        header = prefix <> key <> ":"

        nested =
          value
          |> Enum.sort_by(fn {k, _v} -> to_string(k) end)
          |> Enum.flat_map(fn {k, v} -> dump_yaml_kv(to_string(k), v, indent + 1) end)

        [header | nested]

      is_list(value) ->
        header = prefix <> key <> ":"

        items =
          Enum.map(value, fn item ->
            prefix <> "  - " <> dump_yaml_scalar(item)
          end)

        [header | items]

      true ->
        [prefix <> key <> ": " <> dump_yaml_scalar(value)]
    end
  end

  defp dump_yaml_scalar(nil), do: "null"
  defp dump_yaml_scalar(true), do: "true"
  defp dump_yaml_scalar(false), do: "false"
  defp dump_yaml_scalar(%DateTime{} = dt), do: dump_yaml_scalar(DateTime.to_iso8601(dt))
  defp dump_yaml_scalar(value) when is_integer(value) or is_float(value), do: to_string(value)
  defp dump_yaml_scalar(value) when is_binary(value), do: Jason.encode!(value)
  defp dump_yaml_scalar(value), do: Jason.encode!(to_string(value))
end
