defmodule Cantrip.CodeMediumErgonomicsTest do
  use ExUnit.Case, async: true

  alias Cantrip.CodeMedium
  alias Cantrip.Circle

  defp make_runtime(gates \\ [:done]) do
    circle = Circle.new(gates: gates, type: :code)

    %{
      circle: circle,
      call_entity: fn _opts ->
        %{observation: %{gate: "call_entity", result: "child_result", is_error: false}, value: "child_result"}
      end
    }
  end

  describe "gate call ergonomics - done" do
    test "done.(x) works (dot-call, backwards compatible)" do
      runtime = make_runtime()
      state = %{}
      {_state, observations, result, terminated} = CodeMedium.eval(~s[done.("answer")], state, runtime)

      assert terminated
      assert result == "answer"
      assert Enum.any?(observations, &(&1.gate == "done"))
    end

    test "done(x) works (no dot-call)" do
      runtime = make_runtime()
      state = %{}
      {_state, observations, result, terminated} = CodeMedium.eval(~s[done("answer")], state, runtime)

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
          Circle.execute_gate(circle, gate_name, args)
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

  describe "bare-value gate args in code medium" do
    defp make_runtime_with_gates(gates) do
      circle = Circle.new(gates: gates, type: :code)

      %{
        circle: circle,
        call_entity: fn _opts ->
          %{observation: %{gate: "call_entity", result: "ok", is_error: false}, value: "ok"}
        end,
        execute_gate: fn gate_name, args ->
          Circle.execute_gate(circle, gate_name, args)
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
end
