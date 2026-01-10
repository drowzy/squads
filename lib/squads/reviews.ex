defmodule Squads.Reviews do
  @moduledoc """
  Human review queue for board cards.

  Cards enter the REVIEW lane where an AI review is produced.
  This module surfaces cards that are ready for a human decision.
  """

  import Ecto.Query, warn: false

  alias Squads.Repo
  alias Squads.Board
  alias Squads.Board.Card

  @doc """
  Lists cards ready for human review for a project.

  Criteria:
  - lane == review
  - ai_review is present
  - human_review_status is nil or pending
  """
  def list_reviews(project_id) do
    Card
    |> where([c], c.project_id == ^project_id)
    |> where([c], c.lane == "review")
    |> where([c], not is_nil(c.ai_review))
    |> where([c], is_nil(c.human_review_status) or c.human_review_status == "pending")
    |> order_by([c], desc: c.updated_at)
    |> Repo.all()
    |> Repo.preload([:build_agent])
    |> Enum.map(&to_review_summary/1)
  end

  def get_review(id) do
    case Repo.get(Card, id) do
      nil ->
        {:error, :not_found}

      card ->
        card = Repo.preload(card, [:build_agent, :squad])
        {:ok, to_review_detail(card)}
    end
  end

  def submit_review(id, status, feedback \\ "")
      when status in ["approved", "changes_requested"] do
    Board.submit_human_review(id, status, feedback)
  end

  defp to_review_summary(card) do
    %{
      id: card.id,
      title: card.title || "(untitled)",
      summary: ai_summary(card.ai_review),
      status: card.human_review_status || "pending",
      author_name: card.build_agent && card.build_agent.name,
      project_id: card.project_id,
      inserted_at: card.inserted_at
    }
  end

  defp to_review_detail(card) do
    %{
      id: card.id,
      title: card.title || "(untitled)",
      summary: ai_summary(card.ai_review),
      diff: git_diff(card),
      status: card.human_review_status || "pending",
      author_name: card.build_agent && card.build_agent.name,
      project_id: card.project_id,
      inserted_at: card.inserted_at,
      pr_url: card.pr_url,
      ai_review: card.ai_review
    }
  end

  defp ai_summary(%{"summary" => summary}) when is_binary(summary), do: summary
  defp ai_summary(%{summary: summary}) when is_binary(summary), do: summary
  defp ai_summary(review) when is_map(review), do: Jason.encode!(review)
  defp ai_summary(_), do: ""

  defp git_diff(%Card{build_worktree_path: path, base_branch: base})
       when is_binary(path) and path != "" do
    if File.exists?(path) do
      base = if is_binary(base) and base != "", do: base, else: "main"

      case System.cmd("git", ["diff", "--patch", "#{base}...HEAD"],
             cd: path,
             stderr_to_stdout: true
           ) do
        {output, 0} -> output
        {output, _} -> output
      end
    else
      ""
    end
  end

  defp git_diff(_), do: ""
end
