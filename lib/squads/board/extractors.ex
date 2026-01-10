defmodule Squads.Board.Extractors do
  @moduledoc false

  alias Squads.Sessions.TranscriptEntry

  @spec extract_issue_plan([TranscriptEntry.t()]) :: {:ok, map()} | :error
  def extract_issue_plan(entries) do
    entries
    |> assistant_texts()
    |> Enum.find_value(:error, fn text ->
      case last_json_fence(text) do
        {:ok, %{"issues" => _} = obj} -> {:ok, obj}
        _ -> nil
      end
    end)
  end

  @spec extract_build_result([TranscriptEntry.t()]) :: {:ok, map()} | :error
  def extract_build_result(entries) do
    entries
    |> assistant_texts()
    |> Enum.find_value(:error, fn text ->
      case last_json_fence(text) do
        {:ok, %{"pr_url" => _} = obj} -> {:ok, obj}
        _ -> nil
      end
    end)
  end

  @spec extract_ai_review([TranscriptEntry.t()]) :: {:ok, map()} | :error
  def extract_ai_review(entries) do
    entries
    |> assistant_texts()
    |> Enum.find_value(:error, fn text ->
      case last_json_fence(text) do
        {:ok, %{"recommendation" => _} = obj} -> {:ok, obj}
        _ -> nil
      end
    end)
  end

  defp assistant_texts(entries) do
    entries
    |> Enum.filter(fn
      %TranscriptEntry{role: "assistant"} -> true
      _ -> false
    end)
    |> Enum.map(&text_from_payload(&1.payload))
    |> Enum.reject(&(&1 == ""))
    |> Enum.reverse()
  end

  defp text_from_payload(%{"parts" => parts}) when is_list(parts) do
    parts
    |> Enum.map(fn
      %{"type" => "text", "text" => text} when is_binary(text) -> text
      %{"text" => text} when is_binary(text) -> text
      _ -> nil
    end)
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end

  defp text_from_payload(%{"data" => data}) when is_map(data), do: text_from_payload(data)
  defp text_from_payload(%{"payload" => data}) when is_map(data), do: text_from_payload(data)
  defp text_from_payload(_), do: ""

  defp last_json_fence(text) when is_binary(text) do
    case extract_fenced_blocks(text, "json") do
      [] ->
        case extract_fenced_blocks(text, nil) do
          [] -> :error
          blocks -> decode_last(blocks)
        end

      blocks ->
        decode_last(blocks)
    end
  end

  defp decode_last(blocks) when is_list(blocks) do
    blocks
    |> List.last()
    |> then(fn
      nil ->
        :error

      json ->
        case Jason.decode(json) do
          {:ok, obj} when is_map(obj) -> {:ok, obj}
          _ -> :error
        end
    end)
  end

  defp extract_fenced_blocks(text, language) do
    fence = "```"

    text
    |> String.split(fence)
    |> Enum.with_index()
    |> Enum.filter(fn {_chunk, idx} -> rem(idx, 2) == 1 end)
    |> Enum.flat_map(fn {chunk, _idx} -> normalize_fence(chunk, language) end)
  end

  defp normalize_fence(nil, nil), do: []

  defp normalize_fence(chunk, nil) when is_binary(chunk) do
    # Accept any fenced content; attempt to decode as JSON
    content = chunk |> String.trim()

    # If a language tag is present on first line, strip it.
    case String.split(content, "\n", parts: 2) do
      [first, rest] ->
        if Regex.match?(~r/^[a-zA-Z0-9_-]+$/, first) do
          [String.trim(rest)]
        else
          [content]
        end

      _ ->
        [content]
    end
  end

  defp normalize_fence(chunk, language) when is_binary(language) and is_binary(chunk) do
    content = chunk |> String.trim()

    case String.split(content, "\n", parts: 2) do
      [first, rest] ->
        first_down = String.downcase(first)

        cond do
          first == language -> [String.trim(rest)]
          first_down == language -> [String.trim(rest)]
          true -> []
        end

      _ ->
        []
    end
  end
end
