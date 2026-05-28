defmodule Cantrip.Test.SleepingLLM do
  @moduledoc false

  @behaviour Cantrip.LLM

  @impl true
  def query(state, _request) do
    sleep_ms = Map.get(state, :sleep_ms, Map.get(state, "sleep_ms", 1_000))
    Process.sleep(sleep_ms)
    {:ok, %{content: Map.get(state, :content, "slept")}, state}
  end
end
