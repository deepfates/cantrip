defmodule Cantrip.Medium.Registry do
  @moduledoc """
  Resolves circle medium types to medium modules.

  Keeping this lookup explicit gives the runtime one place to add future
  mediums without teaching the entity loop about each substrate.
  """

  @spec fetch(atom()) :: {:ok, module()} | {:error, String.t()}
  def fetch(:conversation), do: {:ok, Cantrip.Medium.Conversation}
  def fetch(:code), do: {:ok, Cantrip.Medium.Code}
  def fetch(:bash), do: {:ok, Cantrip.Medium.Bash}
  def fetch(other), do: {:error, "unknown medium: #{inspect(other)}"}

  @spec fetch!(atom()) :: module()
  def fetch!(type) do
    case fetch(type) do
      {:ok, module} -> module
      {:error, reason} -> raise ArgumentError, reason
    end
  end

  @spec present(Cantrip.Circle.t(), map()) :: Cantrip.Medium.presentation()
  def present(%Cantrip.Circle{type: type} = circle, state \\ %{}) do
    type
    |> fetch!()
    |> apply(:present, [circle, state])
  end
end
