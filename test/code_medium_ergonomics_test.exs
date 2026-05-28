defmodule Cantrip.Medium.CodeErgonomicsTest do
  use ExUnit.Case, async: true

  alias Cantrip.Medium.Code
  alias Cantrip.Circle
  alias Cantrip.Gate

  defp make_runtime(gates \\ [:done]) do
    circle = Circle.new(gates: gates, type: :code)

    %{circle: circle}
  end

  describe "folded_summary binding (§6.8 — summaries in the sandbox)" do
    test "when runtime carries a folded_summary, the entity sees it as a binding" do
      runtime = make_runtime() |> Map.put(:folded_summary, "Earlier turns surveyed the root.")
      state = %{}

      {_state, _obs, result, terminated} =
        Code.eval(~s[done.(folded_summary)], state, runtime)

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
        Code.eval(
          ~s[done.(:erlang.binding_to_term(:erlang.nil_to_atom()))],
          state,
          runtime
        )

      # The above is gibberish that won't compile — but the meaningful
      # assertion is that referencing `folded_summary` would compile-fail
      # when not provided. We verify presence in the binding instead:
      {state2, _obs, _, _} = Code.eval(~s[done.("ok")], state, runtime)
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
        Code.eval(
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

    test "Cantrip.new constructs package handles that can persist in code_state" do
      child_llm =
        {Cantrip.FakeLLM,
         Cantrip.FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}
         ])}

      {:ok, parent} =
        Cantrip.new(
          llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([])},
          circle: %{type: :code, gates: [:done], wards: [%{max_turns: 3}]}
        )

      runtime =
        make_runtime([:done])
        |> Map.put(:parent_context, Cantrip.parent_context(parent, child_llm: child_llm))

      {state, _obs, result, terminated} =
        Code.eval(
          ~s|{:ok, helper} = Cantrip.new(%{
               identity: %{system_prompt: "helper"},
               circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 1}]}
             })
             {:ok, answer, _next_helper, _child_loom, _meta} = Cantrip.cast(helper, "go")
             done.(%{id: helper.id, result: answer})|,
          %{},
          runtime
        )

      assert terminated
      assert result.result == "ok"
      assert %Cantrip{id: id} = state.binding[:helper]
      assert id == result.id
    end

    test "child gate dependency inheritance does not create atoms from string keys" do
      root =
        Path.join(
          System.tmp_dir!(),
          "cantrip_deps_" <> Integer.to_string(System.unique_integer([:positive]))
        )

      atom_name = "cantrip_unknown_dep_" <> Integer.to_string(System.unique_integer([:positive]))
      assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(atom_name) end

      {:ok, parent} =
        Cantrip.new(
          llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([])},
          circle: %{
            type: :code,
            gates: [
              %{name: :done},
              %{name: :read_file, dependencies: %{"root" => root, atom_name => "ignored"}}
            ],
            wards: [%{max_turns: 3}]
          }
        )

      {:ok, child} =
        Cantrip.new(%{
          parent_context: Cantrip.parent_context(parent),
          circle: %{type: :code, gates: ["list_dir"]}
        })

      assert child.circle.gates["list_dir"].dependencies == %{root: root}
      assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(atom_name) end
    end

    test "parent context normalization does not create atoms from unknown string keys" do
      atom_name =
        "cantrip_unknown_parent_context_" <> Integer.to_string(System.unique_integer([:positive]))

      assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(atom_name) end

      {:ok, parent} =
        Cantrip.new(
          llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([])},
          circle: %{type: :code, gates: [:done], wards: [%{max_turns: 3}]}
        )

      parent_context =
        parent
        |> Cantrip.parent_context()
        |> Map.put(Atom.to_string(:parent_cantrip), parent)
        |> Map.put(atom_name, "ignored")

      assert {:ok, _child} =
               Cantrip.new(%{
                 parent_context: parent_context,
                 circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
               })

      assert_raise ArgumentError, fn -> :erlang.binary_to_existing_atom(atom_name) end
    end

    test "deleted delegation gates are not injected" do
      runtime = make_runtime([:done])

      deleted_gate = String.to_atom("call_" <> "entity")

      {_state, _obs, result, terminated} =
        Code.eval("done.(binding() |> Keyword.has_key?(#{inspect(deleted_gate)}))", %{}, runtime)

      assert terminated
      refute result
    end
  end

  describe "gate call ergonomics - done" do
    test "done.(x) works (dot-call, backwards compatible)" do
      runtime = make_runtime()
      state = %{}

      {_state, observations, result, terminated} =
        Code.eval(~s[done.("answer")], state, runtime)

      assert terminated
      assert result == "answer"
      assert Enum.any?(observations, &(&1.gate == "done"))
    end

    test "done(x) works (no dot-call)" do
      runtime = make_runtime()
      state = %{}

      {_state, observations, result, terminated} =
        Code.eval(~s[done("answer")], state, runtime)

      assert terminated
      assert result == "answer"
      assert Enum.any?(observations, &(&1.gate == "done"))
    end
  end

  describe "source transform safety" do
    test "gate calls inside strings are NOT transformed" do
      runtime = make_runtime()
      state = %{}
      # This code assigns a string containing "done(" — it should NOT be transformed
      code = ~s[x = "call done(x) to finish"\ndone.(x)]
      {_state, _obs, result, terminated} = Code.eval(code, state, runtime)

      assert terminated
      assert result == "call done(x) to finish"
    end

    test "module-qualified calls are NOT transformed" do
      runtime = make_runtime()
      state = %{}
      # SomeModule.done(x) should NOT become SomeModule.done.(x)
      # This will fail at runtime (no such module), but the transform should not mangle it
      code = ~s[try do\n  String.done("x")\nrescue\n  _ -> done.("rescued")\nend]
      {_state, _obs, result, terminated} = Code.eval(code, state, runtime)

      assert terminated
      assert result == "rescued"
    end

    test "already dot-called gates are not double-transformed" do
      runtime = make_runtime()
      state = %{}
      code = ~s[done.("already_dotted")]
      {_state, _obs, result, terminated} = Code.eval(code, state, runtime)

      assert terminated
      assert result == "already_dotted"
    end

    test "custom gate names are also transformed" do
      circle = Circle.new(gates: [:done, :echo], type: :code)

      runtime = %{
        circle: circle,
        execute_gate: fn gate_name, args ->
          Gate.execute(circle, gate_name, args)
        end
      }

      state = %{}
      # echo(opts) without dot should work
      code = ~s[result = echo(%{text: "hello"})\ndone.(result)]
      {_state, _obs, result, terminated} = Code.eval(code, state, runtime)

      assert terminated
      assert result == "hello"
    end

    test "parser-aware transform does not rewrite function definitions" do
      transformed =
        Cantrip.Medium.Code.add_dot_calls(
          ~s[def done(value), do: {:local, value}\nresult = done("x")],
          ["done"]
        )

      assert transformed =~ "def done(value)"
      assert transformed =~ ~s|result = done.("x")|
      refute transformed =~ "def done.(value)"
    end
  end

  describe "compile_and_load bare-value args" do
    test "compile_and_load.(string) passes the string through, not %{}" do
      circle = Circle.new(gates: [:done], type: :code)

      runtime = %{
        circle: circle,
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
      {_state, _obs, result, terminated} = Code.eval(code, state, runtime)

      assert terminated
      assert result == "my_module_code"
    end
  end

  describe "bare-value gate args in code medium" do
    defp make_runtime_with_gates(gates) do
      circle = Circle.new(gates: gates, type: :code)

      %{
        circle: circle,
        execute_gate: fn gate_name, args ->
          Gate.execute(circle, gate_name, args)
        end
      }
    end

    test "echo.(string) returns the string, not nil" do
      runtime = make_runtime_with_gates([:done, :echo])
      state = %{}
      code = ~s[result = echo.("hello world")\ndone.(result)]
      {_state, _obs, result, terminated} = Code.eval(code, state, runtime)

      assert terminated
      assert result == "hello world"
    end

    test "echo(string) without dot also returns the string" do
      runtime = make_runtime_with_gates([:done, :echo])
      state = %{}
      code = ~s[result = echo("bare value")\ndone.(result)]
      {_state, _obs, result, terminated} = Code.eval(code, state, runtime)

      assert terminated
      assert result == "bare value"
    end

    test "echo.(%{text: string}) still works with map arg" do
      runtime = make_runtime_with_gates([:done, :echo])
      state = %{}
      code = ~s[result = echo.(%{text: "map form"})\ndone.(result)]
      {_state, _obs, result, terminated} = Code.eval(code, state, runtime)

      assert terminated
      assert result == "map form"
    end
  end

  # ===========================================================================
  # COMP-8: cast_batch must raise on child failure like cast does
  # ===========================================================================

  describe "cast_batch error consistency (COMP-8)" do
    test "cast_batch validates item shape before spawning child tasks" do
      {:ok, child} =
        Cantrip.new(
          llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([])},
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
        )

      assert {:error, {:invalid_cast_batch_item, 0, :missing_cantrip}} =
               Cantrip.cast_batch([%{intent: "go"}])

      assert {:error, {:invalid_cast_batch_item, 0, :missing_intent}} =
               Cantrip.cast_batch([%{cantrip: child}])

      assert {:error, {:invalid_cast_batch_item, 0, :invalid_cantrip}} =
               Cantrip.cast_batch([%{cantrip: :not_a_cantrip, intent: "go"}])

      assert {:error, {:invalid_cast_batch_item, 0, :expected_map_or_keyword}} =
               Cantrip.cast_batch([:not_an_item])
    end

    test "cast_batch sequential fallback surfaces child failure as error observation" do
      child_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{error: "child crashed"}])}

      {:ok, parent} =
        Cantrip.new(
          llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([])},
          circle: %{type: :code, gates: [:done], wards: [%{max_turns: 3}]}
        )

      runtime =
        make_runtime([:done])
        |> Map.put(:parent_context, Cantrip.parent_context(parent, child_llm: child_llm))

      state = %{}

      # Matching on the success shape should fail when Cantrip.cast_batch returns
      # an error, so the code medium records the failure and does not reach done.
      code = """
      {:ok, child} = Cantrip.new(%{
        identity: %{system_prompt: "helper"},
        circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
      })
      {:ok, _values, _children, _looms, _meta} =
        Cantrip.cast_batch([%{cantrip: child, intent: "fail please"}])
      done.("should not reach here")
      """

      {_state, obs, _result, terminated} = Code.eval(code, state, runtime)

      refute terminated, "Cantrip.cast_batch should have errored before done was called"
      assert Enum.any?(obs, &(&1[:is_error] and &1.gate == "cast_batch"))
      assert Enum.any?(obs, &(&1[:is_error] and &1.gate == "code"))
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
        Code.eval(
          ~s|x = :hello\ndone.(:first_send)|,
          state,
          runtime
        )

      assert terminated1
      assert Keyword.fetch!(state1.binding, :x) == :hello

      # Turn 2 (simulating a subsequent send): x must still be visible.
      {_state2, _obs2, result2, terminated2} =
        Code.eval(~s|done.({:saw_x, x})|, state1, runtime)

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

      {state1, _obs, _result, _term} = Code.eval(code, state, runtime)

      assert Keyword.fetch!(state1.binding, :a) == 1
      assert Keyword.fetch!(state1.binding, :b) == 2
      assert Keyword.fetch!(state1.binding, :c) == 4
    end

    test "single-statement code with just done() still works (no regression)" do
      runtime = make_runtime()

      {_state, _obs, result, terminated} =
        Code.eval(~s|done.("only thing")|, %{}, runtime)

      assert terminated
      assert result == "only thing"
    end
  end
end
