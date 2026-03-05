defmodule Cantrip.Loom.Storage do
  @moduledoc """
  Storage behavior for persisting loom events.
  """

  @type storage_state :: term()

  @callback init(term()) :: {:ok, storage_state()}
  @callback append_turn(storage_state(), map()) :: {:ok, storage_state()} | {:error, term()}
  @callback annotate_reward(storage_state(), non_neg_integer(), term()) ::
              {:ok, storage_state()} | {:error, term()}
end
