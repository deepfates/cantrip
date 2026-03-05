defmodule Cantrip.Loom.Storage.Memory do
  @moduledoc false

  @behaviour Cantrip.Loom.Storage

  @impl true
  def init(_opts), do: {:ok, %{}}

  @impl true
  def append_turn(state, _turn), do: {:ok, state}

  @impl true
  def annotate_reward(state, _index, _reward), do: {:ok, state}
end
