defmodule SquadsWeb.API.FsIssueController do
  use SquadsWeb, :controller

  alias Squads.Artifacts
  alias Squads.Projects

  action_fallback SquadsWeb.FallbackController

  def index(conn, %{"project_id" => project_id}) do
    with {:ok, uuid} <- cast_uuid(project_id),
         %Projects.Project{} = project <- Projects.get_project(uuid),
         {:ok, issues} <- Artifacts.list_issues(project.path) do
      render(conn, :index, issues: issues)
    else
      {:error, :not_found} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  def show(conn, %{"project_id" => project_id, "id" => issue_id}) do
    with {:ok, uuid} <- cast_uuid(project_id),
         %Projects.Project{} = project <- Projects.get_project(uuid),
         {:ok, issue} <- Artifacts.get_issue(project.path, issue_id) do
      render(conn, :show, issue: issue)
    else
      {:error, :not_found} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  def create(conn, %{"project_id" => project_id} = params) do
    with {:ok, uuid} <- cast_uuid(project_id),
         %Projects.Project{} = project <- Projects.get_project(uuid),
         {:ok, issue} <- create_issue(project.path, params) do
      conn
      |> put_status(:created)
      |> render(:create, issue: issue)
    else
      {:error, :not_found} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  def update(conn, %{"project_id" => project_id, "id" => issue_id} = params) do
    with {:ok, uuid} <- cast_uuid(project_id),
         %Projects.Project{} = project <- Projects.get_project(uuid),
         {:ok, issue} <- update_issue(project.path, issue_id, params) do
      render(conn, :update, issue: issue)
    else
      {:error, :not_found} -> {:error, :not_found}
      nil -> {:error, :not_found}
    end
  end

  defp create_issue(project_root, params) do
    attrs =
      Map.take(params, [
        "title",
        "body_md",
        "status",
        "priority",
        "labels",
        "assignee",
        "dependencies",
        "references"
      ])

    case Artifacts.create_issue(project_root, attrs) do
      {:ok, issue} -> {:ok, issue}
      {:error, {:validation, changeset}} -> {:error, changeset}
      other -> other
    end
  end

  defp update_issue(project_root, issue_id, params) do
    attrs =
      Map.take(params, [
        "title",
        "body_md",
        "status",
        "priority",
        "labels",
        "assignee",
        "references"
      ])

    case Artifacts.update_issue(project_root, issue_id, attrs) do
      {:ok, issue} -> {:ok, issue}
      {:error, {:validation, changeset}} -> {:error, changeset}
      other -> other
    end
  end

  defp cast_uuid(id) do
    case Ecto.UUID.cast(id) do
      {:ok, uuid} -> {:ok, uuid}
      :error -> {:error, :not_found}
    end
  end
end
