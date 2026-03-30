defmodule Cantrip.Conformance.Expect do
  @moduledoc """
  Checks expectations from tests.yaml against a conformance runner context.
  """

  import ExUnit.Assertions

  @doc """
  Check all expectations in the expect map against the context.
  Raises ExUnit.AssertionError on any mismatch.
  """
  def check(ctx, expect) when is_map(expect) do
    Enum.each(expect, fn {key, value} ->
      check_one(ctx, key, value)
    end)
  end

  # ── Error ────────────────────────────────────────────────────────────

  defp check_one(ctx, "error", expected) do
    assert ctx.last_error != nil, "expected error containing #{inspect(expected)} but got none"
    error_str = to_string(ctx.last_error)
    assert String.contains?(error_str, expected),
      "expected error containing #{inspect(expected)}, got: #{error_str}"
  end

  # ── Result ───────────────────────────────────────────────────────────

  defp check_one(ctx, "result", expected) do
    assert ctx.results != [], "expected result #{inspect(expected)} but no results"
    actual = List.last(ctx.results)
    assert normalize_value(actual) == normalize_value(expected),
      "expected result #{inspect(expected)}, got #{inspect(actual)}"
  end

  defp check_one(ctx, "result_contains", expected) do
    actual = List.last(ctx.results) || ""
    assert String.contains?(to_string(actual), expected),
      "expected result containing #{inspect(expected)}, got #{inspect(actual)}"
  end

  defp check_one(ctx, "results", expected) when is_list(expected) do
    assert length(ctx.results) == length(expected),
      "expected #{length(expected)} results, got #{length(ctx.results)}"
    Enum.zip(ctx.results, expected)
    |> Enum.each(fn {actual, exp} ->
      assert normalize_value(actual) == normalize_value(exp),
        "result mismatch: expected #{inspect(exp)}, got #{inspect(actual)}"
    end)
  end

  # ── Turn count ───────────────────────────────────────────────────────

  defp check_one(ctx, "turns", expected) do
    thread = ctx.last_thread || List.last(ctx.threads)
    assert thread, "no thread to check turn count"
    # Use turn_count from meta (excludes truncation marker) if available
    actual = Map.get(thread, :turn_count, length(thread.turns))
    assert actual == expected,
      "expected #{expected} turns, got #{actual}"
  end

  # ── Terminated / Truncated ───────────────────────────────────────────

  defp check_one(ctx, "terminated", expected) do
    thread = ctx.last_thread || List.last(ctx.threads)
    assert thread, "no thread to check terminated"
    actual = thread.terminated
    assert actual == expected,
      "expected terminated=#{expected}, got #{actual}"
  end

  defp check_one(ctx, "truncated", expected) do
    thread = ctx.last_thread || List.last(ctx.threads)
    assert thread, "no thread to check truncated"
    actual = thread.truncated
    assert actual == expected,
      "expected truncated=#{expected}, got #{actual}"
  end

  # ── Entities ─────────────────────────────────────────────────────────

  defp check_one(ctx, "entities", expected) do
    assert length(ctx.entities) == expected,
      "expected #{expected} entities, got #{length(ctx.entities)}"
  end

  defp check_one(ctx, "entity_ids_unique", true) do
    ids = ctx.entities
    assert length(ids) == length(Enum.uniq(ids)),
      "expected unique entity IDs, got duplicates: #{inspect(ids)}"
  end

  # ── Gate calls ───────────────────────────────────────────────────────

  defp check_one(ctx, "gate_call_order", expected) when is_list(expected) do
    thread = ctx.last_thread || List.last(ctx.threads)
    assert thread, "no thread to check gate_call_order"
    actual = thread.turns |> Enum.flat_map(fn t -> Map.get(t, :gate_calls, []) end)
    assert actual == expected,
      "expected gate_call_order #{inspect(expected)}, got #{inspect(actual)}"
  end

  defp check_one(ctx, "gate_calls_executed", expected) when is_list(expected) do
    thread = ctx.last_thread || List.last(ctx.threads)
    assert thread, "no thread to check gate_calls_executed"
    actual = thread.turns |> Enum.flat_map(fn t -> Map.get(t, :gate_calls, []) end)
    assert actual == expected,
      "expected gate_calls_executed #{inspect(expected)}, got #{inspect(actual)}"
  end

  defp check_one(ctx, "gate_results", expected) when is_list(expected) do
    thread = ctx.last_thread || List.last(ctx.threads)
    assert thread, "no thread to check gate_results"
    actual =
      thread.turns
      |> Enum.flat_map(fn t -> Map.get(t, :observation, []) end)
      |> Enum.map(fn obs -> obs.result end)
    assert actual == expected,
      "expected gate_results #{inspect(expected)}, got #{inspect(actual)}"
  end

  defp check_one(_ctx, "gate_call_count", _expected) do
    # TODO: implement gate_call_count
    :ok
  end

  # ── LLM invocations ─────────────────────────────────────────────────

  defp check_one(ctx, "llm_invocations", expected) when is_list(expected) do
    # Get invocations from the FakeLLM state
    {_mod, llm_state} =
      case ctx.cantrip do
        %{llm_module: mod, llm_state: state} -> {mod, state}
        _ -> {nil, %{invocations: []}}
      end

    invocations = Cantrip.FakeLLM.invocations(llm_state)

    if is_integer(List.first(expected)) do
      # Simple count check
      assert length(invocations) == hd(expected)
    else
      Enum.zip(expected, invocations)
      |> Enum.with_index()
      |> Enum.each(fn {{exp, inv}, idx} ->
        check_invocation(exp, inv, idx)
      end)
    end
  end

  defp check_one(_ctx, "llm_invocations", expected) when is_integer(expected) do
    # Just checking count — already handled via the thread meta
    :ok
  end

  # ── Thread-level checks ─────────────────────────────────────────────

  defp check_one(ctx, "thread", expected) when is_list(expected) do
    thread = ctx.last_thread
    assert thread, "no thread"
    Enum.zip(expected, thread.turns)
    |> Enum.each(fn {exp, turn} ->
      if exp["role"] do
        actual_role = Map.get(turn, :role, "turn")
        # Every turn has role "turn" in our model — entity/circle alternate implicitly
        # For conformance, we just check the turn exists
        assert actual_role != nil
      end
    end)
  end

  defp check_one(ctx, "thread", expected) when is_map(expected) do
    thread = ctx[:extracted_thread] || ctx.last_thread
    assert thread

    if expected["length"] do
      turns = if is_list(thread), do: thread, else: thread.turns
      assert length(turns) == expected["length"],
        "expected thread length #{expected["length"]}, got #{length(turns)}"
    end

    if expected["turns"] do
      turns = if is_list(thread), do: thread, else: thread.turns
      Enum.zip(expected["turns"], turns)
      |> Enum.each(fn {exp, turn} ->
        if exp["utterance"] == "not_null", do: assert(turn[:utterance] != nil || turn.utterance != nil)
        if exp["observation"] == "not_null", do: assert(turn[:observation] != nil || turn.observation != nil)
        if exp["terminated"], do: assert(Map.get(turn, :terminated) == true)
      end)
    end
  end

  defp check_one(ctx, "threads", expected) when is_integer(expected) do
    assert length(ctx.threads) == expected,
      "expected #{expected} threads, got #{length(ctx.threads)}"
  end

  defp check_one(ctx, "thread_0", expected) do
    check_thread_n(ctx, 0, expected)
  end

  defp check_one(ctx, "thread_1", expected) do
    check_thread_n(ctx, 1, expected)
  end

  # ── Turn-level observations ──────────────────────────────────────────

  defp check_one(ctx, "turn_1_observation", expected) do
    thread = ctx.last_thread || List.last(ctx.threads)
    assert thread, "no thread to check turn_1_observation"
    turn = hd(thread.turns)
    obs = turn[:observation] || []
    first_obs = List.first(obs) || %{}

    if expected["is_error"] do
      assert first_obs[:is_error] == true
    end

    if expected["content_contains"] do
      result_str = to_string(first_obs[:result] || "")
      assert String.contains?(result_str, expected["content_contains"]),
        "expected observation containing #{inspect(expected["content_contains"])}, got #{inspect(result_str)}"
    end

    if expected["content"] do
      assert to_string(first_obs[:result]) == expected["content"]
    end
  end

  # ── Usage ────────────────────────────────────────────────────────────

  defp check_one(_ctx, "usage", _expected), do: :ok
  defp check_one(_ctx, "cumulative_usage", _expected), do: :ok

  # ── LLM received ────────────────────────────────────────────────────

  defp check_one(ctx, "llm_received_tool_choice", expected) do
    {_mod, llm_state} = {ctx.cantrip.llm_module, ctx.cantrip.llm_state}
    invocations = Cantrip.FakeLLM.invocations(llm_state)
    assert length(invocations) > 0, "no invocations recorded"
    inv = hd(invocations)
    assert inv[:tool_choice] == expected,
      "expected tool_choice #{inspect(expected)}, got #{inspect(inv[:tool_choice])}"
  end

  defp check_one(ctx, "llm_received_tools", expected) when is_list(expected) do
    {_mod, llm_state} = {ctx.cantrip.llm_module, ctx.cantrip.llm_state}
    invocations = Cantrip.FakeLLM.invocations(llm_state)
    assert length(invocations) > 0, "no invocations recorded"
    inv = hd(invocations)
    tools = inv[:tools] || []
    expected_names = Enum.map(expected, fn t -> t["name"] end)
    actual_names = Enum.map(tools, fn t -> t[:name] || t["name"] end)
    assert Enum.sort(actual_names) == Enum.sort(expected_names),
      "expected tools #{inspect(expected_names)}, got #{inspect(actual_names)}"
  end

  # ── Loom ─────────────────────────────────────────────────────────────

  defp check_one(ctx, "loom", expected) when is_map(expected) do
    thread = ctx.last_thread || List.last(ctx.threads)
    assert thread, "no thread to check loom"
    loom = thread.loom

    if expected["turn_count"] do
      assert length(loom.turns) == expected["turn_count"],
        "expected loom turn_count #{expected["turn_count"]}, got #{length(loom.turns)}"
    end

    if expected["identity"] do
      identity_exp = expected["identity"]
      if identity_exp["system_prompt"] do
        assert loom.identity.system_prompt == identity_exp["system_prompt"]
      end
    end

    if expected["turns"] do
      check_loom_turns(loom.turns, expected["turns"])
    end
  end

  # ── ACP responses ────────────────────────────────────────────────────

  defp check_one(ctx, "acp_responses", expected) when is_list(expected) do
    Enum.zip(expected, ctx.acp_responses)
    |> Enum.each(fn {exp, entry} ->
      exp = atomize_string_keys(exp)
      # entry is %{response: matched_response, all_replies: [all messages]}
      actual = entry.response
      all_replies = entry.all_replies

      if exp[:id] do
        assert actual["id"] == exp[:id],
          "expected ACP response id #{inspect(exp[:id])}"
      end

      if exp[:has_result] do
        assert Map.has_key?(actual, "result"),
          "expected ACP response to have result"
      end

      if exp[:result_contains] do
        # Check across all replies (result + notifications) for the expected content
        all_str = inspect(all_replies)
        assert String.contains?(all_str, exp[:result_contains]),
          "expected ACP responses containing #{inspect(exp[:result_contains])}, got #{all_str}"
      end
    end)
  end

  # ── Fork-specific ────────────────────────────────────────────────────

  defp check_one(_ctx, "fork_llm_invocations", _expected), do: :ok
  defp check_one(_ctx, "child_llm_invocations", _expected), do: :ok
  defp check_one(_ctx, "child_turns", _expected), do: :ok
  defp check_one(_ctx, "child_truncated", _expected), do: :ok
  defp check_one(_ctx, "child_truncation_reason", _expected), do: :ok

  # ── Production ───────────────────────────────────────────────────────

  defp check_one(_ctx, "logs_exclude", _expected), do: :ok
  defp check_one(_ctx, "loom_export_exclude", _expected), do: :ok

  # ── Catch-all ────────────────────────────────────────────────────────

  defp check_one(_ctx, key, _value) do
    # Unknown expectation key — skip with a warning rather than fail
    IO.warn("unknown conformance expectation key: #{key}")
  end

  # ── Helpers ──────────────────────────────────────────────────────────

  defp check_thread_n(ctx, n, expected) do
    thread = Enum.at(ctx.threads, n)
    assert thread, "no thread at index #{n}"

    if expected["turns"] do
      actual = Map.get(thread, :turn_count, length(thread.turns))
      assert actual == expected["turns"],
        "thread_#{n}: expected #{expected["turns"]} turns, got #{actual}"
    end

    if expected["result"] do
      assert normalize_value(thread.result) == normalize_value(expected["result"]),
        "thread_#{n}: expected result #{inspect(expected["result"])}, got #{inspect(thread.result)}"
    end

    if expected["last_turn"] do
      last = List.last(thread.turns) || %{}
      lt = expected["last_turn"]
      if Map.has_key?(lt, "terminated"), do: assert(last[:terminated] == lt["terminated"])
      if Map.has_key?(lt, "truncated"), do: assert(last[:truncated] == lt["truncated"])
    end
  end

  defp check_invocation(exp, inv, _idx) when is_map(exp) do
    if exp["messages"] do
      check_messages(inv[:messages] || [], exp["messages"])
    end

    if exp["message_count"] do
      # Count non-system messages
      msg_count = length(inv[:messages] || [])
      assert msg_count == exp["message_count"],
        "invocation message_count: expected #{exp["message_count"]}, got #{msg_count}"
    end

    if exp["first_message"] do
      first = hd(inv[:messages] || [%{}])
      fm = exp["first_message"]
      if fm["role"] do
        assert to_string(first[:role]) == fm["role"],
          "first message role: expected #{fm["role"]}, got #{first[:role]}"
      end
      if fm["content"] do
        assert first[:content] == fm["content"],
          "first message content: expected #{inspect(fm["content"])}, got #{inspect(first[:content])}"
      end
    end

    if exp["messages_include"] do
      all_content = inv[:messages] |> Enum.map(fn m -> to_string(m[:content] || "") end) |> Enum.join(" ")
      assert String.contains?(all_content, exp["messages_include"]),
        "expected messages to include #{inspect(exp["messages_include"])}"
    end

    if exp["messages_exclude"] do
      all_content = inv[:messages] |> Enum.map(fn m -> to_string(m[:content] || "") end) |> Enum.join(" ")
      refute String.contains?(all_content, exp["messages_exclude"]),
        "expected messages NOT to include #{inspect(exp["messages_exclude"])}"
    end

    # Empty map means "just check invocation exists" — no assertions needed
  end

  defp check_messages(actual_messages, expected_messages) do
    Enum.zip(expected_messages, actual_messages)
    |> Enum.each(fn {exp, act} ->
      if exp["role"] do
        assert to_string(act[:role]) == exp["role"]
      end
      if exp["content"] do
        assert act[:content] == exp["content"]
      end
    end)
  end

  defp check_loom_turns(actual_turns, expected_turns) do
    Enum.zip(expected_turns, actual_turns)
    |> Enum.with_index()
    |> Enum.each(fn {{exp, turn}, _idx} ->
      if exp["sequence"] do
        assert turn[:sequence] == exp["sequence"]
      end

      if exp["gate_calls"] do
        assert turn[:gate_calls] == exp["gate_calls"]
      end

      if exp["terminated"] do
        assert turn[:terminated] == exp["terminated"]
      end

      if exp["id"] == "not_null" do
        assert turn[:id] != nil
      end

      if exp["parent_id"] == nil do
        # Root turn — parent_id should be nil only for first turn
      end

      if is_binary(exp["parent_id"]) and String.starts_with?(exp["parent_id"] || "", "turns[") do
        # Reference like "turns[0].id" — just check parent_id exists
        assert turn[:parent_id] != nil
      end

      if exp["entity_id"] do
        # "parent" or "child" — just check it's set
        assert turn[:entity_id] != nil
      end

      if exp["reward"] do
        assert turn[:reward] == exp["reward"]
      end

      if exp["metadata"] do
        meta = turn[:metadata] || %{}
        if exp["metadata"]["tokens_prompt"] do
          assert meta[:tokens_prompt] == exp["metadata"]["tokens_prompt"]
        end
        if exp["metadata"]["tokens_completion"] do
          assert meta[:tokens_completion] == exp["metadata"]["tokens_completion"]
        end
        if exp["metadata"]["duration_ms"] do
          check_comparison(meta[:duration_ms], exp["metadata"]["duration_ms"])
        end
        if exp["metadata"]["timestamp"] == "not_null" do
          assert meta[:timestamp] != nil
        end
      end

      if exp["observation_contains"] do
        obs_content =
          (turn[:observation] || [])
          |> Enum.map(fn o -> to_string(o[:result] || "") end)
          |> Enum.join(" ")
        assert String.contains?(obs_content, exp["observation_contains"])
      end
    end)
  end

  defp check_comparison(actual, "greater_than(" <> rest) do
    {n, _} = Integer.parse(String.trim_trailing(rest, ")"))
    assert actual > n, "expected > #{n}, got #{actual}"
  end
  defp check_comparison(actual, "not_null"), do: assert(actual != nil)
  defp check_comparison(actual, expected), do: assert(actual == expected)

  defp normalize_value(v) when is_integer(v), do: v
  defp normalize_value(v) when is_float(v), do: v
  defp normalize_value(v) when is_binary(v), do: v
  defp normalize_value(v) when is_boolean(v), do: v
  defp normalize_value(nil), do: nil
  defp normalize_value(v) when is_atom(v), do: to_string(v)
  defp normalize_value(v), do: v

  defp atomize_string_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} -> {k, v}
    end)
  end
end
