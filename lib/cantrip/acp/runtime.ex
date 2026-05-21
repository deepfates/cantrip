defmodule Cantrip.ACP.Runtime do
  @moduledoc false

  @callback new_session(map()) :: {:ok, term()} | {:error, String.t()}
  @callback prompt(term(), String.t()) :: {:ok, String.t(), term()} | {:error, String.t(), term()}
end
