defmodule Squads.Reviews.ReviewComment do
  @moduledoc """
  Review comment schema.

  Comments can reference:
  - "summary": General comment on the review
  - "file": Comment on a specific file
  - "line": Comment on a specific line in a file
  """

  use Ecto.Schema

  import Ecto.Changeset

  alias Squads.Reviews.Review

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @types ~w(summary file line)
  @diff_sides ~w(old new)
  @author_types ~w(agent human system)

  schema "review_comments" do
    belongs_to :review, Review

    # Comment type
    field :type, :string

    # Content
    field :body, :string

    # Author tracking
    field :author_type, :string, default: "human"
    field :author_name, :string

    # Location (for file/line types)
    field :file_path, :string
    field :line_number, :integer
    field :diff_side, :string

    # Code context snippets
    field :before_context, :string
    field :after_context, :string

    timestamps(type: :utc_datetime)
  end

  @required_fields ~w(review_id type body)a
  @optional_fields ~w(
    author_type author_name
    file_path line_number diff_side
    before_context after_context
  )a

  def changeset(comment, attrs) do
    comment
    |> cast(attrs, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_inclusion(:type, @types)
    |> validate_inclusion(:diff_side, @diff_sides)
    |> validate_inclusion(:author_type, @author_types)
    |> validate_location()
    |> foreign_key_constraint(:review_id)
  end

  defp validate_location(changeset) do
    type = get_field(changeset, :type)

    case type do
      "file" ->
        changeset
        |> validate_required([:file_path])

      "line" ->
        changeset
        |> validate_required([:file_path, :line_number])

      _ ->
        changeset
    end
  end

  def types, do: @types
  def diff_sides, do: @diff_sides
  def author_types, do: @author_types
end
