defmodule Cantrip.Loom.Storage.Auto do
  @moduledoc false

  @behaviour Cantrip.Loom.Storage

  alias Cantrip.Loom.Storage.{Dets, Mnesia}
  import Cantrip.LLMs.Helpers, only: [normalize_opts: 1]

  @impl true
  def init(opts) do
    opts = normalize_opts(opts)

    mnesia_opts = %{
      table: Map.get(opts, :mnesia_table, default_mnesia_table())
    }

    dets_path =
      Map.get(
        opts,
        :dets_path,
        Path.join(
          System.tmp_dir!(),
          "cantrip_loom_auto_#{System.unique_integer([:positive])}.dets"
        )
      )

    case Mnesia.init(mnesia_opts) do
      {:ok, mnesia_state} ->
        {:ok, %{backend: :mnesia, module: Mnesia, state: mnesia_state}}

      {:error, _reason} ->
        case Dets.init(dets_path) do
          {:ok, dets_state} ->
            {:ok, %{backend: :dets, module: Dets, state: dets_state}}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  @impl true
  def append_turn(%{module: module, state: state} = storage, turn) do
    case module.append_turn(state, turn) do
      {:ok, next_state} -> {:ok, %{storage | state: next_state}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def append_event(%{module: module, state: state} = storage, event) do
    result =
      if function_exported?(module, :append_event, 2) do
        module.append_event(state, event)
      else
        append_event_compat(module, state, event)
      end

    case result do
      {:ok, next_state} -> {:ok, %{storage | state: next_state}}
      {:error, reason} -> {:error, reason}
    end
  end

  @impl true
  def annotate_reward(%{module: module, state: state} = storage, index, reward) do
    case module.annotate_reward(state, index, reward) do
      {:ok, next_state} -> {:ok, %{storage | state: next_state}}
      {:error, reason} -> {:error, reason}
    end
  end

  def read_events(%{backend: :mnesia, state: %{table: table}}) do
    Mnesia.read_events(table)
  end

  def read_events(%{backend: :dets, state: %{path: path}}) do
    Dets.read_events(path)
  end

  def read_events(_), do: {:error, "invalid auto storage state"}

  defp append_event_compat(module, state, event) do
    case event_type(event) do
      :turn ->
        module.append_turn(state, Map.fetch!(event, :turn))

      :reward ->
        module.annotate_reward(state, Map.fetch!(event, :index), Map.fetch!(event, :reward))

      _ ->
        {:ok, state}
    end
  end

  defp event_type(event), do: Map.get(event, :type) || Map.get(event, "type")

  defp default_mnesia_table do
    :"cantrip_loom_auto_#{System.unique_integer([:positive])}"
  end
end
