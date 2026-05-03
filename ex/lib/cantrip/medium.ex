defmodule Cantrip.Medium do
  @moduledoc """
  Behaviour for a circle medium.

  A medium owns the "inside" of a circle: how capabilities are presented to
  the LLM, how an utterance is executed, and how medium-local state is captured
  for persistence or fork.

  `Cantrip.EntityServer` decides when an entity takes a turn; mediums decide
  what an LLM utterance means inside that turn. Code, bash, and conversation
  can therefore keep different execution semantics without hiding control flow
  inside the entity process.
  """

  @type circle :: Cantrip.Circle.t()
  @type medium_state :: map()
  @type runtime :: map()
  @type presentation :: %{
          optional(:tools) => list(map()),
          optional(:tool_choice) => String.t() | atom() | nil,
          optional(:capability_text) => String.t() | nil
        }
  @type execution_result ::
          {:ok, medium_state(), list(map()), term(), boolean()}
          | {:error, medium_state(), list(map())}

  @doc """
  Return the LLM-facing presentation for this medium in the given circle.

  Implementations should keep this pure. It is used to build the model request,
  not to execute host effects.
  """
  @callback present(circle(), medium_state()) :: presentation()

  @doc """
  Execute one model utterance inside the medium.

  The returned boolean is the medium-level termination signal for the current
  episode. Gate failures should be represented as observations rather than
  process crashes when they are expected operational failures.
  """
  @callback execute(term(), medium_state(), runtime()) :: execution_result()

  @doc """
  Capture enough medium state to fork or persist an entity.
  """
  @callback snapshot(medium_state()) :: term()

  @doc """
  Restore medium state from a snapshot.
  """
  @callback restore(term()) :: medium_state()
end
