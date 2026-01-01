defmodule Squads.ReviewsTest do
  use Squads.DataCase, async: true

  alias Squads.Reviews
  alias Squads.Projects
  alias Squads.Squads, as: SquadsContext
  alias Squads.Agents
  alias Squads.Tickets

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("review_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, junior} =
      Agents.create_agent(%{squad_id: squad.id, name: "GreenPanda", slug: "green-panda"})

    {:ok, senior} =
      Agents.create_agent(%{
        squad_id: squad.id,
        name: "BlueLake",
        slug: "blue-lake",
        model: "gpt-4o"
      })

    {:ok, ticket} =
      Tickets.create_ticket(%{
        project_id: project.id,
        beads_id: "test-123",
        title: "Test Ticket",
        assignee_id: junior.id
      })

    %{
      project: project,
      squad: squad,
      junior: junior,
      senior: senior,
      ticket: ticket
    }
  end

  describe "mentor mapping" do
    test "suggests mentor as reviewer when author has mentor", %{
      junior: junior,
      senior: senior,
      ticket: ticket
    } do
      {:ok, updated_junior} =
        Agents.update_agent(junior, %{mentor_id: senior.id})

      {:ok, review} =
        Reviews.create_review(%{
          ticket_id: ticket.id,
          author_id: updated_junior.id,
          reviewer_id: senior.id
        })

      assert review.reviewer_id == senior.id
      assert review.status == "pending"
    end

    test "suggest_reviewer returns mentor_id when author has mentor", %{
      junior: junior,
      senior: senior
    } do
      {:ok, updated_junior} =
        Agents.update_agent(junior, %{mentor_id: senior.id})

      {:ok, mentor_id} = Reviews.suggest_reviewer(updated_junior.id)
      assert mentor_id == senior.id
    end

    test "suggest_reviewer returns nil when author has no mentor", %{
      junior: junior
    } do
      {:ok, mentor_id} = Reviews.suggest_reviewer(junior.id)
      assert mentor_id == nil
    end
  end

  describe "review workflow" do
    test "creates review with pending status", %{
      junior: junior,
      senior: senior,
      ticket: ticket
    } do
      {:ok, review} =
        Reviews.create_review(%{
          ticket_id: ticket.id,
          author_id: junior.id,
          reviewer_id: senior.id
        })

      assert review.status == "pending"
      assert review.ticket_id == ticket.id
      assert review.author_id == junior.id
      assert review.reviewer_id == senior.id
    end

    test "starts review (pending -> in_review)", %{
      junior: junior,
      senior: senior,
      ticket: ticket
    } do
      {:ok, review} =
        Reviews.create_review(%{
          ticket_id: ticket.id,
          author_id: junior.id,
          reviewer_id: senior.id
        })

      {:ok, started_review} = Reviews.start_review(review)
      assert started_review.status == "in_review"
    end

    test "approves review", %{
      junior: junior,
      senior: senior,
      ticket: ticket
    } do
      {:ok, review} =
        Reviews.create_review(%{
          ticket_id: ticket.id,
          author_id: junior.id,
          reviewer_id: senior.id
        })

      {:ok, approved_review} = Reviews.approve_review(review)
      assert approved_review.status == "approved"
    end

    test "requests changes", %{
      junior: junior,
      senior: senior,
      ticket: ticket
    } do
      {:ok, review} =
        Reviews.create_review(%{
          ticket_id: ticket.id,
          author_id: junior.id,
          reviewer_id: senior.id
        })

      {:ok, changed_review} = Reviews.request_changes(review, "Please fix the tests")
      assert changed_review.status == "changes_requested"
      assert changed_review.summary == "Please fix the tests"
    end
  end

  describe "list reviews" do
    test "lists reviews for ticket", %{
      junior: junior,
      senior: senior,
      ticket: ticket
    } do
      {:ok, review1} =
        Reviews.create_review(%{
          ticket_id: ticket.id,
          author_id: junior.id,
          reviewer_id: senior.id
        })

      {:ok, review2} =
        Reviews.create_review(%{
          ticket_id: ticket.id,
          author_id: senior.id,
          reviewer_id: junior.id
        })

      reviews = Reviews.list_reviews_for_ticket(ticket.id)
      assert length(reviews) == 2
      assert Enum.any?(reviews, fn r -> r.id == review1.id end)
      assert Enum.any?(reviews, fn r -> r.id == review2.id end)
    end

    test "returns pending reviews for reviewer", %{
      junior: junior,
      senior: senior,
      ticket: ticket
    } do
      {:ok, review1} =
        Reviews.create_review(%{
          ticket_id: ticket.id,
          author_id: junior.id,
          reviewer_id: senior.id
        })

      {:ok, _review2} =
        Reviews.create_review(%{
          ticket_id: ticket.id,
          author_id: senior.id,
          reviewer_id: junior.id
        })

      pending = Reviews.pending_reviews_for_reviewer(senior.id)
      assert length(pending) == 1
      assert hd(pending).id == review1.id
    end
  end
end
