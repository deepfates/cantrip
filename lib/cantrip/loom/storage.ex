defmodule Cantrip.Loom.Storage do
  @moduledoc """
  If you implement this behaviour, you are giving the loom a place to live.
  Built-in backends are memory, JSONL, and Mnesia; `load/1` is the optional
  rehydration callback that lets a summoning resume from a prior trajectory.

  Storage behavior for persisting loom events.
  """

  @type storage_state :: term()

  @callback init(term()) :: {:ok, storage_state()}
  @callback append_event(storage_state(), map()) :: {:ok, storage_state()} | {:error, term()}
  @callback append_turn(storage_state(), map()) :: {:ok, storage_state()} | {:error, term()}
  @callback annotate_reward(storage_state(), non_neg_integer(), term()) ::
              {:ok, storage_state()} | {:error, term()}
  @callback flush(storage_state()) :: {:ok, storage_state()} | {:error, term()}
  @callback close(storage_state()) :: :ok | {:error, term()}

  @doc """
  Load prior persisted state into a freshly-initialized backend.

  Returns `{:ok, %{events: [...], turns: [...]}}` with reconstructed
  events and turns from the storage's durable record, or `{:ok, %{events:
  [], turns: []}}` for backends that don't yet support rehydration.

  This is what makes the loom an actual replay buffer rather than a
  write-only log: a Familiar summoned a second time against the same
  `loom_path` should resume with its prior turns visible in `loom.turns`.
  """
  @callback load(storage_state()) ::
              {:ok, %{events: [map()], turns: [map()]}} | {:error, term()}

  @optional_callbacks append_event: 2, load: 1, flush: 1, close: 1
end
