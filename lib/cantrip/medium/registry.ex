defmodule Cantrip.Medium.Registry do
  @moduledoc false

  @spec fetch(atom()) :: {:ok, module()} | {:error, String.t()}
  def fetch(:conversation), do: {:ok, Cantrip.Medium.Conversation}
  def fetch(:code), do: {:ok, Cantrip.Medium.Code}
  def fetch(:bash), do: {:ok, Cantrip.Medium.Bash}
  def fetch(other), do: {:error, "unknown medium: #{Cantrip.SafeFormat.inspect(other)}"}

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
