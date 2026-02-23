defmodule Cantrip.Crystal do
  @moduledoc """
  Crystal adapter contract.
  """

  @type request :: %{
          required(:messages) => list(map()),
          required(:tools) => list(map()),
          optional(:tool_choice) => String.t() | nil
        }

  @type response :: %{
          optional(:content) => String.t() | nil,
          optional(:tool_calls) => list(map()) | nil,
          optional(:usage) => map() | nil
        }

  @callback query(state :: term(), request()) ::
              {:ok, response(), term()} | {:error, term(), term()}
end
