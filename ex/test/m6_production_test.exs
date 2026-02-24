defmodule CantripM6ProductionTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeCrystal

  test "PROD-2 retried invocation appears as single turn" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{error: %{status: 429, message: "rate limited"}},
         %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{gates: [:done], wards: [%{max_turns: 10}]},
        retry: %{max_retries: 3, retryable_status_codes: [429]}
      )

    assert {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "retry")
    assert length(loom.turns) == 1
  end

  test "PROD-3 cumulative token tracking" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new([
         %{
           tool_calls: [%{gate: "echo", args: %{text: "1"}}],
           usage: %{prompt_tokens: 100, completion_tokens: 50}
         },
         %{
           tool_calls: [%{gate: "done", args: %{answer: "ok"}}],
           usage: %{prompt_tokens: 200, completion_tokens: 30}
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]}
      )

    assert {:ok, "ok", _cantrip, _loom, meta} = Cantrip.cast(cantrip, "usage")

    assert meta.cumulative_usage == %{
             prompt_tokens: 300,
             completion_tokens: 80,
             total_tokens: 380
           }
  end

  test "PROD-4 folding triggers automatically and preserves loom" do
    crystal =
      {FakeCrystal,
       FakeCrystal.new(
         [
           %{tool_calls: [%{gate: "echo", args: %{text: "1"}}]},
           %{tool_calls: [%{gate: "echo", args: %{text: "2"}}]},
           %{tool_calls: [%{gate: "echo", args: %{text: "3"}}]},
           %{tool_calls: [%{gate: "echo", args: %{text: "4"}}]},
           %{tool_calls: [%{gate: "echo", args: %{text: "5"}}]},
           %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
         ],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{gates: [:done, :echo], wards: [%{max_turns: 10}]},
        folding: %{trigger_after_turns: 3}
      )

    assert {:ok, "ok", cantrip, loom, _meta} = Cantrip.cast(cantrip, "fold")
    assert length(loom.turns) == 6

    invocations = FakeCrystal.invocations(cantrip.crystal_state)
    [_, _, _, fourth, fifth | _] = invocations
    assert length(fifth.messages) <= length(fourth.messages)
  end

  test "PROD-5 ephemeral gate results are redacted from context but kept in loom" do
    payload = "very large content here..."

    crystal =
      {FakeCrystal,
       FakeCrystal.new(
         [
           %{tool_calls: [%{gate: "read_ephemeral", args: %{path: "big.txt"}}]},
           %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
         ],
         record_inputs: true
       )}

    {:ok, cantrip} =
      Cantrip.new(
        crystal: crystal,
        circle: %{
          gates: [
            %{name: :done},
            %{name: :read_ephemeral, ephemeral: true, result: payload}
          ],
          wards: [%{max_turns: 10}]
        }
      )

    assert {:ok, "ok", cantrip, loom, _meta} = Cantrip.cast(cantrip, "ephemeral")

    [_first, second] = FakeCrystal.invocations(cantrip.crystal_state)
    refute Enum.any?(second.messages, &String.contains?(to_string(&1.content), payload))

    [turn1 | _] = loom.turns
    assert hd(turn1.observation).result == payload
  end
end
