defmodule Cantrip.ACP.Runtime do
  @moduledoc false

  @callback new_session(map()) :: {:ok, term()} | {:error, String.t()}
  @callback prepare_prompt(term()) :: {:ok, term()} | {:error, String.t(), term()}

  @callback prompt(term(), String.t()) ::
              {:ok, String.t(), term()} | {:cancelled, term()} | {:error, String.t(), term()}
  @callback cancel(term()) :: {:ok, term()} | {:error, String.t(), term()}

  @optional_callbacks prepare_prompt: 1, cancel: 1
end
