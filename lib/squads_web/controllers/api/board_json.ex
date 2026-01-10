defmodule SquadsWeb.API.BoardJSON do
  @moduledoc false

  alias Squads.Board.{Card, LaneAssignment}
  alias Squads.Squads.Squad
  alias Squads.Agents.Agent

  def show(%{board: %{squads: squads, assignments: assignments, cards: cards}}) do
    %{
      data: %{
        squads: Enum.map(squads, &squad_data/1),
        lane_assignments: Enum.map(assignments, &assignment_data/1),
        cards: Enum.map(cards, &card_data/1)
      }
    }
  end

  def card(%{card: %Card{} = card}) do
    %{data: card_data(card)}
  end

  def lane_assignment(%{assignment: %LaneAssignment{} = assignment}) do
    %{data: assignment_data(assignment)}
  end

  defp squad_data(%Squad{} = squad) do
    base = %{
      id: squad.id,
      name: squad.name,
      description: squad.description,
      project_id: squad.project_id,
      inserted_at: squad.inserted_at,
      updated_at: squad.updated_at
    }

    if Ecto.assoc_loaded?(squad.agents) do
      Map.put(base, :agents, Enum.map(squad.agents, &agent_data/1))
    else
      base
    end
  end

  defp agent_data(%Agent{} = agent) do
    %{
      id: agent.id,
      name: agent.name,
      slug: agent.slug,
      model: agent.model,
      role: agent.role,
      level: agent.level,
      status: agent.status,
      squad_id: agent.squad_id,
      mentor_id: agent.mentor_id,
      inserted_at: agent.inserted_at,
      updated_at: agent.updated_at
    }
  end

  defp assignment_data(%LaneAssignment{} = a) do
    %{
      id: a.id,
      project_id: a.project_id,
      squad_id: a.squad_id,
      lane: a.lane,
      agent_id: a.agent_id,
      inserted_at: a.inserted_at,
      updated_at: a.updated_at
    }
  end

  defp card_data(%Card{} = c) do
    %{
      id: c.id,
      project_id: c.project_id,
      squad_id: c.squad_id,
      lane: c.lane,
      position: c.position,
      title: c.title,
      body: c.body,
      prd_path: c.prd_path,
      issue_plan: c.issue_plan,
      issue_refs: c.issue_refs,
      pr_url: c.pr_url,
      pr_opened_at: c.pr_opened_at,
      plan_agent_id: c.plan_agent_id,
      build_agent_id: c.build_agent_id,
      review_agent_id: c.review_agent_id,
      plan_session_id: c.plan_session_id,
      build_session_id: c.build_session_id,
      review_session_id: c.review_session_id,
      build_worktree_name: c.build_worktree_name,
      build_worktree_path: c.build_worktree_path,
      build_branch: c.build_branch,
      base_branch: c.base_branch,
      ai_review: c.ai_review,
      ai_review_session_id: c.ai_review_session_id,
      human_review_status: c.human_review_status,
      human_review_feedback: c.human_review_feedback,
      human_reviewed_at: c.human_reviewed_at,
      inserted_at: c.inserted_at,
      updated_at: c.updated_at
    }
  end
end
