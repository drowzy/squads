defmodule Squads.MailTest do
  use Squads.DataCase, async: true

  alias Squads.Mail
  alias Squads.Projects
  alias Squads.Squads, as: SquadsContext
  alias Squads.Agents

  setup do
    tmp_dir = System.tmp_dir!() |> Path.join("mail_test_#{:rand.uniform(1_000_000)}")
    File.mkdir_p!(tmp_dir)
    on_exit(fn -> File.rm_rf!(tmp_dir) end)

    {:ok, project} = Projects.init(tmp_dir, "test-project")
    {:ok, squad} = SquadsContext.create_squad(%{project_id: project.id, name: "Test Squad"})

    {:ok, agent1} =
      Agents.create_agent(%{squad_id: squad.id, name: "GreenPanda", slug: "green-panda"})

    {:ok, agent2} =
      Agents.create_agent(%{squad_id: squad.id, name: "BlueLake", slug: "blue-lake"})

    %{project: project, agent1: agent1, agent2: agent2}
  end

  describe "send_message/1" do
    test "creates a new thread and message", %{project: project, agent1: agent1, agent2: agent2} do
      attrs = %{
        project_id: project.id,
        sender_id: agent1.id,
        subject: "Hello",
        body_md: "World",
        to: [agent2.id]
      }

      assert {:ok, message} = Mail.send_message(attrs)
      assert message.subject == "Hello"
      assert message.body_md == "World"
      assert message.sender_id == agent1.id
      assert length(message.recipients) == 1
      assert hd(message.recipients).agent_id == agent2.id
      assert message.thread.subject == "Hello"
    end

    test "adds to existing thread", %{project: project, agent1: agent1, agent2: agent2} do
      assert {:ok, m1} =
               Mail.send_message(%{
                 project_id: project.id,
                 sender_id: agent1.id,
                 subject: "Thread 1",
                 body_md: "First",
                 to: [agent2.id]
               })

      assert {:ok, m2} =
               Mail.send_message(%{
                 thread_id: m1.thread_id,
                 project_id: project.id,
                 sender_id: agent2.id,
                 subject: "Re: Thread 1",
                 body_md: "Second",
                 to: [agent1.id]
               })

      assert m2.thread_id == m1.thread_id
      assert length(Mail.list_thread_messages(m1.thread_id)) == 2
    end
  end

  describe "mailbox operations" do
    setup %{project: project, agent1: agent1, agent2: agent2} do
      assert {:ok, m1} =
               Mail.send_message(%{
                 project_id: project.id,
                 sender_id: agent1.id,
                 subject: "Msg 1",
                 body_md: "Body 1",
                 to: [agent2.id]
               })

      %{message: m1}
    end

    test "list_inbox/1 returns messages for agent", %{agent2: agent2, message: message} do
      inbox = Mail.list_inbox(agent2.id)
      assert length(inbox) == 1
      assert hd(inbox).id == message.id
    end

    test "mark_as_read/2 updates recipient", %{agent2: agent2, message: message} do
      assert {:ok, _} = Mail.mark_as_read(message.id, agent2.id)

      updated = Mail.get_message!(message.id)
      recipient = hd(updated.recipients)
      assert recipient.read_at != nil
    end

    test "acknowledge/2 updates recipient", %{agent2: agent2, message: message} do
      assert {:ok, _} = Mail.acknowledge(message.id, agent2.id)

      updated = Mail.get_message!(message.id)
      recipient = hd(updated.recipients)
      assert recipient.acknowledged_at != nil
      assert recipient.read_at != nil
    end
  end

  describe "search_messages/3" do
    test "finds messages by content", %{project: project, agent1: agent1, agent2: agent2} do
      Mail.send_message(%{
        project_id: project.id,
        sender_id: agent1.id,
        subject: "Unique Subject",
        body_md: "Special Keyword",
        to: [agent2.id]
      })

      assert length(Mail.search_messages(project.id, "Unique")) == 1
      assert length(Mail.search_messages(project.id, "Keyword")) == 1
      assert length(Mail.search_messages(project.id, "Missing")) == 0
    end
  end
end
