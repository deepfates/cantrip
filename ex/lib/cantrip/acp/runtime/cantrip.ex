defmodule Cantrip.ACP.Runtime.Cantrip do
  @moduledoc false

  @behaviour Cantrip.ACP.Runtime

  @impl true
  def new_session(params) do
    cwd = Map.get(params, "cwd")

    case Cantrip.new_from_env(
           circle: %{
             gates: [:done, :echo, :call_agent, :call_agent_batch, :compile_and_load],
             wards: [%{max_turns: 24}, %{max_depth: 2}, %{max_concurrent_children: 4}]
           }
         ) do
      {:ok, cantrip} -> {:ok, %{cantrip: cantrip, cwd: cwd}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def prompt(%{cantrip: cantrip} = session, text) when is_binary(text) do
    case Cantrip.cast(cantrip, text) do
      {:ok, result, next_cantrip, _loom, _meta} ->
        {:ok, to_string(result), %{session | cantrip: next_cantrip}}

      {:error, reason, next_cantrip} ->
        {:error, inspect(reason), %{session | cantrip: next_cantrip}}
    end
  end
end
