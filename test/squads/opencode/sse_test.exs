defmodule Squads.OpenCode.SSETest do
  use ExUnit.Case, async: true

  alias Squads.OpenCode.SSE

  describe "parse_chunk/2" do
    test "parses a complete event" do
      chunk = "event: message\ndata: {\"foo\":1}\n\n"

      {events, buffer} = SSE.parse_chunk(chunk)

      assert length(events) == 1
      assert hd(events) == %{event: "message", data: %{"foo" => 1}}
      assert buffer == ""
    end

    test "parses multiple events in one chunk" do
      chunk = """
      event: first
      data: {"id":1}

      event: second
      data: {"id":2}

      """

      {events, buffer} = SSE.parse_chunk(chunk)

      assert length(events) == 2
      assert Enum.at(events, 0).event == "first"
      assert Enum.at(events, 0).data["id"] == 1
      assert Enum.at(events, 1).event == "second"
      assert Enum.at(events, 1).data["id"] == 2
      assert buffer == ""
    end

    test "handles incomplete event and returns buffer" do
      chunk = "event: partial\ndata: "

      {events, buffer} = SSE.parse_chunk(chunk)

      assert events == []
      assert buffer == "event: partial\ndata: "
    end

    test "combines buffer with new chunk" do
      buffer = "event: test\ndata: "
      chunk = "{\"complete\":true}\n\n"

      {events, new_buffer} = SSE.parse_chunk(chunk, buffer)

      assert length(events) == 1
      assert hd(events) == %{event: "test", data: %{"complete" => true}}
      assert new_buffer == ""
    end

    test "handles event without data" do
      chunk = "event: ping\n\n"

      {events, buffer} = SSE.parse_chunk(chunk)

      assert length(events) == 1
      assert hd(events) == %{event: "ping"}
      assert buffer == ""
    end

    test "handles data without event type" do
      chunk = "data: {\"message\":\"hello\"}\n\n"

      {events, buffer} = SSE.parse_chunk(chunk)

      assert length(events) == 1
      assert hd(events) == %{data: %{"message" => "hello"}}
      assert buffer == ""
    end

    test "handles empty chunk with buffer" do
      {events, buffer} = SSE.parse_chunk("", "pending data")
      assert events == []
      assert buffer == "pending data"
    end

    test "handles completely empty input" do
      {events, buffer} = SSE.parse_chunk("")
      assert events == []
      assert buffer == ""
    end
  end

  describe "parse_event/1" do
    test "parses event with all standard fields" do
      block = """
      event: message
      id: 123
      data: {"text":"hello"}
      retry: 5000
      """

      event = SSE.parse_event(block)

      assert event.event == "message"
      assert event.id == "123"
      assert event.data == %{"text" => "hello"}
      assert event.retry == 5000
    end

    test "handles non-JSON data as string" do
      block = """
      event: ping
      data: keep-alive
      """

      event = SSE.parse_event(block)

      assert event.event == "ping"
      assert event.data == "keep-alive"
    end

    test "ignores comment lines" do
      block = """
      : this is a comment
      event: test
      : another comment
      data: {"value":42}
      """

      event = SSE.parse_event(block)

      assert event.event == "test"
      assert event.data == %{"value" => 42}
    end

    test "handles empty lines" do
      block = "event: test\n\ndata: {}\n"

      event = SSE.parse_event(block)

      assert event.event == "test"
      assert event.data == %{}
    end

    test "trims whitespace from values" do
      block = "event:  spaced  \ndata:   {\"k\":1}   \n"

      event = SSE.parse_event(block)

      assert event.event == "spaced"
      assert event.data == %{"k" => 1}
    end

    test "ignores unknown fields" do
      block = """
      event: test
      custom: ignored
      data: {"foo":"bar"}
      """

      event = SSE.parse_event(block)

      assert event.event == "test"
      assert event.data == %{"foo" => "bar"}
      refute Map.has_key?(event, :custom)
    end
  end

  describe "build_request/2" do
    test "creates request with SSE headers" do
      request = SSE.build_request("http://localhost:4096/event")

      assert request.url == URI.parse("http://localhost:4096/event")

      headers = Enum.into(request.headers, %{})
      assert headers["accept"] == ["text/event-stream"]
      assert headers["cache-control"] == ["no-cache"]
    end

    test "accepts custom timeout" do
      request = SSE.build_request("http://localhost:4096/event", timeout: 60_000)

      assert request.options.receive_timeout == 60_000
    end

    test "accepts custom connect timeout" do
      request = SSE.build_request("http://localhost:4096/event", connect_timeout: 10_000)

      connect_opts = request.options.connect_options
      assert connect_opts[:timeout] == 10_000
    end

    test "defaults to infinite receive timeout" do
      request = SSE.build_request("http://localhost:4096/event")

      assert request.options.receive_timeout == :infinity
    end
  end

  describe "stream/2" do
    # Note: These tests would require mocking or a real server
    # For unit tests, we focus on the parsing logic above
    # Integration tests can verify the full stream behavior

    test "returns an enumerable" do
      # Just verify the function returns a stream structure
      # Actual streaming would need a mock server
      stream = SSE.stream("http://localhost:4096/event")
      assert is_function(stream, 2)
    end
  end
end
