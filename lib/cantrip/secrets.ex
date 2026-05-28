defmodule Cantrip.Secrets do
  @moduledoc false

  @secret_key_fragments [
    "api_key",
    "apikey",
    "secret",
    "password",
    "token",
    "authorization",
    "bearer",
    "cookie",
    "private_key",
    "client_secret"
  ]

  @doc false
  @spec secret_key?(term()) :: boolean()
  def secret_key?(key) when is_atom(key), do: key |> Atom.to_string() |> secret_key?()

  def secret_key?(key) when is_binary(key) do
    lower = String.downcase(key)
    Enum.any?(@secret_key_fragments, &String.contains?(lower, &1))
  end

  def secret_key?(_key), do: false
end
