defmodule SquadsWeb.API.ReviewJSON do
  @moduledoc false

  def index(%{reviews: reviews}) when is_list(reviews) do
    %{data: reviews}
  end

  def show(%{review: review}) when is_map(review) do
    %{data: review}
  end
end
