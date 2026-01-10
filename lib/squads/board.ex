defmodule Squads.Board do
  @moduledoc """
  Local-first Kanban board for build requests.

  A board is grouped by squad (sections). Each card moves through lanes:
  TODO -> PLAN -> BUILD -> REVIEW.

  Cards collect durable artifacts as they progress (PRD path, GitHub issues, PR URL,
  AI review output, human review state).
  """

  import Ecto.Query, warn: false

  alias Ecto.Multi
  alias Squads.Repo

  alias Squads.Board.{Card, LaneAssignment, Extractors, Prompts}
  alias Squads.GitHub.RepoResolver
  alias Squads.GitHub.Client, as: GitHubClient
  alias Squads.Projects
  alias Squads.Sessions
  alias Squads.Sessions.Transcripts
  alias Squads.Squads, as: SquadsContext
  alias Squads.Worktrees

  @lanes ~w(todo plan build review done)

  def list_board(project_id) do
    squads = SquadsContext.list_squads_with_agents(project_id)

    assignments =
      LaneAssignment
      |> where([a], a.project_id == ^project_id)
      |> Repo.all()

    cards =
      Card
      |> where([c], c.project_id == ^project_id)
      |> order_by([c], asc: c.squad_id, asc: c.lane, asc: c.position, desc: c.inserted_at)
      |> Repo.all()

    %{
      squads: squads,
      assignments: assignments,
      cards: cards
    }
  end

  def board_summary(project_id) do
    Card
    |> where([c], c.project_id == ^project_id)
    |> group_by([c], c.lane)
    |> select([c], {c.lane, count(c.id)})
    |> Repo.all()
    |> Enum.into(%{})
    |> then(fn counts ->
      %{
        todo: Map.get(counts, "todo", 0),
        plan: Map.get(counts, "plan", 0),
        build: Map.get(counts, "build", 0),
        review: Map.get(counts, "review", 0),
        done: Map.get(counts, "done", 0)
      }
    end)
  end

  def create_card(project_id, squad_id, body) when is_binary(body) do
    title = derive_title(body)

    %Card{}
    |> Card.changeset(%{
      project_id: project_id,
      squad_id: squad_id,
      lane: "todo",
      body: body,
      title: title
    })
    |> Repo.insert()
  end

  def upsert_lane_assignment(project_id, squad_id, lane, agent_id) do
    attrs = %{project_id: project_id, squad_id: squad_id, lane: lane, agent_id: agent_id}

    %LaneAssignment{}
    |> LaneAssignment.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:agent_id, :updated_at]},
      conflict_target: [:project_id, :squad_id, :lane]
    )
  end

  def move_card(card_id, lane) when lane in @lanes do
    with %Card{} = card <- Repo.get(Card, card_id) |> Repo.preload([:squad]) do
      case lane do
        "todo" ->
          update_card(card, %{lane: "todo"})

        "plan" ->
          start_lane_session(card, "plan")

        "build" ->
          start_lane_session(card, "build")

        "review" ->
          start_lane_session(card, "review")

        "done" ->
          # DONE is only reachable via human review approval.
          {:error, :forbidden}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  def set_pr_url(card_id, pr_url) when is_binary(pr_url) do
    with %Card{} = card <- Repo.get(Card, card_id) do
      pr_url = String.trim(pr_url)

      if pr_url == "" do
        {:error, :invalid_pr_url}
      else
        updated_issue_refs = soft_close_issue_refs(card.issue_refs)

        update_card(card, %{pr_url: pr_url, pr_opened_at: now(), issue_refs: updated_issue_refs})
      end
    else
      nil -> {:error, :not_found}
    end
  end

  def create_issues_from_plan(card_id) do
    with %Card{} = card <- Repo.get(Card, card_id) |> Repo.preload([:project, :squad]),
         {:ok, plan} <- ensure_issue_plan(card),
         {:ok, repo} <- RepoResolver.github_repo_for_project(card.project_id) do
      issues = Map.get(plan, "issues", [])

      with :ok <- ensure_labels(repo, issues) do
        created =
          issues
          |> Enum.map(fn issue ->
            attrs = %{
              title: issue["title"],
              body: issue["body_md"],
              labels: issue["labels"] || ["squads"]
            }

            GitHubClient.client().create_issue(repo, attrs, [])
          end)

        {oks, errors} =
          Enum.split_with(created, fn
            {:ok, _} -> true
            _ -> false
          end)

        if errors != [] do
          {:error, {:github_error, errors}}
        else
          refs =
            oks
            |> Enum.map(fn {:ok, issue} ->
              %{
                "repo" => repo,
                "number" => issue["number"],
                "url" => issue["html_url"],
                "title" => issue["title"],
                "github_state" => issue["state"],
                "soft_state" => "open"
              }
            end)

          update_card(card, %{issue_plan: plan, issue_refs: %{"issues" => refs}})
        end
      end
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def request_create_pr(card_id) do
    with %Card{} = card <- Repo.get(Card, card_id) |> Repo.preload([:squad]),
         {:ok, session} <- ensure_build_session(card) do
      issue_refs = (card.issue_refs || %{})["issues"] || []
      Sessions.send_prompt_async(session, Prompts.create_pr_prompt(issue_refs))
    else
      nil -> {:error, :not_found}
      {:error, reason} -> {:error, reason}
    end
  end

  def sync_artifacts(card_id) do
    with %Card{} = card <- Repo.get(Card, card_id) do
      card =
        Repo.preload(card, [:plan_session, :build_session, :review_session, :ai_review_session])

      Multi.new()
      |> Multi.run(:plan, fn _repo, _ -> sync_from_session(card.plan_session_id, :issue_plan) end)
      |> Multi.run(:build, fn _repo, _ ->
        sync_from_session(card.build_session_id, :build_result)
      end)
      |> Multi.run(:review, fn _repo, _ ->
        sync_from_session(card.review_session_id, :ai_review)
      end)
      |> Multi.run(:update, fn repo, results ->
        patch = artifact_patch(card, results)

        if patch == %{} do
          {:ok, card}
        else
          repo.update(Card.changeset(card, patch))
        end
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{update: updated}} -> {:ok, updated}
        {:error, _step, reason, _} -> {:error, reason}
      end
    else
      nil -> {:error, :not_found}
    end
  end

  def submit_human_review(card_id, status, feedback \\ "")
      when status in ["approved", "changes_requested"] do
    with %Card{} = card <- Repo.get(Card, card_id) do
      base_attrs = %{
        human_review_status: status,
        human_review_feedback: feedback,
        human_reviewed_at: now()
      }

      case status do
        "changes_requested" ->
          update_card(card, Map.put(base_attrs, :lane, "build"))

        "approved" ->
          if is_binary(card.pr_url) and String.trim(card.pr_url) != "" do
            update_card(card, Map.put(base_attrs, :lane, "done"))
          else
            {:error, :missing_pr_url}
          end
      end
    else
      nil -> {:error, :not_found}
    end
  end

  # ---------------------------------------------------------------------------
  # Internals
  # ---------------------------------------------------------------------------

  defp start_lane_session(%Card{} = card, lane) when lane in ["plan", "build", "review"] do
    with {:ok, agent_id} <- lane_agent_id(card, lane),
         {:ok, project} <- fetch_project(card.project_id),
         {:ok, repo} <- repo_or_empty(card.project_id) do
      prepared_attrs = prepare_attrs_for_lane(card, lane, project)
      prepared = Ecto.Changeset.apply_changes(Card.changeset(card, prepared_attrs))

      Multi.new()
      |> Multi.run(:session, fn _repo, _ ->
        create_lane_session(prepared, lane, agent_id, project)
      end)
      |> Multi.update(:card, fn %{session: session} ->
        patch = Map.merge(prepared_attrs, lane_session_patch(prepared, lane, agent_id, session))
        Card.changeset(card, patch)
      end)
      |> Repo.transaction()
      |> case do
        {:ok, %{card: updated, session: session}} ->
          updated = Repo.preload(updated, [:squad])
          send_lane_prompt_async(updated, lane, session, repo)
          {:ok, updated}

        {:error, _step, reason, _} ->
          {:error, reason}
      end
    else
      {:error, reason} -> {:error, reason}
    end
  end

  defp prepare_attrs_for_lane(card, "plan", project) do
    prd_path = card.prd_path || next_prd_path(project.path, card.title || card.body)
    %{lane: "plan", prd_path: prd_path}
  end

  defp prepare_attrs_for_lane(_card, "build", project) do
    %{lane: "build", base_branch: detect_default_branch(project.path)}
  end

  defp prepare_attrs_for_lane(card, "review", project) do
    base_branch = card.base_branch || detect_default_branch(project.path)
    %{lane: "review", base_branch: base_branch}
  end

  defp create_lane_session(card, "plan", agent_id, _project) do
    Sessions.new_session_for_agent(agent_id, %{title: "PLAN: #{card.title}"})
  end

  defp create_lane_session(card, "build", agent_id, _project) do
    worktree_name = "#{agent_slug!(agent_id)}-#{card.id}"

    with {:ok, worktree_path} <- Worktrees.ensure_worktree(card.project_id, agent_id, card.id) do
      branch = "squads/#{worktree_name}"

      Sessions.new_session_for_agent(agent_id, %{
        title: "BUILD: #{card.title}",
        worktree_path: worktree_path,
        branch: branch
      })
    end
  end

  defp create_lane_session(card, "review", agent_id, project) do
    worktree_path = card.build_worktree_path || project.path
    branch = card.build_branch || ""

    Sessions.new_session_for_agent(agent_id, %{
      title: "REVIEW: #{card.title}",
      worktree_path: worktree_path,
      branch: branch
    })
  end

  defp lane_session_patch(_card, "plan", agent_id, session) do
    %{plan_agent_id: agent_id, plan_session_id: session.id}
  end

  defp lane_session_patch(card, "build", agent_id, session) do
    worktree_name = "#{agent_slug!(agent_id)}-#{card.id}"

    %{
      build_agent_id: agent_id,
      build_session_id: session.id,
      build_worktree_name: worktree_name,
      build_worktree_path: session.worktree_path,
      build_branch: session.branch
    }
  end

  defp lane_session_patch(_card, "review", agent_id, session) do
    %{review_agent_id: agent_id, review_session_id: session.id, ai_review_session_id: session.id}
  end

  defp send_lane_prompt_async(card, "plan", session, repo) do
    prompt =
      Prompts.plan_prompt(
        squad_name: card.squad && card.squad.name,
        card_body: card.body,
        prd_path: card.prd_path,
        github_repo: repo
      )

    Sessions.send_prompt_async(session, prompt)
  end

  defp send_lane_prompt_async(card, "build", session, _repo) do
    issue_refs = (card.issue_refs || %{})["issues"] || []

    prompt =
      Prompts.build_prompt(
        squad_name: card.squad && card.squad.name,
        prd_path: card.prd_path,
        issue_refs: issue_refs,
        pr_url: card.pr_url,
        worktree_path: card.build_worktree_path,
        branch: card.build_branch,
        base_branch: card.base_branch
      )

    Sessions.send_prompt_async(session, prompt)
  end

  defp send_lane_prompt_async(card, "review", session, _repo) do
    prompt =
      Prompts.review_prompt(
        squad_name: card.squad && card.squad.name,
        pr_url: card.pr_url,
        prd_path: card.prd_path,
        worktree_path: card.build_worktree_path,
        branch: card.build_branch,
        base_branch: card.base_branch
      )

    Sessions.send_prompt_async(session, prompt)
  end

  defp update_card(%Card{} = card, attrs) do
    card
    |> Card.changeset(attrs)
    |> Repo.update()
  end

  defp lane_agent_id(%Card{} = card, lane) do
    assignment =
      LaneAssignment
      |> where(
        [a],
        a.project_id == ^card.project_id and a.squad_id == ^card.squad_id and a.lane == ^lane
      )
      |> Repo.one()

    cond do
      is_nil(assignment) -> {:error, {:lane_unassigned, lane}}
      is_nil(assignment.agent_id) -> {:error, {:lane_unassigned, lane}}
      true -> {:ok, assignment.agent_id}
    end
  end

  defp fetch_project(project_id) do
    case Projects.get_project(project_id) do
      %Projects.Project{} = project -> {:ok, project}
      nil -> {:error, :not_found}
    end
  end

  defp repo_or_empty(project_id) do
    case RepoResolver.github_repo_for_project(project_id) do
      {:ok, repo} -> {:ok, repo}
      {:error, _} -> {:ok, ""}
    end
  end

  defp ensure_issue_plan(%Card{} = card) do
    cond do
      is_map(card.issue_plan) ->
        {:ok, card.issue_plan}

      is_nil(card.plan_session_id) ->
        {:error, :missing_plan_session}

      true ->
        with {:ok, session} <- Sessions.fetch_session(card.plan_session_id),
             {:ok, _} <- Transcripts.sync_session_transcript(session),
             {entries, _meta} <-
               Sessions.list_transcript_entries(card.plan_session_id, limit: 500),
             {:ok, plan} <- Extractors.extract_issue_plan(entries) do
          {:ok, plan}
        else
          _ -> {:error, :issue_plan_not_found}
        end
    end
  end

  defp ensure_build_session(%Card{} = card) do
    cond do
      not is_nil(card.build_session_id) ->
        Sessions.fetch_session(card.build_session_id)

      true ->
        with {:ok, _agent_id} <- lane_agent_id(card, "build"),
             {:ok, updated} <- start_lane_session(card, "build"),
             %Card{build_session_id: session_id} <- updated,
             {:ok, session} <- Sessions.fetch_session(session_id) do
          {:ok, session}
        end
    end
  end

  defp sync_from_session(nil, _kind), do: {:ok, nil}

  defp sync_from_session(session_id, kind)
       when kind in [:issue_plan, :build_result, :ai_review] do
    with {:ok, session} <- Sessions.fetch_session(session_id),
         {:ok, _count} <- Transcripts.sync_session_transcript(session),
         {entries, _meta} <- Sessions.list_transcript_entries(session_id, limit: 500) do
      case kind do
        :issue_plan -> Extractors.extract_issue_plan(entries)
        :build_result -> Extractors.extract_build_result(entries)
        :ai_review -> Extractors.extract_ai_review(entries)
      end
      |> case do
        {:ok, obj} -> {:ok, obj}
        :error -> {:ok, nil}
      end
    end
  end

  defp artifact_patch(card, results) do
    patch = %{}

    patch =
      case results[:plan] do
        %{} = plan when is_nil(card.issue_plan) -> Map.put(patch, :issue_plan, plan)
        _ -> patch
      end

    patch =
      case results[:build] do
        %{"pr_url" => pr_url} when is_binary(pr_url) and pr_url != "" and is_nil(card.pr_url) ->
          patch
          |> Map.put(:pr_url, pr_url)
          |> Map.put(:pr_opened_at, now())
          |> Map.put(:issue_refs, soft_close_issue_refs(card.issue_refs))

        _ ->
          patch
      end

    patch =
      case results[:review] do
        %{} = review when is_nil(card.ai_review) ->
          patch
          |> Map.put(:ai_review, review)
          |> Map.put(:human_review_status, "pending")

        _ ->
          patch
      end

    patch
  end

  defp soft_close_issue_refs(nil), do: nil

  defp soft_close_issue_refs(%{"issues" => issues} = refs) when is_list(issues) do
    updated =
      Enum.map(issues, fn issue ->
        issue
        |> Map.put("soft_state", "soft_closed")
      end)

    Map.put(refs, "issues", updated)
  end

  defp soft_close_issue_refs(refs), do: refs

  defp ensure_labels(_repo, []), do: :ok

  defp ensure_labels(repo, issues) when is_list(issues) do
    labels =
      issues
      |> Enum.flat_map(fn issue -> issue["labels"] || ["squads"] end)
      |> Enum.uniq()

    Enum.reduce_while(labels, :ok, fn name, :ok ->
      case ensure_github_label(repo, name) do
        :ok -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  defp ensure_github_label(repo, name) when is_binary(name) and name != "" do
    case GitHubClient.client().get_label(repo, name, []) do
      {:ok, _} ->
        :ok

      {:error, {:http_error, 404, _}} ->
        GitHubClient.client().create_label(
          repo,
          %{name: name, color: "ededed", description: ""},
          []
        )
        |> case do
          {:ok, _} -> :ok
          {:error, reason} -> {:error, reason}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp derive_title(body) do
    body
    |> String.split("\n")
    |> List.first()
    |> to_string()
    |> String.trim()
    |> case do
      "" -> "(untitled)"
      title -> String.slice(title, 0, 120)
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp next_prd_path(project_path, seed) do
    dir = Path.join([project_path, ".squads", "prds"])
    File.mkdir_p!(dir)

    seq = next_prd_seq(dir)
    slug = slugify(seed)

    Path.join([
      ".squads",
      "prds",
      String.pad_leading(Integer.to_string(seq), 3, "0") <> "-" <> slug <> ".md"
    ])
  end

  defp next_prd_seq(dir) do
    case File.ls(dir) do
      {:ok, files} ->
        files
        |> Enum.map(&Regex.run(~r/^(\d{3})[-.]/, &1))
        |> Enum.filter(&is_list/1)
        |> Enum.map(fn [_, digits] -> String.to_integer(digits) end)
        |> Enum.max(fn -> 0 end)
        |> Kernel.+(1)

      _ ->
        1
    end
  end

  defp slugify(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9\s-]/, "")
    |> String.replace(~r/\s+/, "-")
    |> String.replace(~r/-+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "card"
      slug -> String.slice(slug, 0, 48)
    end
  end

  defp detect_default_branch(repo_path) do
    case System.cmd("git", ["symbolic-ref", "refs/remotes/origin/HEAD"],
           cd: repo_path,
           stderr_to_stdout: true
         ) do
      {output, 0} -> output |> String.trim() |> Path.basename()
      _ -> "main"
    end
  end

  defp agent_slug!(agent_id) do
    agent = Repo.get!(Squads.Agents.Agent, agent_id)
    agent.slug
  end
end
