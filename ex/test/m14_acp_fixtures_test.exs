defmodule CantripM14AcpFixturesTest do
  use ExUnit.Case, async: true

  alias Cantrip.ACP.Protocol
  alias Cantrip.ACP.Server

  @fixtures_dir Path.expand("fixtures/acp/prompts", __DIR__)

  defmodule StubRuntime do
    def new_session(%{"cwd" => cwd}), do: {:ok, %{cwd: cwd, calls: []}}

    def prompt(session, text),
      do: {:ok, "echo:" <> text, %{session | calls: [text | session.calls]}}
  end

  test "fixture prompt payloads remain ACP-compatible" do
    fixture_paths = @fixtures_dir |> Path.join("*.json") |> Path.wildcard() |> Enum.sort()
    assert fixture_paths != []

    Enum.each(fixture_paths, fn path ->
      fixture = path |> File.read!() |> Jason.decode!()
      run_fixture(fixture)
    end)
  end

  defp run_fixture(%{"name" => name, "params_fragment" => fragment, "expect" => expectation}) do
    state = Protocol.new(runtime: StubRuntime)

    {state, init_responses} =
      send_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 1,
        "method" => "initialize",
        "params" => %{"protocolVersion" => 1}
      })

    assert [%{"result" => %{"protocolVersion" => 1}}] = init_responses, "fixture=#{name}"

    {state, new_responses} =
      send_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 2,
        "method" => "session/new",
        "params" => %{"cwd" => "/tmp"}
      })

    assert [%{"result" => %{"sessionId" => session_id}}] = new_responses, "fixture=#{name}"

    prompt_params =
      fragment
      |> Map.put_new("sessionId", session_id)

    {_state, prompt_responses} =
      send_request(state, %{
        "jsonrpc" => "2.0",
        "id" => 3,
        "method" => "session/prompt",
        "params" => prompt_params
      })

    case expectation do
      "ok" ->
        assert length(prompt_responses) == 3, "fixture=#{name}"
        [u1, u2, done] = prompt_responses
        assert u1["method"] == "session/update", "fixture=#{name}"
        assert u2["method"] == "session/update", "fixture=#{name}"
        assert done["id"] == 3, "fixture=#{name}"
        assert get_in(done, ["result", "stopReason"]) == "end_turn", "fixture=#{name}"

      "bad_prompt" ->
        assert [%{"id" => 3, "error" => %{"code" => -32602}}] = prompt_responses,
               "fixture=#{name}"

      other ->
        flunk("unknown fixture expectation: #{inspect(other)} (fixture=#{name})")
    end
  end

  defp send_request(state, request) do
    line = Jason.encode!(request) <> "\n"
    Server.handle_line(state, line)
  end
end
