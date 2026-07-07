defmodule Cantrip.Event do
  @moduledoc false

  @type envelope :: %{
          version: pos_integer(),
          entity_id: String.t(),
          trace_id: String.t(),
          turn_id: String.t(),
          correlation_id: String.t(),
          depth: non_neg_integer(),
          medium: atom(),
          sequence: pos_integer(),
          timestamp: DateTime.t()
        }
  @type event :: {atom(), term()}
  @type enveloped_event :: {envelope(), event()}

  @spec upcast(map()) :: map()
  def upcast(%{version: 1} = envelope), do: envelope
  def upcast(%{"version" => 1} = envelope), do: envelope

  def upcast(%{version: version}) do
    raise "unsupported cantrip event version: #{Cantrip.SafeFormat.inspect(version)}"
  end

  def upcast(%{"version" => version}) do
    raise "unsupported cantrip event version: #{Cantrip.SafeFormat.inspect(version)}"
  end

  def upcast(%{}) do
    raise "missing cantrip event version"
  end

  @spec envelope(map(), event() | nil) :: envelope()
  def envelope(
        %{entity_id: entity_id, depth: depth, cantrip: %{circle: %{type: medium}}} = state,
        event \\ nil
      ) do
    turn_id = turn_id(state, event)

    %{
      version: 1,
      entity_id: entity_id,
      trace_id: Map.fetch!(state, :trace_id),
      turn_id: turn_id,
      correlation_id: correlation_id(event, turn_id),
      depth: depth,
      medium: medium,
      sequence: next_sequence(),
      timestamp: DateTime.utc_now()
    }
  end

  @spec wrap(map(), event()) :: enveloped_event()
  def wrap(state, event), do: {envelope(state, event), event}

  @spec tool_events(list(map())) :: list(event())
  def tool_events(observations) do
    Enum.flat_map(observations, fn obs ->
      tool_call_id = obs[:tool_call_id] || mint_tool_call_id()

      [
        {:tool_call,
         %{
           gate: obs.gate,
           tool_call_id: tool_call_id,
           kind: gate_kind(obs.gate),
           args_summary: args_summary(obs.gate, obs[:args])
         }},
        {:tool_result,
         %{
           gate: obs.gate,
           result: obs.result,
           is_error: obs.is_error,
           tool_call_id: tool_call_id,
           child_turn_count: child_turn_count(obs)
         }}
      ]
    end)
  end

  @doc """
  Build all per-turn runtime events when the caller has not already emitted the
  model utterance events.

  `EntityServer` emits `classified.events` before code eval so parent scripts
  render before child scripts; that path should use `turn_result_events/3`
  after execution.
  """
  @spec turn_runtime_events(map(), boolean(), pos_integer()) :: list(event())
  def turn_runtime_events(executed, terminated?, turn_number) do
    executed.events ++
      tool_events(executed.observation) ++ empty_turn_events(executed, terminated?, turn_number)
  end

  @spec turn_result_events(map(), boolean(), pos_integer()) :: list(event())
  def turn_result_events(executed, terminated?, turn_number) do
    tool_events(executed.observation) ++ empty_turn_events(executed, terminated?, turn_number)
  end

  @spec send(pid() | nil, map(), event()) :: :ok
  def send(nil, _state, _event), do: :ok

  def send(pid, state, event) when is_pid(pid) do
    Kernel.send(pid, {:cantrip_event, wrap(state, event)})
    :ok
  end

  @spec send_with_barrier(pid() | nil, map(), event()) :: :ok | :dead | :timeout
  def send_with_barrier(nil, _state, _event), do: :ok

  def send_with_barrier(pid, state, event) when is_pid(pid) do
    :ok = send(pid, state, event)

    if Map.get(state, :stream_barrier?, false) do
      barrier(pid, :infinity)
    else
      :ok
    end
  end

  @spec barrier(pid(), timeout()) :: :ok | :dead | :timeout
  def barrier(pid, timeout \\ 5_000) when is_pid(pid) do
    if Process.alive?(pid) do
      monitor_ref = Process.monitor(pid)
      barrier_ref = make_ref()
      Kernel.send(pid, {:cantrip_barrier, self(), barrier_ref})

      receive do
        {:cantrip_barriered, ^barrier_ref} ->
          Process.demonitor(monitor_ref, [:flush])
          :ok

        {:DOWN, ^monitor_ref, :process, ^pid, _reason} ->
          :dead
      after
        timeout ->
          Process.demonitor(monitor_ref, [:flush])
          :timeout
      end
    else
      :dead
    end
  end

  defp next_sequence do
    System.unique_integer([:positive, :monotonic])
  end

  defp turn_id(%{entity_id: entity_id}, {_type, %{turn: turn}}) when is_integer(turn) do
    "#{entity_id}:turn:#{turn}"
  end

  defp turn_id(%{entity_id: entity_id, turns: turns}, _event) when is_integer(turns) do
    "#{entity_id}:turn:#{turns + 1}"
  end

  defp turn_id(%{entity_id: entity_id}, _event), do: "#{entity_id}:turn:unknown"

  defp correlation_id({_type, %{tool_call_id: id}}, _turn_id) when is_binary(id), do: id
  defp correlation_id({_type, %{correlation_id: id}}, _turn_id) when is_binary(id), do: id
  defp correlation_id(_event, turn_id), do: turn_id

  defp empty_turn_events(%{observation: []}, false, turn_number) do
    [{:empty_turn, %{turn: turn_number}}]
  end

  defp empty_turn_events(_executed, _terminated?, _turn_number), do: []

  defp mint_tool_call_id do
    "call_" <> Integer.to_string(System.unique_integer([:positive]))
  end

  defp gate_kind("read_file"), do: :read
  defp gate_kind("list_dir"), do: :read
  defp gate_kind("search"), do: :search
  defp gate_kind("compile_and_load"), do: :edit
  defp gate_kind("mix"), do: :execute
  defp gate_kind(_), do: :execute

  defp args_summary("read_file", args) when is_binary(args), do: args
  defp args_summary("read_file", %{} = a), do: Map.get(a, "path", Map.get(a, :path))
  defp args_summary("list_dir", args) when is_binary(args), do: args
  defp args_summary("list_dir", %{} = a), do: Map.get(a, "path", Map.get(a, :path))
  defp args_summary("search", %{} = a), do: Map.get(a, "pattern", Map.get(a, :pattern))
  defp args_summary("mix", %{} = a), do: Map.get(a, "task", Map.get(a, :task))
  defp args_summary(_, _), do: nil

  defp child_turn_count(%{child_turns: turns}) when is_list(turns), do: length(turns)
  defp child_turn_count(%{"child_turns" => turns}) when is_list(turns), do: length(turns)
  defp child_turn_count(_obs), do: 0
end
