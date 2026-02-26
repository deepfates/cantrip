defmodule CantripM15AcpTranscriptsTest do
  use ExUnit.Case, async: true

  alias Cantrip.ACP.Protocol
  alias Cantrip.ACP.Server

  @fixtures_dir Path.expand("fixtures/acp/transcripts", __DIR__)

  defmodule StubRuntime do
    def new_session(%{"cwd" => cwd}), do: {:ok, %{cwd: cwd, calls: []}}

    def prompt(session, text),
      do: {:ok, "echo:" <> text, %{session | calls: [text | session.calls]}}
  end

  test "transcript fixtures remain ACP-compatible across full request sequences" do
    fixture_paths = @fixtures_dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()
    assert fixture_paths != []

    Enum.each(fixture_paths, fn path ->
      fixture = path |> File.read!() |> Jason.decode!()
      run_fixture(fixture)
    end)
  end

  defp run_fixture(%{"name" => name, "steps" => steps}) when is_list(steps) do
    initial = %{protocol: Protocol.new(runtime: StubRuntime), session_id: nil}

    Enum.reduce(steps, initial, fn step, acc ->
      {next_acc, responses} = run_step(acc, step)
      assert_step_expectation(responses, step["expect"] || %{}, name, acc.session_id)
      maybe_capture_session(next_acc, responses, step["expect"] || %{}, name)
    end)
  end

  defp run_step(state, %{"raw_line" => raw_line}) when is_binary(raw_line) do
    {next_protocol, responses} = Server.handle_line(state.protocol, raw_line)
    {%{state | protocol: next_protocol}, responses}
  end

  defp run_step(state, %{"request" => request}) when is_map(request) do
    request = substitute_session_id(request, state.session_id)
    line = Jason.encode!(request) <> "\n"
    {next_protocol, responses} = Server.handle_line(state.protocol, line)
    {%{state | protocol: next_protocol}, responses}
  end

  defp assert_step_expectation(responses, expect, fixture_name, known_session_id) do
    if count = expect["response_count"] do
      assert length(responses) == count, "fixture=#{fixture_name}"
    end

    if code = expect["first_error_code"] do
      assert get_in(List.first(responses), ["error", "code"]) == code, "fixture=#{fixture_name}"
    end

    if version = expect["result_protocol_version"] do
      assert get_in(List.first(responses), ["result", "protocolVersion"]) == version,
             "fixture=#{fixture_name}"
    end

    if text = expect["first_update_text"] do
      assert get_in(List.first(responses), ["params", "update", "content", "text"]) == text,
             "fixture=#{fixture_name}"
    end

    if reason = expect["last_stop_reason"] do
      assert get_in(List.last(responses), ["result", "stopReason"]) == reason,
             "fixture=#{fixture_name}"
    end

    if expected_responses = expect["responses"] do
      session_id = known_session_id || capture_session_id(responses)

      expected_responses =
        substitute_session_id(expected_responses, session_id)

      assert responses == expected_responses, "fixture=#{fixture_name}"
    end
  end

  defp maybe_capture_session(state, responses, expect, fixture_name) do
    if expect["capture_session_id"] do
      session_id = capture_session_id(responses)
      assert is_binary(session_id), "fixture=#{fixture_name}"
      %{state | session_id: session_id}
    else
      state
    end
  end

  defp capture_session_id(responses) do
    get_in(List.first(responses), ["result", "sessionId"])
  end

  defp substitute_session_id(term, nil), do: term
  defp substitute_session_id("$SESSION_ID", session_id), do: session_id

  defp substitute_session_id(term, session_id) when is_list(term) do
    Enum.map(term, &substitute_session_id(&1, session_id))
  end

  defp substitute_session_id(term, session_id) when is_map(term) do
    Map.new(term, fn {k, v} -> {k, substitute_session_id(v, session_id)} end)
  end

  defp substitute_session_id(term, _session_id), do: term
end
