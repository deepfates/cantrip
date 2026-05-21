defmodule Cantrip.Conformance.Runner do
  @moduledoc """
  Builds cantrip context from test case setup and executes actions.
  """

  alias Cantrip.FakeLLM

  @doc """
  Build a test context from a loaded test case.
  Returns a map with :cantrip, :llms, :results, :threads, etc.
  """
  def build_context(tc) do
    setup = tc.setup
    llm_configs = setup.llms

    # Build FakeLLM instances for each llm key in setup
    llms =
      llm_configs
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new(fn {key, config} ->
        fake = build_fake_llm(config)
        {key, fake}
      end)

    # Main LLM is the one keyed "llm"; fall back to first available LLM
    main_llm = Map.get(llms, "llm") || Map.values(llms) |> List.first()

    # Child LLM — look for "child_llm" or any key matching child_llm*.
    # When multiple child_llm keys exist (e.g., child_llm_l1, child_llm_l2),
    # combine their responses into a single FakeLLM in sorted key order.
    child_llm =
      llms
      |> Enum.filter(fn {k, _v} -> k != "llm" and String.starts_with?(k, "child_llm") end)
      |> Enum.sort_by(fn {k, _v} -> k end)
      |> case do
        [] ->
          nil

        [{_k, v}] ->
          v

        multi ->
          # Merge responses from all child LLMs into one FakeLLM with shared counter
          # so that child entities at different depths share the response sequence
          merged_responses =
            Enum.flat_map(multi, fn {_k, {_mod, state}} ->
              state.responses
            end)

          {FakeLLM, FakeLLM.new(merged_responses, record_inputs: true, shared: true)}
      end

    # Build circle config
    circle_setup = setup.circle
    gates = circle_setup[:gates] || []
    wards = circle_setup[:wards] || []
    circle_type = circle_setup[:type]
    circle_medium = circle_setup[:medium]
    circle_type_alt = circle_setup[:circle_type]

    # Set up filesystem for gates that need it
    filesystem = setup.filesystem || %{}
    gates = inject_filesystem_deps(gates, filesystem)

    has_any_medium = circle_type || circle_medium || circle_type_alt

    circle_attrs = %{gates: gates, wards: wards}

    circle_attrs =
      if circle_type, do: Map.put(circle_attrs, :type, circle_type), else: circle_attrs

    circle_attrs =
      if circle_medium, do: Map.put(circle_attrs, :medium, circle_medium), else: circle_attrs

    circle_attrs =
      if circle_type_alt,
        do: Map.put(circle_attrs, :circle_type, circle_type_alt),
        else: circle_attrs

    # Inject default medium "conversation" when no medium is specified,
    # UNLESS the test expects a medium-related error (MEDIUM-1 no-medium test).
    expects_medium_error =
      case tc.expect["error"] do
        err when is_binary(err) -> String.contains?(err, "medium")
        _ -> false
      end

    circle_attrs =
      if !has_any_medium and !expects_medium_error do
        Map.put(circle_attrs, :type, "conversation")
      else
        circle_attrs
      end

    # Build identity
    identity_setup = setup.identity || %{}
    identity = atomize_keys(identity_setup)

    # Build retry config
    retry = atomize_keys(setup.retry || %{})

    # Build folding config
    folding = atomize_keys(setup.folding || %{})

    # Attempt cantrip construction
    cantrip_result =
      if main_llm do
        cantrip_attrs = %{
          llm: main_llm,
          identity: identity,
          circle: circle_attrs,
          retry: retry,
          folding: folding
        }

        cantrip_attrs =
          if child_llm, do: Map.put(cantrip_attrs, :child_llm, child_llm), else: cantrip_attrs

        Cantrip.new(cantrip_attrs)
      else
        {:error, "cantrip requires an llm"}
      end

    cantrip =
      case cantrip_result do
        {:ok, c} -> c
        _ -> nil
      end

    %{
      setup: setup,
      cantrip: cantrip,
      cantrip_result: cantrip_result,
      llms: llms,
      results: [],
      threads: [],
      last_thread: nil,
      last_error: nil,
      entities: [],
      acp_responses: [],
      identity: identity,
      extracted_thread: nil
    }
  end

  @doc """
  Execute a list of actions against the context.
  """
  def execute(ctx, actions) when is_list(actions) do
    Enum.reduce(actions, ctx, &execute_single/2)
  end

  # ── Action dispatch ──────────────────────────────────────────────────

  defp execute_single(%{construct_cantrip: true}, ctx) do
    case ctx.cantrip_result do
      {:ok, _} -> ctx
      {:error, reason} -> %{ctx | last_error: reason}
    end
  end

  defp execute_single(%{cast: cast_cfg} = action, ctx) do
    ctx = execute_cast(ctx, cast_cfg)

    case action[:then] do
      nil -> ctx
      then_block -> execute_then(ctx, then_block)
    end
  end

  defp execute_single(%{acp_exchange: steps}, ctx) do
    execute_acp_exchange(ctx, steps)
  end

  defp execute_single(_action, ctx), do: ctx

  # ── Cast ─────────────────────────────────────────────────────────────

  defp execute_cast(ctx, cast_cfg) do
    intent = cast_cfg[:intent]
    llm_name = cast_cfg[:llm]

    # If a specific llm is named, build a new cantrip with that llm
    cantrip =
      if llm_name do
        llm_key = to_string(llm_name)

        case Map.get(ctx.llms, llm_key) do
          nil ->
            ctx.cantrip

          llm ->
            {:ok, c} =
              Cantrip.new(
                llm: llm,
                identity: Map.from_struct(ctx.cantrip.identity),
                circle: %{
                  gates: Map.values(ctx.cantrip.circle.gates),
                  wards: ctx.cantrip.circle.wards,
                  type: ctx.cantrip.circle.type
                },
                child_llm: ctx.cantrip.child_llm,
                retry: ctx.cantrip.retry,
                folding: ctx.cantrip.folding
              )

            c
        end
      else
        ctx.cantrip
      end

    case Cantrip.cast(cantrip, intent) do
      {:ok, result, next_cantrip, loom, meta} ->
        thread = build_thread(result, loom, meta, next_cantrip)

        %{
          ctx
          | cantrip: next_cantrip,
            results: ctx.results ++ [result],
            threads: ctx.threads ++ [thread],
            last_thread: thread,
            entities: ctx.entities ++ [meta.entity_id]
        }

      {:error, reason, next_cantrip} ->
        %{ctx | cantrip: next_cantrip, last_error: reason}
    end
  end

  # ── ACP exchange ─────────────────────────────────────────────────────

  defp execute_acp_exchange(ctx, steps) do
    # Create a conformance ACP runtime that wraps our cantrip
    cantrip = ctx.cantrip
    runtime = Cantrip.Conformance.ACPTestRuntime

    # Register the cantrip for the test runtime to use
    Process.put(:conformance_cantrip, cantrip)

    table = Cantrip.ACP.AgentHandler.new(runtime: runtime)

    {responses} =
      Enum.reduce(steps, {[]}, fn step, {resps} ->
        request = normalize_acp_request(step)
        {reply_list, response} = dispatch_acp_step(table, request)
        {resps ++ [%{response: response, all_replies: reply_list}]}
      end)

    # Extract LLM invocations from the runtime's sessions if needed
    llm_state = extract_llm_state_from_handler(table)

    ctx = %{ctx | acp_responses: responses}
    if llm_state, do: %{ctx | cantrip: %{ctx.cantrip | llm_state: llm_state}}, else: ctx
  end

  defp dispatch_acp_step(table, request) do
    id = request["id"]
    method = request["method"]
    params = request["params"] || %{}

    {typed_request, decode_ok} = decode_acp_request(method, params)

    case decode_ok do
      :ok ->
        result = Cantrip.ACP.AgentHandler.handle_request(typed_request, table)
        reply_list = build_reply_list(id, method, result, table)
        response = Enum.find(reply_list, fn r -> r["id"] == id end) || List.last(reply_list)
        {reply_list, response}

      {:error, reason} ->
        err = %{
          "jsonrpc" => "2.0",
          "id" => id,
          "error" => %{"code" => -32_602, "message" => reason}
        }

        {[err], err}
    end
  end

  defp decode_acp_request("initialize", params) do
    req = %ACP.InitializeRequest{
      protocol_version: params["protocolVersion"] || 1,
      client_capabilities: %ACP.ClientCapabilities{},
      client_info: params["clientInfo"]
    }

    {{:initialize, req}, :ok}
  end

  defp decode_acp_request("session/new", params) do
    req = %ACP.NewSessionRequest{
      cwd: params["cwd"] || System.tmp_dir!()
    }

    {{:new_session, req}, :ok}
  end

  defp decode_acp_request("session/prompt", params) do
    session_id = params["sessionId"]
    prompt_raw = params["prompt"] || params["content"] || params["text"] || params

    case extract_prompt_text(prompt_raw) do
      {:ok, text} ->
        req = %ACP.PromptRequest{
          session_id: session_id,
          prompt: [{:text, %ACP.TextContent{text: text}}]
        }

        {{:prompt, req}, :ok}

      {:error, reason} ->
        {nil, {:error, reason}}
    end
  end

  defp decode_acp_request(_method, _params) do
    {nil, {:error, "method not found"}}
  end

  defp extract_prompt_text(text) when is_binary(text) and text != "", do: {:ok, text}
  defp extract_prompt_text(%{"text" => text}) when is_binary(text), do: {:ok, text}
  defp extract_prompt_text(%{"content" => text}) when is_binary(text), do: {:ok, text}

  defp extract_prompt_text(%{"content" => blocks}) when is_list(blocks) do
    extract_prompt_text(blocks)
  end

  defp extract_prompt_text(%{"messages" => messages}) when is_list(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn msg ->
      case extract_prompt_text(msg) do
        {:ok, text} -> text
        _ -> nil
      end
    end)
    |> case do
      nil -> {:error, "bad prompt"}
      text -> {:ok, text}
    end
  end

  defp extract_prompt_text(blocks) when is_list(blocks) do
    Enum.find_value(blocks, {:error, "bad prompt"}, fn
      %{"text" => text} when is_binary(text) and text != "" -> {:ok, text}
      %{"content" => text} when is_binary(text) and text != "" -> {:ok, text}
      %{"value" => text} when is_binary(text) and text != "" -> {:ok, text}
      _ -> nil
    end)
  end

  defp extract_prompt_text(_), do: {:error, "bad prompt"}

  defp build_reply_list(id, _method, {:ok, %ACP.InitializeResponse{} = resp}, _table) do
    [
      %{
        "jsonrpc" => "2.0",
        "id" => id,
        "result" => %{
          "protocolVersion" => resp.protocol_version,
          "agentCapabilities" => %{
            "promptCapabilities" => %{"image" => false},
            "loadSession" => false
          }
        }
      }
    ]
  end

  defp build_reply_list(id, _method, {:ok, %ACP.NewSessionResponse{session_id: sid}}, _table) do
    [%{"jsonrpc" => "2.0", "id" => id, "result" => %{"sessionId" => sid}}]
  end

  defp build_reply_list(id, _method, {:ok, %ACP.PromptResponse{stop_reason: reason}}, table) do
    session_id = infer_handler_session_id(table)

    stop =
      case reason do
        :end_turn -> "end_turn"
        other -> to_string(other)
      end

    [
      %{
        "jsonrpc" => "2.0",
        "method" => "session/update",
        "params" => %{
          "sessionId" => session_id,
          "update" => %{
            "sessionUpdate" => "agent_message_chunk",
            "content" => %{"type" => "text", "text" => get_last_answer(table, session_id)}
          }
        }
      },
      %{
        "jsonrpc" => "2.0",
        "method" => "session/update",
        "params" => %{
          "sessionId" => session_id,
          "update" => %{"sessionUpdate" => "agent_message_end"}
        }
      },
      %{"jsonrpc" => "2.0", "id" => id, "result" => %{"stopReason" => stop}}
    ]
  end

  defp build_reply_list(id, _method, {:error, %ACP.Error{code: code, message: msg}}, _table) do
    [%{"jsonrpc" => "2.0", "id" => id, "error" => %{"code" => code, "message" => msg}}]
  end

  defp build_reply_list(id, _method, :ok, _table) do
    [%{"jsonrpc" => "2.0", "id" => id, "result" => %{}}]
  end

  defp infer_handler_session_id(table) do
    case :ets.match(table, {{:session, :"$1"}, :_}) do
      [[id] | _] -> id
      _ -> nil
    end
  end

  defp get_last_answer(table, session_id) do
    case :ets.lookup(table, {:last_answer, session_id}) do
      [{{:last_answer, _}, answer}] -> answer
      [] -> ""
    end
  end

  defp normalize_acp_request(step) when is_map(step) do
    # Ensure all keys are strings and nested maps are string-keyed
    Map.new(step, fn
      {k, v} when is_binary(k) -> {k, normalize_acp_value(v)}
      {k, v} when is_atom(k) -> {Atom.to_string(k), normalize_acp_value(v)}
      {k, v} -> {to_string(k), normalize_acp_value(v)}
    end)
  end

  defp normalize_acp_value(v) when is_map(v), do: normalize_acp_request(v)
  defp normalize_acp_value(v) when is_list(v), do: Enum.map(v, &normalize_acp_value/1)
  defp normalize_acp_value(v), do: v

  defp extract_llm_state_from_handler(table) do
    # Try to get LLM state from the first session in the ETS table
    case :ets.match(table, {{:session, :_}, :"$1"}) do
      [[%{cantrip: %Cantrip{llm_state: state}} | _]] -> state
      _ -> nil
    end
  end

  # ── Then block ───────────────────────────────────────────────────────

  defp execute_then(ctx, then_block) do
    ctx = handle_mutate_identity(ctx, then_block[:mutate_identity])
    ctx = handle_delete_turn(ctx, then_block[:delete_turn])
    ctx = handle_annotate_reward(ctx, then_block[:annotate_reward])
    ctx = handle_fork(ctx, then_block[:fork])
    ctx = handle_extract_thread(ctx, then_block[:extract_thread])
    ctx = handle_export_loom(ctx, then_block[:export_loom])
    ctx
  end

  defp handle_mutate_identity(ctx, nil), do: ctx

  defp handle_mutate_identity(ctx, _mutations) do
    %{ctx | last_error: "identity is immutable"}
  end

  defp handle_delete_turn(ctx, nil), do: ctx

  defp handle_delete_turn(ctx, _turn_index) do
    %{ctx | last_error: "loom is append-only"}
  end

  defp handle_annotate_reward(ctx, nil), do: ctx

  defp handle_annotate_reward(ctx, %{turn: turn_idx, reward: reward}) do
    thread = ctx.last_thread

    if thread do
      case Cantrip.annotate_reward(ctx.cantrip, thread.loom, turn_idx, reward) do
        {:ok, loom, _cantrip} ->
          updated_thread = %{thread | loom: loom, turns: loom.turns}

          %{
            ctx
            | threads: List.replace_at(ctx.threads, -1, updated_thread),
              last_thread: updated_thread
          }

        {:error, reason, _} ->
          %{ctx | last_error: reason}
      end
    else
      ctx
    end
  end

  defp handle_fork(ctx, nil), do: ctx

  defp handle_fork(ctx, fork_cfg) do
    from_turn = fork_cfg[:from_turn]
    llm_name = to_string(fork_cfg[:llm])
    intent = to_string(fork_cfg[:intent])

    fork_llm = Map.get(ctx.llms, llm_name)
    thread = ctx.last_thread

    if thread && fork_llm do
      case Cantrip.fork(ctx.cantrip, thread.loom, from_turn, %{
             intent: intent,
             llm: fork_llm
           }) do
        {:ok, result, next_cantrip, loom, meta} ->
          fork_thread = build_thread(result, loom, meta, next_cantrip)

          %{
            ctx
            | cantrip: next_cantrip,
              results: ctx.results ++ [result],
              threads: ctx.threads ++ [fork_thread],
              last_thread: fork_thread,
              entities: ctx.entities ++ [meta.entity_id]
          }

        {:error, reason, next_cantrip} ->
          %{ctx | cantrip: next_cantrip, last_error: reason}
      end
    else
      ctx
    end
  end

  defp handle_extract_thread(ctx, nil), do: ctx

  defp handle_extract_thread(ctx, _index) do
    thread = ctx.last_thread

    if thread do
      extracted = Cantrip.extract_thread(ctx.cantrip, thread.loom)
      %{ctx | extracted_thread: extracted}
    else
      ctx
    end
  end

  defp handle_export_loom(ctx, nil), do: ctx
  defp handle_export_loom(ctx, _opts), do: ctx

  # ── Helpers ──────────────────────────────────────────────────────────

  defp build_fake_llm(config) do
    responses = config.responses || []

    # Bug fix LLM-6: When raw_response + provider "mock_openai", normalize
    # the raw OpenAI response into cantrip format and prepend as a response.
    responses =
      case {config.raw_response, config.provider} do
        {raw, "mock_openai"} when is_map(raw) ->
          normalized = normalize_openai_response(raw)
          [normalized | responses]

        _ ->
          responses
      end

    # For code circles, translate JS code to Elixir and wrap as tool calls
    responses =
      if config.type == "code_circle" do
        Enum.map(responses, fn resp ->
          case resp[:code] do
            code when is_binary(code) ->
              elixir_code = js_to_elixir(code)
              other = Map.drop(resp, [:code])
              Map.merge(other, %{tool_calls: [%{gate: "elixir", args: %{code: elixir_code}}]})

            _ ->
              resp
          end
        end)
      else
        responses
      end

    # Handle per-response usage from config
    responses =
      case config.usage do
        usage when is_map(usage) ->
          Enum.map(responses, fn resp ->
            Map.put_new(resp, :usage, atomize_keys(usage))
          end)

        _ ->
          responses
      end

    # Bug fix LLM-5: Always record inputs in conformance tests
    {FakeLLM, FakeLLM.new(responses, record_inputs: true)}
  end

  # Normalize an OpenAI-format raw_response into cantrip's internal format
  defp normalize_openai_response(raw) do
    choices = raw["choices"] || []
    first_choice = List.first(choices) || %{}
    message = first_choice["message"] || %{}

    content = message["content"]
    usage_raw = raw["usage"]

    resp = %{}
    resp = if content, do: Map.put(resp, :content, content), else: resp

    resp =
      if is_map(usage_raw) do
        usage = %{
          prompt_tokens: usage_raw["prompt_tokens"],
          completion_tokens: usage_raw["completion_tokens"],
          total_tokens: usage_raw["total_tokens"]
        }

        Map.put(resp, :usage, usage)
      else
        resp
      end

    resp
  end

  defp build_thread(result, loom, meta, _cantrip) do
    # Use meta.turns for the count (excludes truncation marker turn),
    # but keep loom.turns for inspection
    %{
      result: result,
      loom: loom,
      turns: loom.turns,
      turn_count: Map.get(meta, :turns, length(loom.turns)),
      entity_id: meta.entity_id,
      terminated: Map.get(meta, :terminated, false),
      truncated: Map.get(meta, :truncated, false),
      meta: meta
    }
  end

  defp inject_filesystem_deps(gates, filesystem) when map_size(filesystem) == 0, do: gates

  defp inject_filesystem_deps(gates, filesystem) do
    tmp_dir = System.tmp_dir!()
    base = Path.join(tmp_dir, "cantrip_conformance_#{System.unique_integer([:positive])}")

    Enum.each(filesystem, fn {path, content} ->
      full = Path.join(base, path)
      File.mkdir_p!(Path.dirname(full))
      File.write!(full, content)
    end)

    Enum.map(gates, fn gate ->
      case gate do
        %{name: "read", dependencies: %{root: root}} ->
          %{gate | dependencies: %{root: Path.join(base, root)}}

        %{name: "read"} ->
          Map.put(gate, :dependencies, %{root: base})

        other ->
          other
      end
    end)
  end

  defp atomize_keys(map) when is_map(map) do
    Map.new(map, fn
      {k, v} when is_binary(k) -> {String.to_atom(k), v}
      {k, v} -> {k, v}
    end)
  end

  defp atomize_keys(other), do: other

  # ── JS → Elixir code translation for conformance tests ──────────────
  # tests.yaml uses JavaScript syntax for code-medium tests.
  # Each implementation translates to its native language.

  defp js_to_elixir(js) do
    js
    |> String.trim()
    |> translate_js_lines()
  end

  defp translate_js_lines(code) do
    # Step 1: Strip JS single-line comments
    code = Regex.replace(~r{//[^\n]*}, code, "")

    # Step 2: Handle try/catch blocks via brace-balanced extraction
    code = translate_try_catch(code)

    # Step 3: throw new Error('msg') → throw({:cantrip_error, "msg"})
    # Uses throw + :cantrip_error tag so the code medium catches it as a fatal error,
    # distinct from raise which is recoverable in code medium.
    code =
      Regex.replace(
        ~r/throw new Error\(['"](.+?)['"]\)\s*;?/,
        code,
        "throw({:cantrip_error, \"\\1\"})"
      )

    code =
      Regex.replace(~r/throw new Error\(([^)]+)\)\s*;?/, code, "throw({:cantrip_error, \\1})")

    # Step 4: var declarations → bare assignment
    code = Regex.replace(~r/\bvar\s+/, code, "")

    # Step 5: .join() before dot-call conversion
    # results.join(",") → Enum.join(results, ",")
    code = Regex.replace(~r/(\w+)\.join\(["']([^"']*?)["']\)/, code, "Enum.join(\\1, \"\\2\")")

    # Step 6: e.message → Exception.message(e)
    # Must run before dot-call conversion and before string concat
    # but after .join to avoid matching join's dot
    # Use a function replacement to skip already-translated Exception.message
    code =
      Regex.replace(~r/(\w+)\.message\b/, code, fn _, var ->
        if var == "Exception" do
          "Exception.message"
        else
          "Exception.message(#{var})"
        end
      end)

    # Step 7: Function calls → dot-calls for anonymous function bindings
    code = Regex.replace(~r/\bdone\(/, code, "done.(")
    code = Regex.replace(~r/\bcall_entity_batch\(/, code, "call_entity_batch.(")
    code = Regex.replace(~r/\bcall_entity\(/, code, "call_entity.(")

    # Step 8: JS object literals → Elixir maps
    # Any { followed by word+colon is a JS object literal → %{
    # This handles ({...}), [{...}], and standalone { key: val } in arrays
    code = Regex.replace(~r/\{(\s*\w+\s*:)/, code, "%{\\1")

    # Step 9: Single quotes → double quotes
    code = Regex.replace(~r/'([^']*?)'/, code, "\"\\1\"")

    # Step 10: Semicolons
    # Semicolons before newlines → just newline
    code = Regex.replace(~r/;\s*\n/, code, "\n")
    # Semicolons between statements on same line → newline
    code = Regex.replace(~r/;\s+(?=\S)/, code, "\n")
    # Trailing semicolons at end of string
    code = Regex.replace(~r/;\s*$/, code, "")
    # Any remaining semicolons (e.g., bare "done.(42);")
    code = Regex.replace(~r/;/, code, "")

    # Step 11: String concatenation: "str" + expr → "str" <> to_string(expr)
    # Handle complex RHS expressions: variables, function calls, strings
    code =
      Regex.replace(
        ~r/"([^"]*)"\s*\+\s*("[^"]*"|[^\s,;)\n]+)/,
        code,
        fn _, str, expr ->
          expr = String.trim(expr)

          if String.starts_with?(expr, "\"") do
            "\"#{str}\" <> #{expr}"
          else
            "\"#{str}\" <> to_string(#{expr})"
          end
        end
      )

    code
  end

  # Translate try { body } catch(e) { body } using brace-balanced extraction.
  # The non-greedy regex approach fails when try/catch bodies contain nested braces
  # (e.g., call_entity({ intent: "sub" }) inside a try block).
  defp translate_try_catch(code) do
    case Regex.run(~r/try\s*\{/, code, return: :index) do
      [{start, prefix_len}] ->
        before = String.slice(code, 0, start)
        after_open = String.slice(code, start + prefix_len, String.length(code))
        {try_body, after_try_close} = extract_brace_balanced(after_open)

        case Regex.run(~r/^\s*catch\s*\(\s*(\w+)\s*\)\s*\{/, after_try_close, capture: :all) do
          [catch_prefix, var_name] ->
            after_catch_open =
              String.slice(
                after_try_close,
                String.length(catch_prefix),
                String.length(after_try_close)
              )

            {catch_body, after_catch_close} = extract_brace_balanced(after_catch_open)

            try_elixir = translate_js_lines(String.trim(try_body))
            catch_elixir = translate_js_lines(String.trim(catch_body))

            # Wrap try body in Code.eval_string so that compile errors
            # (e.g., undefined variables) become runtime errors catchable by rescue.
            # Escape the try body for embedding in a string.
            escaped_try =
              try_elixir |> String.replace("\\", "\\\\") |> String.replace("\"", "\\\"")

            try_wrapper = "Code.eval_string(\"#{escaped_try}\", binding())"

            replacement =
              "try do\n#{try_wrapper}\nrescue\n#{var_name} in _ ->\n#{catch_elixir}\nend"

            # Recurse for any additional try/catch blocks
            translate_try_catch(before <> replacement <> after_catch_close)

          _ ->
            code
        end

      _ ->
        code
    end
  end

  # Extract content from inside braces, handling nested brace pairs.
  # Input starts AFTER the opening brace. Returns {body, rest_after_closing_brace}.
  defp extract_brace_balanced(str), do: do_extract_brace(str, 0, [])

  defp do_extract_brace(<<>>, _depth, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), ""}

  defp do_extract_brace(<<"}", rest::binary>>, 0, acc),
    do: {IO.iodata_to_binary(Enum.reverse(acc)), rest}

  defp do_extract_brace(<<"}", rest::binary>>, depth, acc),
    do: do_extract_brace(rest, depth - 1, ["}" | acc])

  defp do_extract_brace(<<"{", rest::binary>>, depth, acc),
    do: do_extract_brace(rest, depth + 1, ["{" | acc])

  defp do_extract_brace(<<c, rest::binary>>, depth, acc),
    do: do_extract_brace(rest, depth, [<<c>> | acc])
end

# Simple ACP test runtime that reads cantrip from process dictionary
defmodule Cantrip.Conformance.ACPTestRuntime do
  @moduledoc false
  @behaviour Cantrip.ACP.Runtime

  @impl true
  def new_session(_params) do
    cantrip = Process.get(:conformance_cantrip)
    {:ok, %{cantrip: cantrip, entity_pid: nil}}
  end

  @impl true
  def prompt(%{cantrip: cantrip, entity_pid: nil} = session, text) do
    case Cantrip.summon(cantrip, text) do
      {:ok, pid, result, next_cantrip, _loom, _meta} ->
        answer = if is_binary(result), do: result, else: to_string(result)
        answer = String.trim(answer)

        if answer == "",
          do: {:error, "empty agent response", %{session | cantrip: next_cantrip}},
          else: {:ok, answer, %{session | cantrip: next_cantrip, entity_pid: pid}}

      {:error, reason, next_cantrip} ->
        {:error, inspect(reason), %{session | cantrip: next_cantrip}}
    end
  end

  def prompt(%{entity_pid: pid} = session, text) when is_pid(pid) do
    case Cantrip.send(pid, text) do
      {:ok, result, next_cantrip, _loom, _meta} ->
        answer = if is_binary(result), do: result, else: to_string(result)
        answer = String.trim(answer)

        if answer == "",
          do: {:error, "empty agent response", %{session | cantrip: next_cantrip}},
          else: {:ok, answer, %{session | cantrip: next_cantrip}}

      {:error, reason} ->
        {:error, inspect(reason), session}
    end
  end
end
