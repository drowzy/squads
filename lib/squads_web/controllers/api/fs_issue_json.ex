defmodule SquadsWeb.API.FsIssueJSON do
  @moduledoc false

  alias Squads.Artifacts.Issue

  def index(%{issues: issues}) do
    %{data: issues}
  end

  def show(%{issue: %Issue{} = issue}) do
    %{data: issue_detail(issue)}
  end

  def create(%{issue: %Issue{} = issue}) do
    %{data: issue_card(issue)}
  end

  def update(%{issue: %Issue{} = issue}) do
    %{data: issue_card(issue)}
  end

  defp issue_detail(%Issue{} = issue) do
    %{
      id: issue.id,
      title: issue.title,
      frontmatter: Issue.frontmatter_map(issue),
      body_md: issue.body_md
    }
  end

  defp issue_card(%Issue{} = issue) do
    %{
      id: issue.id,
      path: issue.path,
      title: issue.title,
      status: issue.status
    }
  end
end
