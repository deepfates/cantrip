defmodule LiveAnthropicTest do
  @moduledoc """
  Regression coverage for the v1-prep bugs (system-message coalesce and
  streaming tool-call extraction) against a real LLM.

  Existing live tests (`test/real_llm_*`, `test/familiar_real_llm_*`,
  `test/zed_trace_replay_test.exs`) cover the sync tool loop, error
  recovery, and multi-turn replay paths. They do not exercise:

  - **Streaming + tool calls.** The 65d5e1c bug dropped every streamed
    tool call because the adapter consumed the chunk stream twice. The
    bug shipped invisibly behind the c994878 system-message 400.
  - **The Anthropic system-message coalesce.** Two consecutive `:system`
    messages must merge into one before they hit ReqLLM's Anthropic
    encoder, otherwise the API returns 400.

  Both of these only surfaced when driven live. This module is the CI
  hook that catches that class of regression.

  Gating matches the rest of the live-test suite: `RUN_REAL_LLM_TESTS=1`
  plus the usual CANTRIP_MODEL / API key env. With neither set every
  test in this module returns `:ok` so default `mix test` stays free.
  """

  use ExUnit.Case, async: false

  alias Cantrip.Test.RealLLMEnv

  @moduletag :integration
  @moduletag timeout: :timer.seconds(60)

  describe "Familiar against a real LLM" do
    test "code medium completes a list_dir → done turn (sync)" do
      if not RealLLMEnv.enabled?() do
        :ok
      else
        {:ok, llm} = Cantrip.LLM.from_env(%{stream: "false"})
        value = assert_live_ok(drive_code_medium(llm))

        assert is_binary(value) and String.length(value) > 0,
               "expected a filename string from done, got: #{inspect(value)}"
      end
    end

    test "code medium completes a list_dir → done turn (streaming, regression for 65d5e1c)" do
      if not RealLLMEnv.enabled?() do
        :ok
      else
        {:ok, llm} = Cantrip.LLM.from_env(%{stream: "true"})
        value = assert_live_ok(drive_code_medium(llm))

        assert is_binary(value) and String.length(value) > 0,
               "streaming dropped the tool call — got prose or empty instead of a filename. " <>
                 "this is the exact shape of the 65d5e1c bug: #{inspect(value)}"
      end
    end
  end

  describe "Conversation medium with tool-calling" do
    test "model calls done and the result returns through cast" do
      if not RealLLMEnv.enabled?() do
        :ok
      else
        {:ok, llm} = Cantrip.LLM.from_env(%{stream: "false"})

        {:ok, cantrip} =
          Cantrip.new(
            llm: llm,
            identity: %{
              system_prompt:
                "You are a friendly assistant. When you have an answer, call the done tool with your reply."
            },
            circle: %{
              type: :conversation,
              gates: [:done],
              wards: [%{max_turns: 3}]
            }
          )

        answer = assert_live_ok(Cantrip.cast(cantrip, "Say hi in one short sentence."))

        assert is_binary(answer) and String.length(answer) > 0,
               "conversation medium dropped the tool-call result: #{inspect(answer)}"
      end
    end
  end

  # === Helpers ===

  defp drive_code_medium(llm) do
    root = File.cwd!()

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        identity: %{
          system_prompt:
            "You are a Familiar. Emit Elixir code that uses the available gates. Call done with the final value."
        },
        circle: %{
          type: :code,
          gates: [:done, %{name: "list_dir", dependencies: %{root: root}}],
          wards: [
            %{max_turns: 3},
            %{sandbox: :port},
            %{code_eval_timeout_ms: 30_000}
          ]
        }
      )

    Cantrip.cast(cantrip, "list one file in this repo and report its name")
  end

  defp assert_live_ok({:ok, value, _cantrip, _loom, _meta}), do: value

  defp assert_live_ok({:error, reason, _cantrip}) do
    flunk("live cantrip failed: #{inspect(reason)}")
  end

  defp assert_live_ok(other), do: flunk("unexpected live result: #{inspect(other)}")
end
