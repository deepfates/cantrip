defmodule Cantrip.Conformance.Runner do
  @moduledoc "Executes tests.yaml conformance cases against Elixir Cantrip runtime."

  alias Cantrip.Conformance.{Expect, FakeLLM, Loader, TestCase}

  @spec run_all!() :: :ok
  def run_all! do
    Loader.load()
    |> Enum.each(&run_case!/1)

    :ok
  end

  @spec run_case!(TestCase.t()) :: :ok
  def run_case!(%TestCase{} = test_case) do
    execute_case(test_case)
    |> then(fn result -> Expect.check!(test_case.expect, result) end)
  rescue
    error ->
      reraise RuntimeError,
              [message: "conformance case #{test_case.id} (#{test_case.description}) failed: #{Exception.message(error)}"],
              __STACKTRACE__
  end

  defp execute_case(%TestCase{setup: setup, action: action}) do
    llm_responses = get_in(setup, ["llm", "responses"]) || []

    {:ok, cantrip} =
      Cantrip.new(
        llm: {FakeLLM, FakeLLM.new(llm_responses)},
        circle: get_in(setup, ["circle"]) || %{"gates" => ["done"], "wards" => [%{"max_turns" => 10}]},
        identity: get_in(setup, ["identity"]) || %{}
      )

    execute_action(cantrip, action)
  end

  defp execute_action(cantrip, %{"cast" => %{"intent" => intent}}) do
    {:ok, result, _next_cantrip, _loom, meta} = Cantrip.cast(cantrip, intent)
    %{result: result, meta: meta}
  end

  defp execute_action(cantrip, action) when is_list(action) do
    Enum.reduce(action, %{result: nil, meta: %{}}, fn step, _acc -> execute_action(cantrip, step) end)
  end

  defp execute_action(_cantrip, _action) do
    raise "unsupported action"
  end
end
