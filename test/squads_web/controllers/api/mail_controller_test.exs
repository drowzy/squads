defmodule SquadsWeb.API.MailControllerTest do
  use SquadsWeb.ConnCase, async: true

  alias Squads.{Projects, Mail, Agents, Squads}

  setup %{tmp_dir: tmp_dir} do
    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = Squads.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, sender} =
      Agents.create_agent(%{
        name: "GreenPanda",
        slug: "green-panda",
        squad_id: squad.id
      })

    {:ok, recipient} =
      Agents.create_agent(%{
        name: "BlueLake",
        slug: "blue-lake",
        squad_id: squad.id
      })

    {:ok, project: project, sender: sender, recipient: recipient}
  end

  describe "GET /api/mail" do
    @tag :tmp_dir
    test "lists messages for an agent", %{
      conn: conn,
      project: project,
      sender: sender,
      recipient: recipient
    } do
      Mail.send_message(%{
        project_id: project.id,
        sender_id: sender.id,
        subject: "Hello",
        body_md: "World",
        to: [recipient.id]
      })

      conn = get(conn, ~p"/api/mail", %{"agent_id" => recipient.id})
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["subject"] == "Hello"
      assert hd(response["data"])["sender"]["name"] == "GreenPanda"
    end

    @tag :tmp_dir
    test "returns empty list if no messages", %{conn: conn, recipient: recipient} do
      conn = get(conn, ~p"/api/mail", %{"agent_id" => recipient.id})
      response = json_response(conn, 200)
      assert response["data"] == []
    end
  end

  describe "POST /api/mail" do
    @tag :tmp_dir
    test "sends a new message", %{
      conn: conn,
      project: project,
      sender: sender,
      recipient: recipient
    } do
      attrs = %{
        "project_id" => project.id,
        "sender_name" => sender.name,
        "subject" => "API Test",
        "body_md" => "Testing API",
        "to" => [recipient.name]
      }

      conn = post(conn, ~p"/api/mail", attrs)
      response = json_response(conn, 201)

      assert response["data"]["subject"] == "API Test"
      assert response["data"]["sender"]["id"] == sender.id
    end

    @tag :tmp_dir
    test "returns errors for invalid data", %{conn: conn, project: project, sender: sender} do
      attrs = %{
        "project_id" => project.id,
        "sender_id" => sender.id,
        # Subject is required
        "subject" => ""
      }

      conn = post(conn, ~p"/api/mail", attrs)
      assert json_response(conn, 400)["errors"] != %{}
    end
  end

  describe "POST /api/mail/:id/reply" do
    @tag :tmp_dir
    test "replies to a message", %{
      conn: conn,
      project: project,
      sender: sender,
      recipient: recipient
    } do
      {:ok, message} =
        Mail.send_message(%{
          project_id: project.id,
          sender_id: sender.id,
          subject: "Initial",
          body_md: "Body",
          to: [recipient.id]
        })

      attrs = %{
        "sender_id" => recipient.id,
        "body_md" => "Reply body"
      }

      conn = post(conn, ~p"/api/mail/#{message.id}/reply", attrs)
      response = json_response(conn, 201)

      assert response["data"]["subject"] == "Re: Initial"
      assert response["data"]["body_md"] == "Reply body"
      assert response["data"]["sender"]["id"] == recipient.id
    end
  end

  describe "POST /api/mail/:id/acknowledge" do
    @tag :tmp_dir
    test "acknowledges a message", %{
      conn: conn,
      project: project,
      sender: sender,
      recipient: recipient
    } do
      {:ok, message} =
        Mail.send_message(%{
          project_id: project.id,
          sender_id: sender.id,
          subject: "Ack me",
          body_md: "Please",
          to: [recipient.id],
          ack_required: true
        })

      conn = post(conn, ~p"/api/mail/#{message.id}/acknowledge", %{"agent_id" => recipient.id})
      assert response(conn, 204)

      # Verify in DB
      msg = Mail.get_message!(message.id)
      recipient_record = Enum.find(msg.recipients, &(&1.agent_id == recipient.id))
      assert recipient_record.acknowledged_at != nil
    end
  end

  describe "GET /api/mail/search" do
    @tag :tmp_dir
    test "searches messages", %{
      conn: conn,
      project: project,
      sender: sender,
      recipient: recipient
    } do
      Mail.send_message(%{
        project_id: project.id,
        sender_id: sender.id,
        subject: "Unique topic",
        body_md: "Some content",
        to: [recipient.id]
      })

      conn = get(conn, ~p"/api/mail/search", %{"project_id" => project.id, "q" => "Unique"})
      response = json_response(conn, 200)

      assert length(response["data"]) == 1
      assert hd(response["data"])["subject"] == "Unique topic"
    end
  end
end
