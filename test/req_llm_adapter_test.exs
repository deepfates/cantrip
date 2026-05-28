defmodule ReqLLMAdapterTest do
  use ExUnit.Case, async: true

  alias Cantrip.LLMs.ReqLLM, as: Adapter
  alias Cantrip.Circle

  describe "module availability" do
    setup do
      Code.ensure_loaded?(Adapter)
      :ok
    end

    test "Cantrip.LLMs.ReqLLM is defined when req_llm is loaded" do
      assert Code.ensure_loaded?(Cantrip.LLMs.ReqLLM)
    end

    test "implements Cantrip.LLM behaviour" do
      behaviours =
        Adapter.__info__(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert Cantrip.LLM in behaviours
    end

    test "exports query/2" do
      assert function_exported?(Adapter, :query, 2)
    end
  end

  describe "query/2 error handling" do
    test "returns error tuple for missing model" do
      state = %{model: nil, timeout_ms: 1_000}
      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      assert {:error, error, _state} = Adapter.query(state, request)
      assert is_map(error)
      assert Map.has_key?(error, :message)
    end

    test "returns error tuple for invalid provider" do
      state = %{model: "nonexistent_provider:fake-model", timeout_ms: 1_000}
      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      assert {:error, error, _state} = Adapter.query(state, request)
      assert is_map(error)
      assert Map.has_key?(error, :message)
    end

    test "preserves state through error path" do
      state = %{model: "nonexistent_provider:fake", timeout_ms: 1_000}
      request = %{messages: [%{role: :user, content: "test"}], tools: []}

      {:error, _error, returned_state} = Adapter.query(state, request)

      assert returned_state.model == "nonexistent_provider:fake"
      assert returned_state.timeout_ms == 1_000
    end

    test "state defaults are applied" do
      state = %{model: "bad:model", timeout_ms: 500}
      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      {:error, _error, returned_state} = Adapter.query(state, request)

      assert returned_state.stream == false
      assert returned_state.temperature == nil
      assert returned_state.max_tokens == nil
    end
  end

  describe "query/2 with tools" do
    test "passes tools without crashing" do
      state = %{model: "bad:model", timeout_ms: 500}

      request = %{
        messages: [%{role: :user, content: "What is the weather?"}],
        tools: [
          %{
            name: "get_weather",
            description: "Get current weather",
            parameters: %{
              type: "object",
              properties: %{
                location: %{type: "string", description: "City name"}
              }
            }
          }
        ]
      }

      # This should error on the provider, not on tool normalization
      assert {:error, error, _state} = Adapter.query(state, request)
      assert is_map(error)
    end

    test "handles empty tools list" do
      state = %{model: "bad:model", timeout_ms: 500}
      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      assert {:error, _error, _state} = Adapter.query(state, request)
    end
  end

  describe "tool-call argument normalization" do
    test "malformed JSON arguments become error observations without invoking the gate" do
      circle =
        Circle.new(%{
          type: :conversation,
          gates: [:echo, :done],
          wards: [%{max_turns: 1}]
        })

      result =
        Cantrip.Gate.Executor.execute_tool_calls(
          circle,
          [
            %{
              id: "tc_bad",
              gate: "echo",
              args: %{},
              args_raw: ~s({"text":),
              args_decode_error: "unexpected end of input"
            }
          ],
          execute_gate: fn _circle, _gate, _args -> flunk("gate should not execute") end
        )

      assert [
               %{
                 gate: "echo",
                 tool_call_id: "tc_bad",
                 args: %{},
                 args_raw: ~s({"text":),
                 is_error: true,
                 result: result_text
               }
             ] = result.observations

      assert result_text =~ "malformed tool-call arguments"
      assert result_text =~ "unexpected end of input"
      refute result.terminated?
    end
  end

  describe "query/2 message normalization" do
    test "handles system, user, assistant, and tool roles" do
      state = %{model: "bad:model", timeout_ms: 500}

      request = %{
        messages: [
          %{role: :system, content: "You are helpful."},
          %{role: :user, content: "hi"},
          %{role: :assistant, content: "hello"},
          %{role: :tool, content: "result", tool_call_id: "tc_123"}
        ],
        tools: []
      }

      # Should not crash on message building -- error comes from provider
      assert {:error, _error, _state} = Adapter.query(state, request)
    end

    test "handles string-keyed messages" do
      state = %{model: "bad:model", timeout_ms: 500}

      request = %{
        messages: [
          %{"role" => "user", "content" => "hello"}
        ],
        tools: []
      }

      assert {:error, _error, _state} = Adapter.query(state, request)
    end

    test "Anthropic provider encoding preserves multiple system messages" do
      context =
        ReqLLM.Context.new([
          ReqLLM.Context.system("first instruction"),
          ReqLLM.Context.system("second instruction"),
          ReqLLM.Context.user("hello")
        ])

      request = ReqLLM.Providers.Anthropic.Context.encode_request(context, "claude-test")

      assert request.system == [
               %{type: "text", text: "first instruction"},
               %{type: "text", text: "second instruction"}
             ]

      assert request.messages == [%{role: "user", content: "hello"}]
    end

    test "Gemini provider encoding preserves multiple system messages" do
      context =
        ReqLLM.Context.new([
          ReqLLM.Context.system("first instruction"),
          ReqLLM.Context.system("second instruction"),
          ReqLLM.Context.user("hello")
        ])

      {:ok, request} =
        ReqLLM.Providers.Google.prepare_request(:chat, "google:gemini-2.5-flash", context,
          api_key: "test"
        )

      request = ReqLLM.Providers.Google.encode_body(request)
      body = Jason.decode!(request.body)

      assert body["systemInstruction"] == %{
               "parts" => [%{"text" => "first instruction\n\nsecond instruction"}]
             }

      assert body["contents"] == [%{"role" => "user", "parts" => [%{"text" => "hello"}]}]
    end
  end

  describe "query/2 streaming mode" do
    test "stream option is passed through state" do
      state = %{model: "bad:model", stream: true, timeout_ms: 500}
      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      # Should error on provider but exercise the streaming path
      assert {:error, error, returned_state} = Adapter.query(state, request)
      assert returned_state.stream == true
      assert is_map(error)
    end

    test "stream_query stays wired to process_stream for reconstructed tool calls" do
      source = File.read!("lib/cantrip/llms/req_llm.ex")

      assert source =~ "ReqLLM.StreamResponse.process_stream(sr, on_result: on_result)"
      refute source =~ "ReqLLM.StreamResponse.tokens(sr)"
      refute source =~ "ReqLLM.StreamResponse.tool_calls(sr)"
    end

    test "process_stream reconstructs streamed Anthropic tool calls while emitting text deltas" do
      test_pid = self()

      chunks = [
        ReqLLM.StreamChunk.text("I'll "),
        ReqLLM.StreamChunk.text("check."),
        ReqLLM.StreamChunk.tool_call("list_dir", %{}, %{id: "toolu_01", index: 0}),
        ReqLLM.StreamChunk.meta(%{
          tool_call_args: %{index: 0, fragment: ~s({"path":"."})}
        }),
        ReqLLM.StreamChunk.meta(%{finish_reason: :tool_calls})
      ]

      {:ok, metadata_handle} =
        ReqLLM.StreamResponse.MetadataHandle.start_link(fn ->
          %{usage: %{input_tokens: 11, output_tokens: 7}, finish_reason: :tool_calls}
        end)

      stream_response = %ReqLLM.StreamResponse{
        stream: chunks,
        metadata_handle: metadata_handle,
        cancel: fn -> :ok end,
        model: LLMDB.Model.new!(%{provider: :anthropic, id: "claude-test"}),
        context: ReqLLM.Context.new([ReqLLM.Context.user("list one file")])
      }

      assert {:ok, response} =
               ReqLLM.StreamResponse.process_stream(stream_response,
                 on_result: fn delta -> send(test_pid, {:text_delta, delta}) end
               )

      assert_receive {:text_delta, "I'll "}
      assert_receive {:text_delta, "check."}

      assert ReqLLM.Response.text(response) == "I'll check."
      assert response.finish_reason == :tool_calls
      assert response.usage.input_tokens == 11
      assert response.usage.output_tokens == 7

      assert [
               %ReqLLM.ToolCall{
                 id: "toolu_01",
                 function: %{name: "list_dir", arguments: ~s({"path":"."})}
               }
             ] = ReqLLM.Response.tool_calls(response)
    end
  end

  describe "Cantrip.LLM contract" do
    test "query returns {:ok, response, state} or {:error, reason, state}" do
      state = %{model: "bad:model", timeout_ms: 500}
      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      result = Adapter.query(state, request)

      case result do
        {:ok, response, _state} ->
          # If somehow OK, validate response shape
          assert is_map(response)
          assert Map.has_key?(response, :content) or Map.has_key?(response, :tool_calls)

        {:error, reason, returned_state} ->
          assert is_map(reason)
          assert is_map(returned_state)
      end
    end

    test "works through Cantrip.LLM.request/3 dispatcher" do
      state = %{model: "bad:model", timeout_ms: 500}
      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      result = Cantrip.LLM.request(Cantrip.LLMs.ReqLLM, state, request)

      assert {:error, _reason, _state} = result
    end
  end

  describe "state normalization" do
    test "keyword list state is accepted" do
      state = [model: "bad:model", timeout_ms: 500]
      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      assert {:error, _error, returned_state} = Adapter.query(state, request)
      assert returned_state.model == "bad:model"
    end

    test "defaults timeout_ms to 60_000" do
      state = %{model: "bad:model"}
      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      {:error, _error, returned_state} = Adapter.query(state, request)
      assert returned_state.timeout_ms == 60_000
    end

    test "custom options are preserved" do
      state = %{
        model: "bad:model",
        temperature: 0.7,
        max_tokens: 1024,
        stream: true,
        timeout_ms: 5_000
      }

      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      {:error, _error, returned_state} = Adapter.query(state, request)
      assert returned_state.temperature == 0.7
      assert returned_state.max_tokens == 1024
      assert returned_state.stream == true
      assert returned_state.timeout_ms == 5_000
    end

    test "base_url and api_key are preserved through state (LLM-3)" do
      state = %{
        model: "bad:model",
        base_url: "http://localhost:11434/v1",
        api_key: "sk-test-key"
      }

      request = %{messages: [%{role: :user, content: "hi"}], tools: []}

      {:error, _error, returned_state} = Adapter.query(state, request)
      assert returned_state.base_url == "http://localhost:11434/v1"
      assert returned_state.api_key == "sk-test-key"
    end
  end
end
