defmodule Cantrip.ReadmeExamplesTest do
  # Pins the API shapes used by README.md and docs/public-api.md so future
  # drift between the example surface and the runtime fails CI. If a public
  # example in README/public-api.md is changed, mirror it here; if a runtime
  # constructor signature changes, the failure here is the signal that docs
  # need updating.
  use ExUnit.Case, async: false

  alias Cantrip.FakeLLM

  defp fake_llm(responses), do: {FakeLLM, FakeLLM.new(responses)}

  test "README/public-api quickstart: conversation cantrip with done gate" do
    llm = fake_llm([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        identity: %{system_prompt: "Call done with the final answer."},
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 8}]}
      )

    {:ok, result, _next_cantrip, loom, _meta} = Cantrip.cast(cantrip, "go")

    assert result == "ok"
    assert length(loom.turns) == 1
  end

  test "README persistent-entity example: summon + send across intents" do
    llm =
      fake_llm([
        %{tool_calls: [%{gate: "done", args: %{answer: "first"}}]},
        %{tool_calls: [%{gate: "done", args: %{answer: "second"}}]}
      ])

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
      )

    {:ok, pid} = Cantrip.summon(cantrip)
    {:ok, first, _next, _loom, _meta} = Cantrip.send(pid, "first intent")
    {:ok, second, _next, _loom, _meta} = Cantrip.send(pid, "second intent")

    assert first == "first"
    assert second == "second"
  end

  test "README fan-out example: cast_batch returns results in request order" do
    {:ok, jsonl_reader} =
      Cantrip.new(
        llm: fake_llm([%{tool_calls: [%{gate: "done", args: %{answer: "jsonl summary"}}]}]),
        identity: %{system_prompt: "Summarize the JSONL storage implementation."},
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
      )

    {:ok, mnesia_reader} =
      Cantrip.new(
        llm: fake_llm([%{tool_calls: [%{gate: "done", args: %{answer: "mnesia summary"}}]}]),
        identity: %{system_prompt: "Summarize the Mnesia storage implementation."},
        circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 5}]}
      )

    {:ok, results, _children, _looms, _meta} =
      Cantrip.cast_batch([
        %{cantrip: jsonl_reader, intent: "Focus on lib/cantrip/loom/storage/jsonl.ex"},
        %{cantrip: mnesia_reader, intent: "Focus on lib/cantrip/loom/storage/mnesia.ex"}
      ])

    assert results == ["jsonl summary", "mnesia summary"]
  end

  test "README medium shapes: conversation, code, bash all accepted" do
    llm = fake_llm([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])

    for medium <- [:conversation, :code, :bash] do
      circle =
        case medium do
          :bash ->
            %{
              type: medium,
              gates: [:done],
              wards: [%{max_turns: 3}],
              medium_opts: %{sandbox: :passthrough}
            }

          _ ->
            %{type: medium, gates: [:done], wards: [%{max_turns: 3}]}
        end

      assert {:ok, _cantrip} =
               Cantrip.new(
                 llm: llm,
                 circle: circle
               )
    end
  end

  @tag :mnesia
  test "README loom_storage shapes: :memory, :jsonl, :mnesia all accepted" do
    llm = fake_llm([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])
    base = [llm: llm, circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 3}]}]

    jsonl_path =
      Path.join(
        System.tmp_dir!(),
        "cantrip_readme_loom_#{System.unique_integer([:positive])}.jsonl"
      )

    table = :"cantrip_readme_loom_#{System.unique_integer([:positive])}"

    on_exit(fn -> File.rm(jsonl_path) end)

    for storage <- [:memory, {:jsonl, jsonl_path}, {:mnesia, table: table}] do
      assert {:ok, _cantrip} = Cantrip.new(Keyword.put(base, :loom_storage, storage))
    end
  end
end
