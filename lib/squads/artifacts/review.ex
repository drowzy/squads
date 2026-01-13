defmodule Squads.Artifacts.Review do
  @moduledoc false

  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  embedded_schema do
    field :id, :string
    field :status, :string, default: "pending"
    field :created_at, :utc_datetime
    field :updated_at, :utc_datetime

    field :title, :string
    field :summary, :string
    field :highlights, {:array, :string}, default: []

    field :context, :map, default: %{}
    field :references, :map, default: %{}

    field :files_changed, {:array, :map}, default: []
    field :comments, {:array, :map}, default: []

    field :path, :string, virtual: true
  end

  @type t :: %__MODULE__{}

  @statuses ~w(pending approved changes_requested)

  @spec parse(String.t()) :: {:ok, t()} | {:error, term()}
  def parse(content) when is_binary(content) do
    with {:ok, raw} <- decode_json(content),
         {:ok, review} <- from_map(raw) do
      {:ok, review}
    end
  end

  @spec render(t()) :: String.t()
  def render(%__MODULE__{} = review) do
    review
    |> to_storage_map()
    |> Jason.encode!(pretty: true)
  end

  @spec new(String.t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def new(review_id, attrs) when is_binary(review_id) and is_map(attrs) do
    attrs = attrs |> Map.new() |> stringify_keys()
    now = DateTime.utc_now() |> DateTime.truncate(:second)

    params = %{
      "id" => review_id,
      "status" => Map.get(attrs, "status", "pending"),
      "created_at" => now,
      "updated_at" => now,
      "title" => Map.get(attrs, "title"),
      "summary" => Map.get(attrs, "summary"),
      "highlights" => List.wrap(Map.get(attrs, "highlights", [])),
      "context" => Map.get(attrs, "context", %{}),
      "references" => Map.get(attrs, "references", %{}),
      "files_changed" => List.wrap(Map.get(attrs, "files_changed", [])),
      "comments" => List.wrap(Map.get(attrs, "comments", []))
    }

    changeset = create_changeset(%__MODULE__{}, params)

    if changeset.valid? do
      {:ok, apply_changes(changeset)}
    else
      {:error, changeset}
    end
  end

  @spec apply_patch(t(), map()) :: {:ok, t()} | {:error, Ecto.Changeset.t()}
  def apply_patch(%__MODULE__{} = review, patch) when is_map(patch) do
    patch = patch |> Map.new() |> stringify_keys()

    patch_comments =
      patch
      |> Map.get("comments", [])
      |> List.wrap()

    patch = Map.delete(patch, "comments")

    now = DateTime.utc_now() |> DateTime.truncate(:second)

    params =
      review
      |> to_storage_map()
      |> Map.merge(patch)
      |> Map.update("comments", [], fn existing -> List.wrap(existing) ++ patch_comments end)
      |> Map.put("updated_at", DateTime.to_iso8601(now))

    changeset = update_changeset(review, params)

    if changeset.valid? do
      {:ok, apply_changes(changeset)}
    else
      {:error, changeset}
    end
  end

  @spec updated_at_iso8601(t()) :: String.t() | nil
  def updated_at_iso8601(%__MODULE__{updated_at: %DateTime{} = dt}), do: DateTime.to_iso8601(dt)
  def updated_at_iso8601(_), do: nil

  @spec to_storage_map(t()) :: map()
  def to_storage_map(%__MODULE__{} = review) do
    %{
      "id" => review.id,
      "status" => review.status,
      "created_at" => datetime_iso(review.created_at),
      "updated_at" => datetime_iso(review.updated_at),
      "title" => review.title,
      "summary" => review.summary,
      "highlights" => review.highlights || [],
      "context" => review.context || %{},
      "references" => review.references || %{},
      "files_changed" => review.files_changed || [],
      "comments" => review.comments || []
    }
  end

  defp decode_json(content) do
    case Jason.decode(content) do
      {:ok, data} when is_map(data) -> {:ok, data}
      {:ok, _} -> {:error, :invalid_review}
      {:error, %Jason.DecodeError{} = error} -> {:error, error}
    end
  end

  defp from_map(map) when is_map(map) do
    changeset = create_changeset(%__MODULE__{}, map)

    if changeset.valid? do
      {:ok, apply_changes(changeset)}
    else
      {:error, {:validation, changeset}}
    end
  end

  defp create_changeset(review, attrs) do
    review
    |> cast(attrs, [
      :id,
      :status,
      :created_at,
      :updated_at,
      :title,
      :summary,
      :highlights,
      :context,
      :references,
      :files_changed,
      :comments
    ])
    |> validate_required([:id, :status, :created_at, :updated_at, :title])
    |> validate_format(:id, ~r/^rev_[A-Za-z0-9\-_.]+$/)
    |> validate_inclusion(:status, @statuses)
  end

  defp update_changeset(review, attrs) do
    review
    |> cast(attrs, [
      :status,
      :updated_at,
      :title,
      :summary,
      :highlights,
      :context,
      :references,
      :files_changed,
      :comments
    ])
    |> validate_required([:status, :updated_at, :title])
    |> validate_inclusion(:status, @statuses)
  end

  defp stringify_keys(map) when is_map(map) do
    map
    |> Enum.map(fn {k, v} -> {to_string(k), v} end)
    |> Map.new()
  end

  defp datetime_iso(nil), do: nil
  defp datetime_iso(%DateTime{} = dt), do: DateTime.to_iso8601(dt)
  defp datetime_iso(value) when is_binary(value), do: value
end
