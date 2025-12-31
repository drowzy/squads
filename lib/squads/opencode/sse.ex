defmodule Squads.OpenCode.SSE do
  @moduledoc """
  Server-Sent Events (SSE) client for OpenCode event streams.

  This module provides functionality to connect to OpenCode's SSE endpoints
  and parse the incoming event stream.

  ## Event Format

  OpenCode SSE events follow the standard SSE format:
  ```
  event: <event_type>
  data: <json_payload>

  ```
  """

  require Logger

  @doc """
  Parses a chunk of SSE data into events.

  Returns a list of parsed events and any remaining incomplete data.

  ## Examples

      iex> Squads.OpenCode.SSE.parse_chunk("event: message\\ndata: {\\"foo\\":1}\\n\\n")
      {[%{event: "message", data: %{"foo" => 1}}], ""}

      iex> Squads.OpenCode.SSE.parse_chunk("event: partial\\ndata: ")
      {[], "event: partial\\ndata: "}
  """
  @spec parse_chunk(String.t(), String.t()) :: {[map()], String.t()}
  def parse_chunk(chunk, buffer \\ "") do
    data = buffer <> chunk

    # Split on double newlines (SSE event delimiter)
    case String.split(data, "\n\n", parts: 2) do
      [complete, rest] ->
        event = parse_event(complete)
        {more_events, remaining} = parse_chunk("", rest)
        {[event | more_events], remaining}

      [incomplete] ->
        # Check if it ends with \n\n (complete event at end)
        if String.ends_with?(incomplete, "\n\n") do
          event = parse_event(String.trim_trailing(incomplete, "\n\n"))
          {[event], ""}
        else
          {[], incomplete}
        end
    end
  end

  @doc """
  Parses a single SSE event block.
  """
  @spec parse_event(String.t()) :: map()
  def parse_event(block) do
    lines = String.split(block, "\n")

    Enum.reduce(lines, %{}, fn line, acc ->
      cond do
        String.starts_with?(line, "event:") ->
          event_type = String.trim_leading(line, "event:") |> String.trim()
          Map.put(acc, :event, event_type)

        String.starts_with?(line, "data:") ->
          data_str = String.trim_leading(line, "data:") |> String.trim()

          data =
            case Jason.decode(data_str) do
              {:ok, decoded} -> decoded
              {:error, _} -> data_str
            end

          Map.put(acc, :data, data)

        String.starts_with?(line, "id:") ->
          id = String.trim_leading(line, "id:") |> String.trim()
          Map.put(acc, :id, id)

        String.starts_with?(line, "retry:") ->
          retry = String.trim_leading(line, "retry:") |> String.trim() |> String.to_integer()
          Map.put(acc, :retry, retry)

        # Comment or empty line
        String.starts_with?(line, ":") or line == "" ->
          acc

        true ->
          # Unknown field, ignore
          acc
      end
    end)
  end

  @doc """
  Creates a Req request configured for SSE streaming.

  Returns a Req request that can be used with `Req.get!/2` and the
  `into: :self` option for async streaming.
  """
  @spec build_request(String.t(), keyword()) :: Req.Request.t()
  def build_request(url, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, :infinity)

    Req.new(
      url: url,
      headers: [
        {"accept", "text/event-stream"},
        {"cache-control", "no-cache"}
      ],
      receive_timeout: timeout,
      connect_options: [timeout: Keyword.get(opts, :connect_timeout, 30_000)]
    )
  end

  @doc """
  Starts an SSE stream connection and returns a stream of events.

  This is a convenience function that handles the connection and
  parsing, yielding parsed events as they arrive.

  Note: This blocks the calling process. For background ingestion,
  use the EventIngester GenServer.
  """
  @spec stream(String.t(), keyword()) :: Enumerable.t()
  def stream(url, opts \\ []) do
    request = build_request(url, opts)

    Stream.resource(
      fn -> start_stream(request) end,
      fn state -> next_events(state) end,
      fn state -> stop_stream(state) end
    )
  end

  defp start_stream(request) do
    case Req.get(request, into: :self) do
      {:ok, response} ->
        %{
          response: response,
          buffer: "",
          status: :connected
        }

      {:error, reason} ->
        %{
          error: reason,
          status: :error
        }
    end
  end

  defp next_events(%{status: :error} = state) do
    {:halt, state}
  end

  defp next_events(%{status: :connected, buffer: buffer} = state) do
    receive do
      {_ref, {:data, chunk}} ->
        {events, new_buffer} = parse_chunk(chunk, buffer)
        {events, %{state | buffer: new_buffer}}

      {_ref, :done} ->
        {:halt, %{state | status: :done}}

      {_ref, {:error, reason}} ->
        Logger.error("SSE stream error: #{inspect(reason)}")
        {:halt, %{state | status: :error, error: reason}}
    after
      60_000 ->
        # Timeout waiting for data, keep connection alive
        {[], state}
    end
  end

  defp next_events(%{status: :done} = state) do
    {:halt, state}
  end

  defp stop_stream(%{response: %{ref: ref}} = _state) when is_reference(ref) do
    # Cancel the async request
    Process.demonitor(ref, [:flush])
    :ok
  end

  defp stop_stream(_state), do: :ok
end
