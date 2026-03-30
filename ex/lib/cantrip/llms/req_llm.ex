if Code.ensure_loaded?(ReqLLM) do
  defmodule Cantrip.LLMs.ReqLLM do
    @moduledoc """
    LLM adapter backed by the ReqLLM hex package.

    ReqLLM provides a unified interface to 18+ LLM providers (Anthropic, OpenAI,
    Google, Groq, xAI, etc.) via a single canonical data model.  This adapter
    bridges ReqLLM's `generate_text/3` and `stream_text/3` into the
    `Cantrip.LLM` behaviour.

    ## State

    The adapter expects a state map with:

      * `:model` -- a ReqLLM model string, e.g. `"anthropic:claude-haiku-4-5"` or
        `"openai:gpt-4o"`.  The provider prefix tells ReqLLM which API to target.
      * `:stream` -- (optional, default `false`) whether to use streaming.
      * `:temperature` -- (optional) sampling temperature.
      * `:max_tokens` -- (optional) maximum tokens to generate.
      * `:timeout_ms` -- (optional, default 60 000) receive timeout in ms.

    API keys are resolved by ReqLLM's built-in `ReqLLM.Keys` subsystem (env vars,
    `.env` files, etc.).

    ## Example

        state = %{model: "anthropic:claude-haiku-4-5"}
        request = %{
          messages: [%{role: :user, content: "Hello!"}],
          tools: []
        }
        {:ok, response, next_state} = Cantrip.LLMs.ReqLLM.query(state, request)
    """

    alias Cantrip.LLMs.Helpers

    @behaviour Cantrip.LLM

    @default_timeout_ms 60_000

    @impl true
    def query(state, request) do
      state = normalize_state(state)
      model = state.model
      context = build_context(request)
      opts = build_opts(state, request)
      stream_to = Map.get(request, :stream_to)

      result =
        if state.stream do
          stream_query(model, context, opts, stream_to)
        else
          sync_query(model, context, opts)
        end

      case result do
        {:ok, response} ->
          {:ok, response, state}

        {:error, reason} ->
          {:error, normalize_error(reason), state}
      end
    rescue
      e ->
        {:error, %{status: nil, message: Exception.message(e)}, normalize_state(state)}
    end

    # -- Sync path --

    defp sync_query(model, context, opts) do
      case ReqLLM.generate_text(model, context, opts) do
        {:ok, %ReqLLM.Response{} = response} ->
          {:ok, normalize_response(response)}

        {:error, reason} ->
          {:error, reason}
      end
    end

    # -- Streaming path --

    defp stream_query(model, context, opts, stream_to) do
      case ReqLLM.stream_text(model, context, opts) do
        {:ok, %ReqLLM.StreamResponse{} = sr} ->
          # Stream tokens, emitting deltas to stream_to as they arrive
          text =
            sr
            |> ReqLLM.StreamResponse.tokens()
            |> Enum.reduce("", fn chunk, acc ->
              if is_pid(stream_to) and is_binary(chunk) and chunk != "" do
                send(stream_to, {:cantrip_event, {:text_delta, chunk}})
              end

              acc <> chunk
            end)

          text = if text == "", do: nil, else: text

          # Get metadata after stream is consumed
          usage = ReqLLM.StreamResponse.usage(sr) || %{}
          tool_calls = ReqLLM.StreamResponse.tool_calls(sr)

          {:ok,
           %{
             content: text,
             code: Helpers.extract_code(text),
             tool_calls: normalize_tool_calls(tool_calls || []),
             usage: normalize_usage(usage),
             raw_response: sr
           }}

        # Legacy Response path (some providers may still return this)
        {:ok, %ReqLLM.Response{} = response} ->
          text = ReqLLM.Response.text(response)

          if is_pid(stream_to) and is_binary(text) and text != "" do
            send(stream_to, {:cantrip_event, {:text_delta, text}})
          end

          usage = ReqLLM.Response.usage(response) || %{}

          {:ok,
           %{
             content: if(is_nil(text) or text == "", do: nil, else: text),
             code: Helpers.extract_code(text),
             tool_calls: normalize_tool_calls(ReqLLM.Response.tool_calls(response)),
             usage: normalize_usage(usage),
             raw_response: response
           }}

        {:error, reason} ->
          {:error, reason}
      end
    end

    # -- Context building --

    defp build_context(%{messages: messages}) when is_list(messages) and messages != [] do
      parts =
        Enum.map(messages, fn msg ->
          msg = Helpers.normalize_message(msg)
          role = msg[:role]
          content = to_string(msg[:content] || "")

          case role do
            :system -> ReqLLM.Context.system(content)
            :assistant -> ReqLLM.Context.assistant(content)
            :tool -> ReqLLM.Context.user("[tool_result] #{content}")
            _ -> ReqLLM.Context.user(content)
          end
        end)

      ReqLLM.Context.new(parts)
    end

    defp build_context(_request), do: ReqLLM.Context.new([ReqLLM.Context.user("")])

    # -- Options --

    defp build_opts(state, request) do
      tools = Map.get(request, :tools, [])

      opts = []
      opts = if state.temperature, do: [{:temperature, state.temperature} | opts], else: opts
      opts = if state.max_tokens, do: [{:max_tokens, state.max_tokens} | opts], else: opts
      opts = if state.timeout_ms, do: [{:receive_timeout, state.timeout_ms} | opts], else: opts
      opts = if state.base_url, do: [{:base_url, state.base_url} | opts], else: opts
      opts = if state.api_key, do: [{:api_key, state.api_key} | opts], else: opts

      tool_specs = normalize_tools(tools)

      if tool_specs != [] do
        [{:tools, tool_specs} | opts]
      else
        opts
      end
    end

    defp normalize_tools(tools) do
      Enum.map(tools, fn tool ->
        tool = Helpers.normalize_tool_spec(tool)

        ReqLLM.tool(
          name: tool[:name],
          description: tool[:description] || "",
          parameter_schema: tool[:parameters] || %{type: "object", properties: %{}},
          callback: fn args -> {:ok, inspect(args)} end
        )
      end)
    end

    # -- Response normalization --

    defp normalize_response(%ReqLLM.Response{} = response) do
      text = ReqLLM.Response.text(response)
      tool_calls = ReqLLM.Response.tool_calls(response)
      usage = ReqLLM.Response.usage(response) || %{}

      %{
        content: if(is_nil(text) or text == "", do: nil, else: text),
        code: Helpers.extract_code(text),
        tool_calls: normalize_tool_calls(tool_calls),
        usage: normalize_usage(usage),
        raw_response: response
      }
    end

    defp normalize_tool_calls(tool_calls) when is_list(tool_calls) do
      Enum.map(tool_calls, fn tc ->
        tc_map = if is_struct(tc), do: Map.from_struct(tc), else: tc
        func = tc_map[:function] || tc_map["function"] || %{}

        args_raw = func[:arguments] || func["arguments"] || %{}

        args =
          cond do
            is_map(args_raw) -> args_raw
            is_binary(args_raw) ->
              case Jason.decode(args_raw) do
                {:ok, map} when is_map(map) -> map
                _ -> %{}
              end
            true -> %{}
          end

        %{
          id: tc_map[:id] || tc_map["id"],
          gate: func[:name] || func["name"],
          args: args
        }
      end)
    end

    defp normalize_tool_calls(_), do: []

    defp normalize_usage(usage) when is_map(usage) do
      %{
        prompt_tokens:
          Map.get(usage, :input_tokens) || Map.get(usage, "input_tokens") ||
            Map.get(usage, :prompt_tokens) || Map.get(usage, "prompt_tokens") || 0,
        completion_tokens:
          Map.get(usage, :output_tokens) || Map.get(usage, "output_tokens") ||
            Map.get(usage, :completion_tokens) || Map.get(usage, "completion_tokens") || 0
      }
    end

    defp normalize_usage(_), do: %{prompt_tokens: 0, completion_tokens: 0}

    # -- Error normalization --

    defp normalize_error(%{status: status, message: message}) do
      %{status: status, message: message}
    end

    defp normalize_error(%{status: status, body: body}) do
      %{status: status, message: Helpers.extract_error(body)}
    end

    defp normalize_error(reason) when is_binary(reason) do
      %{status: nil, message: reason}
    end

    defp normalize_error(%{__exception__: true} = exception) do
      %{status: nil, message: Exception.message(exception)}
    end

    defp normalize_error(reason) do
      %{status: nil, message: inspect(reason)}
    end

    # -- State --

    defp normalize_state(state) do
      state = Map.new(state)

      %{
        model: Map.get(state, :model),
        stream: Map.get(state, :stream, false),
        temperature: Map.get(state, :temperature),
        max_tokens: Map.get(state, :max_tokens),
        timeout_ms: Map.get(state, :timeout_ms, @default_timeout_ms),
        base_url: Map.get(state, :base_url),
        api_key: Map.get(state, :api_key)
      }
    end
  end
end
