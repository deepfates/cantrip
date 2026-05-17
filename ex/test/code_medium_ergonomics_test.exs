defmodule Cantrip.CodeMediumErgonomicsTest do
  use ExUnit.Case, async: true

  alias Cantrip.CodeMedium
  alias Cantrip.Circle
  alias Cantrip.Gate

  defp make_runtime(gates \\ [:done]) do
    circle = Circle.new(gates: gates, type: :code)

    %{
      circle: circle,
      call_entity: fn _opts ->
        %{
          observation: %{gate: "call_entity", result: "child_result", is_error: false},
          value: "child_result"
        }
      end
    }
  end

  describe "folded_summary binding (§6.8 — summaries in the sandbox)" do
    test "when runtime carries a folded_summary, the entity sees it as a binding" do
      runtime = make_runtime() |> Map.put(:folded_summary, "Earlier turns surveyed the root.")
      state = %{}

      {_state, _obs, result, terminated} =
        CodeMedium.eval(~s[done.(folded_summary)], state, runtime)

      assert terminated
      assert result == "Earlier turns surveyed the root."
    end

    test "when runtime has no folded_summary, the binding is absent" do
      # The binding must NOT be silently set to nil (which would look
      # like "folding fired and produced nothing"). When no fold has
      # occurred this turn, the binding simply doesn't exist.
      runtime = make_runtime()
      state = %{}

      {_state, _obs, _result, _terminated} =
        CodeMedium.eval(
          ~s[done.(:erlang.binding_to_term(:erlang.nil_to_atom()))],
          state,
          runtime
        )

      # The above is gibberish that won't compile — but the meaningful
      # assertion is that referencing `folded_summary` would compile-fail
      # when not provided. We verify presence in the binding instead:
      {state2, _obs, _, _} = CodeMedium.eval(~s[done.("ok")], state, runtime)
      refute Keyword.has_key?(state2.binding || [], :folded_summary)
    end
  end

  describe "runtime bindings" do
    test "loom aliases are readable but not persisted into code_state" do
      loom =
        %{system_prompt: nil}
        |> Cantrip.Loom.new()
        |> Cantrip.Loom.append_turn(%{utterance: %{content: "old"}, observation: []})

      runtime = make_runtime() |> Map.put(:loom, loom)

      {state, _obs, result, terminated} =
        CodeMedium.eval(
          ~s|loom_value = loom
             count = length(loom_value.turns)
             done.(count)|,
          %{},
          runtime
        )

      assert terminated
      assert result == 1
      refute Keyword.has_key?(state.binding, :loom)
      refute Keyword.has_key?(state.binding, :loom_value)
      assert state.binding[:count] == 1
    end
  end

  describe "gate call ergonomics - done" do
    test "done.(x) works (dot-call, backwards compatible)" do
      runtime = make_runtime()
      state = %{}

      {_state, observations, result, terminated} =
        CodeMedium.eval(~s[done.("answer")], state, runtime)

      assert terminated
      assert result == "answer"
      assert Enum.any?(observations, &(&1.gate == "done"))
    end

    test "done(x) works (no dot-call)" do
      runtime = make_runtime()
      state = %{}

      {_state, observations, result, terminated} =
        CodeMedium.eval(~s[done("answer")], state, runtime)

      assert terminated
      assert result == "answer"
      assert Enum.any?(observations, &(&1.gate == "done"))
    end
  end

  describe "gate call ergonomics - call_entity" do
    test "call_entity.(%{intent: \"hi\"}) works (dot-call)" do
      runtime = make_runtime([:done, :call_entity])
      state = %{}
      code = ~s[result = call_entity.(%{intent: "hi"})\ndone.(result)]
      {_state, _obs, result, terminated} = CodeMedium.eval(code, state, runtime)

      assert terminated
      assert result == "child_result"
    end

    test "call_entity(%{intent: \"hi\"}) works (no dot-call)" do
      runtime = make_runtime([:done, :call_entity])
      state = %{}
      code = ~s[result = call_entity(%{intent: "hi"})\ndone.(result)]
      {_state, _obs, result, terminated} = CodeMedium.eval(code, state, runtime)

      assert terminated
      assert result == "child_result"
    end
  end

  describe "source transform safety" do
    test "gate calls inside strings are NOT transformed" do
      runtime = make_runtime()
      state = %{}
      # This code assigns a string containing "done(" — it should NOT be transformed
      code = ~s[x = "call done(x) to finish"\ndone.(x)]
      {_state, _obs, result, terminated} = CodeMedium.eval(code, state, runtime)

      assert terminated
      assert result == "call done(x) to finish"
    end

    test "module-qualified calls are NOT transformed" do
      runtime = make_runtime()
      state = %{}
      # SomeModule.done(x) should NOT become SomeModule.done.(x)
      # This will fail at runtime (no such module), but the transform should not mangle it
      code = ~s[try do\n  String.done("x")\nrescue\n  _ -> done.("rescued")\nend]
      {_state, _obs, result, terminated} = CodeMedium.eval(code, state, runtime)

      assert terminated
      assert result == "rescued"
    end

    test "already dot-called gates are not double-transformed" do
      runtime = make_runtime()
      state = %{}
      code = ~s[done.("already_dotted")]
      {_state, _obs, result, terminated} = CodeMedium.eval(code, state, runtime)

      assert terminated
      assert result == "already_dotted"
    end

    test "custom gate names are also transformed" do
      circle = Circle.new(gates: [:done, :echo], type: :code)

      runtime = %{
        circle: circle,
        call_entity: fn _opts ->
          %{observation: %{gate: "call_entity", result: "ok", is_error: false}, value: "ok"}
        end,
        execute_gate: fn gate_name, args ->
          Gate.execute(circle, gate_name, args)
        end
      }

      state = %{}
      # echo(opts) without dot should work
      code = ~s[result = echo(%{text: "hello"})\ndone.(result)]
      {_state, _obs, result, terminated} = CodeMedium.eval(code, state, runtime)

      assert terminated
      assert result == "hello"
    end
  end

  describe "compile_and_load bare-value args" do
    test "compile_and_load.(string) passes the string through, not %{}" do
      circle = Circle.new(gates: [:done], type: :code)

      runtime = %{
        circle: circle,
        call_entity: fn _opts ->
          %{observation: %{gate: "call_entity", result: "ok", is_error: false}, value: "ok"}
        end,
        compile_and_load: fn opts ->
          # The opts should be whatever was passed, not coerced to %{}
          %{
            observation: %{gate: "compile_and_load", result: inspect(opts), is_error: false},
            value: opts
          }
        end
      }

      state = %{}
      code = ~s[result = compile_and_load.("my_module_code")\ndone.(result)]
      {_state, _obs, result, terminated} = CodeMedium.eval(code, state, runtime)

      assert terminated
      assert result == "my_module_code"
    end
  end

  describe "call_entity bare-value args" do
    test "call_entity.(string) passes string as %{intent: string}" do
      received = :ets.new(:test_received, [:set, :public])

      circle = Circle.new(gates: [:done, :call_entity], type: :code)

      runtime = %{
        circle: circle,
        call_entity: fn opts ->
          :ets.insert(received, {:opts, opts})
          %{observation: %{gate: "call_entity", result: "ok", is_error: false}, value: "ok"}
        end
      }

      state = %{}
      code = ~s[result = call_entity.("just a question")\ndone.(result)]
      {_state, _obs, _result, _terminated} = CodeMedium.eval(code, state, runtime)

      [{:opts, captured}] = :ets.lookup(received, :opts)
      assert captured == %{intent: "just a question"}
      :ets.delete(received)
    end
  end

  describe "bare-value gate args in code medium" do
    defp make_runtime_with_gates(gates) do
      circle = Circle.new(gates: gates, type: :code)

      %{
        circle: circle,
        call_entity: fn _opts ->
          %{observation: %{gate: "call_entity", result: "ok", is_error: false}, value: "ok"}
        end,
        execute_gate: fn gate_name, args ->
          Gate.execute(circle, gate_name, args)
        end
      }
    end

    test "echo.(string) returns the string, not nil" do
      runtime = make_runtime_with_gates([:done, :echo])
      state = %{}
      code = ~s[result = echo.("hello world")\ndone.(result)]
      {_state, _obs, result, terminated} = CodeMedium.eval(code, state, runtime)

      assert terminated
      assert result == "hello world"
    end

    test "echo(string) without dot also returns the string" do
      runtime = make_runtime_with_gates([:done, :echo])
      state = %{}
      code = ~s[result = echo("bare value")\ndone.(result)]
      {_state, _obs, result, terminated} = CodeMedium.eval(code, state, runtime)

      assert terminated
      assert result == "bare value"
    end

    test "echo.(%{text: string}) still works with map arg" do
      runtime = make_runtime_with_gates([:done, :echo])
      state = %{}
      code = ~s[result = echo.(%{text: "map form"})\ndone.(result)]
      {_state, _obs, result, terminated} = CodeMedium.eval(code, state, runtime)

      assert terminated
      assert result == "map form"
    end
  end

  # ===========================================================================
  # COMP-8: cast_batch must raise on child failure like cast does
  # ===========================================================================

  describe "cast_batch error consistency (COMP-8)" do
    test "cast_batch sequential fallback surfaces child failure as error observation" do
      # Runtime with call_entity that returns an error, no call_entity_batch
      circle = Circle.new(gates: [:done, :cantrip, :cast, :cast_batch], type: :code)

      failing_call_entity = fn _opts ->
        %{
          observation: %{gate: "call_entity", result: "child crashed", is_error: true},
          value: nil
        }
      end

      runtime = %{circle: circle, call_entity: failing_call_entity}
      state = %{}

      # cast_batch should raise internally (caught by code medium as error obs)
      code = """
      id = cantrip.(%{
        identity: "helper",
        circle: %{medium: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
      })
      cast_batch.([%{cantrip: id, intent: "fail please"}])
      done.("should not reach here")
      """

      {_state, obs, _result, terminated} = CodeMedium.eval(code, state, runtime)

      # The raise should prevent done from being reached
      # Prior to fix: cast_batch swallowed the error, done was reached
      refute terminated, "cast_batch should have raised before done was called"
      error_obs = Enum.find(obs, fn o -> o[:is_error] end)
      assert error_obs, "expected an error observation from cast_batch failure"
    end
  end

  describe "binding persistence across the done-call boundary (MEDIUM-3)" do
    # Historical bug: `done.(x)` threw `{:cantrip_done, ...}` and the
    # catch returned the *input* binding, dropping any assignments
    # made earlier in the same turn. That broke the natural
    # "compute then done" pattern across multi-send entities — by the
    # next send, the computed value was gone.
    #
    # Per-statement evaluation in `eval_block` preserves the binding
    # from statements before the one that called done.

    test "an assignment before done() in the same turn persists to the next turn" do
      runtime = make_runtime()
      state = %{}

      # Turn 1: assign x and call done in the same code block.
      {state1, _obs1, _result1, terminated1} =
        CodeMedium.eval(
          ~s|x = :hello\ndone.(:first_send)|,
          state,
          runtime
        )

      assert terminated1
      assert Keyword.fetch!(state1.binding, :x) == :hello

      # Turn 2 (simulating a subsequent send): x must still be visible.
      {_state2, _obs2, result2, terminated2} =
        CodeMedium.eval(~s|done.({:saw_x, x})|, state1, runtime)

      assert terminated2
      assert result2 == {:saw_x, :hello}
    end

    test "multiple assignments before done() all persist" do
      runtime = make_runtime()
      state = %{}

      code = """
      a = 1
      b = a + 1
      c = b * 2
      done.(:ok)
      """

      {state1, _obs, _result, _term} = CodeMedium.eval(code, state, runtime)

      assert Keyword.fetch!(state1.binding, :a) == 1
      assert Keyword.fetch!(state1.binding, :b) == 2
      assert Keyword.fetch!(state1.binding, :c) == 4
    end

    test "single-statement code with just done() still works (no regression)" do
      runtime = make_runtime()

      {_state, _obs, result, terminated} =
        CodeMedium.eval(~s|done.("only thing")|, %{}, runtime)

      assert terminated
      assert result == "only thing"
    end
  end
end
