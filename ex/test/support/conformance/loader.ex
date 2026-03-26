defmodule Cantrip.Conformance.Loader do
  @moduledoc """
  Loads tests.yaml and normalizes each case into a map usable by the runner.
  """

  @spec load(String.t()) :: [map()]
  def load(path) do
    path
    |> YamlElixir.read_from_file!()
    |> Enum.map(&normalize_case/1)
  end

  defp normalize_case(raw) do
    %{
      rule: raw["rule"],
      name: raw["name"],
      description: raw["description"],
      skip: raw["skip"],
      setup: normalize_setup(raw["setup"] || %{}),
      action: normalize_action(raw["action"]),
      expect: raw["expect"] || %{}
    }
  end

  defp normalize_setup(setup) do
    Enum.reduce(setup, %{llms: %{}, circle: %{}, identity: %{}, folding: %{}, retry: %{}, filesystem: %{}}, fn
      {"circle", v}, acc ->
        %{acc | circle: normalize_circle_setup(v || %{})}

      {"identity", v}, acc ->
        %{acc | identity: v || %{}}

      {"folding", v}, acc ->
        %{acc | folding: v || %{}}

      {"retry", v}, acc ->
        %{acc | retry: v || %{}}

      {"filesystem", v}, acc ->
        %{acc | filesystem: v || %{}}

      {key, v}, acc ->
        if String.contains?(key, "llm") do
          %{acc | llms: Map.put(acc.llms, key, normalize_llm(key, v))}
        else
          acc
        end
    end)
  end

  defp normalize_llm(_key, nil), do: nil

  defp normalize_llm(key, config) when is_map(config) do
    %{
      name: config["name"] || key,
      type: config["type"],
      responses: normalize_responses(config["responses"] || []),
      record_inputs: config["record_inputs"] || false,
      stateless: config["stateless"] || false,
      usage: config["usage"],
      provider: config["provider"],
      raw_response: config["raw_response"],
      retry_behavior: config["retry_behavior"] || false
    }
  end

  defp normalize_responses(responses) when is_list(responses) do
    Enum.map(responses, &normalize_response/1)
  end

  defp normalize_response(resp) when is_map(resp) do
    result = %{}

    tool_calls =
      case resp["tool_calls"] do
        calls when is_list(calls) ->
          Enum.map(calls, fn call ->
            tc = %{gate: call["gate"], args: atomize_shallow(call["args"] || %{})}
            if call["id"], do: Map.put(tc, :id, call["id"]), else: tc
          end)
        _ -> nil
      end

    result = if Map.has_key?(resp, "content"), do: Map.put(result, :content, resp["content"]), else: result
    result = if tool_calls, do: Map.put(result, :tool_calls, tool_calls), else: result
    result = if resp["code"], do: Map.put(result, :code, resp["code"]), else: result
    result = if resp["error"], do: Map.put(result, :error, normalize_error(resp["error"])), else: result
    result = if resp["usage"], do: Map.put(result, :usage, atomize_shallow(resp["usage"])), else: result
    result = if resp["tool_result"], do: Map.put(result, :tool_result, atomize_shallow(resp["tool_result"])), else: result
    result
  end

  defp normalize_error(err) when is_map(err), do: atomize_shallow(err)
  defp normalize_error(err), do: err

  defp normalize_circle_setup(circle) do
    gates =
      (circle["gates"] || [])
      |> Enum.map(fn
        gate when is_binary(gate) -> %{name: gate}
        gate when is_atom(gate) -> %{name: Atom.to_string(gate)}
        gate when is_map(gate) -> atomize_gate(gate)
      end)

    wards =
      (circle["wards"] || [])
      |> Enum.map(&atomize_shallow/1)

    type = circle["type"]
    medium = circle["medium"]
    circle_type = circle["circle_type"]

    result = %{gates: gates, wards: wards}
    result = if type, do: Map.put(result, :type, type), else: result
    result = if medium, do: Map.put(result, :medium, medium), else: result
    result = if circle_type, do: Map.put(result, :circle_type, circle_type), else: result
    result
  end

  defp atomize_gate(gate) do
    Enum.reduce(gate, %{}, fn
      {"name", v}, acc -> Map.put(acc, :name, to_string(v))
      {"parameters", v}, acc -> Map.put(acc, :parameters, v)
      {"dependencies", v}, acc -> Map.put(acc, :dependencies, atomize_shallow(v))
      {"behavior", "throw"}, acc -> Map.put(acc, :behavior, :throw)
      {"behavior", "delay"}, acc -> Map.put(acc, :behavior, :delay)
      {"ephemeral", v}, acc -> Map.put(acc, :ephemeral, v)
      {"stateful", v}, acc -> Map.put(acc, :stateful, v)
      {"result", v}, acc -> Map.put(acc, :result, v)
      {"error", v}, acc -> Map.put(acc, :error, v)
      {"delay_ms", v}, acc -> Map.put(acc, :delay_ms, v)
      {k, v}, acc -> Map.put(acc, String.to_atom(k), v)
    end)
  end

  defp normalize_action(action) when is_list(action), do: Enum.map(action, &normalize_single_action/1)
  defp normalize_action(action) when is_map(action), do: [normalize_single_action(action)]
  defp normalize_action(_), do: []

  defp normalize_single_action(action) when is_map(action) do
    cond do
      Map.has_key?(action, "cast") ->
        cast = atomize_shallow(action["cast"] || %{})
        then_block = action["then"]
        entry = %{cast: cast}
        if then_block, do: Map.put(entry, :then, normalize_then(then_block)), else: entry

      Map.has_key?(action, "construct_cantrip") ->
        %{construct_cantrip: true}

      Map.has_key?(action, "acp_exchange") ->
        %{acp_exchange: action["acp_exchange"]}

      Map.has_key?(action, "summon") ->
        %{summon: action["summon"]}

      Map.has_key?(action, "entity_cast") ->
        %{entity_cast: atomize_shallow(action["entity_cast"] || %{})}

      true ->
        %{unknown: action}
    end
  end

  defp normalize_then(then_block) when is_map(then_block) do
    Enum.reduce(then_block, %{}, fn
      {"mutate_identity", v}, acc -> Map.put(acc, :mutate_identity, v)
      {"delete_turn", v}, acc -> Map.put(acc, :delete_turn, v)
      {"annotate_reward", v}, acc -> Map.put(acc, :annotate_reward, atomize_shallow(v))
      {"fork", v}, acc -> Map.put(acc, :fork, atomize_shallow(v))
      {"extract_thread", v}, acc -> Map.put(acc, :extract_thread, v)
      {"export_loom", v}, acc -> Map.put(acc, :export_loom, atomize_shallow(v))
      {k, v}, acc -> Map.put(acc, String.to_atom(k), v)
    end)
  end

  defp normalize_then(_), do: %{}

  defp atomize_shallow(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp atomize_shallow(other), do: other
end
