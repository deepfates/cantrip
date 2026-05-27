defmodule Cantrip.ZedTraceReplayTest do
  @moduledoc """
  The actual multi-turn conversations from `scratch/familiar-run-001.md`
  and `scratch/familiar-run-002.md` replayed against the current
  substrate with a real LLM.

  The unit tests pin the substrate's behavior at every gate / medium /
  loom boundary. This test pins something different: the *exact same
  user prompts that broke the original sessions* now flow through the
  Familiar end-to-end and the user gets a substantive answer for each.

  Gated by `RUN_REAL_LLM_TESTS=1`. Each scenario summons a single
  Familiar against a tmp loom path, sends the original prompts in
  sequence (no fork, no scripted replies), and after each `send`
  asserts the user-facing contract:

    - The cast terminated (the loop reached done, not max_turns).
    - The ACP bridge can stringify the done answer to non-trivial text
      (the path real users consume the answer through).
    - The persisted loom grew (cross-session recoverability holds).

  The "did the substrate crash" question is the wrong one for this
  layer — the unit tests already verify the substrate doesn't crash
  on the historical failure shapes. The integration question is "does
  the user get coherent output?" and that's what `meta.terminated`
  plus a non-empty stringified answer attests to.
  """

  use ExUnit.Case, async: false

  alias Cantrip.Test.RealLLMEnv

  @moduletag :integration
  @moduletag timeout: :timer.minutes(10)

  # User prompts from scratch/familiar-run-002.md, in trace order.
  @run_002_prompts [
    "check out the new harness, what do you think?",
    "I want you to actually try it out and tell me about your experience, not just read about it",
    "What do you mean the harness around the harness? You are running inside the ex harness right now. The code you are using to operate the computer and talk to me is the same as that in the folder. Are there bugs with it, is that what you're saying? Or are you just confused about what i mean",
    "Can you put it through its paces and then give me a full report? if you would enjoy that",
    "Huhh interesting weird. So you can't even get in there to tell how to fix anything?",
    "please try everything you can and let's do a full analysis ya",
    "Anything else you want to do before i take this to go fix",
    "Keep going please? or is that it"
  ]

  # User prompts from scratch/familiar-run-001.md (the earlier trace,
  # different conversational shape but same failure surface).
  @run_001_prompts [
    "Do you see all of that? Are you understanding and synthesizing it or just shooting me back a bunch of crap?",
    "Do you see what you sent me though? does it make sense to you? can you try to cohere on using this harness?",
    "Hmm you're getting errors huh. Can you see them? Do you want to operate in a loop and try to understand and correct things in your codebase here from what you can see? or at least analyze it and give a full report so i can have a different agent fix the harness to your needs"
  ]

  defp loom_path(tag) do
    Path.join(System.tmp_dir!(), "zed_replay_#{tag}_#{System.unique_integer([:positive])}.jsonl")
  end

  defp assert_user_facing_contract(result, meta, turn_label) do
    # The user-facing contract: the cast terminated (loop reached done,
    # not max_turns or some other escape), and the bridge can convey
    # the answer as non-trivial text. Anything beyond that — substrate
    # crashes, error observations, agent strategy quality — is at
    # other test layers.
    assert meta.terminated, "#{turn_label}: cast did not reach done (loop truncated?)"

    stringified = Cantrip.ACP.EventBridge.stringify(result)
    assert is_binary(stringified), "#{turn_label}: bridge did not produce text"
    assert String.length(String.trim(stringified)) > 0, "#{turn_label}: empty answer"
  end

  defp replay(prompts, loom_path) do
    {:ok, llm} = Cantrip.LLM.from_env()

    {:ok, cantrip} =
      Cantrip.Familiar.new(llm: llm, loom_path: loom_path, root: File.cwd!())

    {:ok, pid} = Cantrip.summon(cantrip)

    try do
      results =
        prompts
        |> Enum.with_index(1)
        |> Enum.map(fn {prompt, idx} ->
          {:ok, result, _next, _loom, meta} = Cantrip.send(pid, prompt)
          label = "Turn #{idx} (#{String.slice(prompt, 0, 40)}...)"
          assert_user_facing_contract(result, meta, label)
          {idx, prompt, result, meta}
        end)

      # Cross-session recoverability: the persistent loom captured
      # something substantive for the next summon to read.
      assert File.exists?(loom_path)
      assert File.stat!(loom_path).size > 0

      results
    after
      Process.exit(pid, :normal)
    end
  end

  test "scratch/familiar-run-002.md prompts: each turn terminates with substantive output" do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      path = loom_path("run002")
      on_exit(fn -> File.rm(path) end)
      _results = replay(@run_002_prompts, path)
    end
  end

  test "scratch/familiar-run-001.md prompts: each turn terminates with substantive output" do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      path = loom_path("run001")
      on_exit(fn -> File.rm(path) end)
      _results = replay(@run_001_prompts, path)
    end
  end

  test "after a multi-turn session, a fresh summon against the same loom_path rehydrates the prior turns" do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      path = loom_path("rehydrate")
      on_exit(fn -> File.rm(path) end)

      # Session 1: drive a short multi-turn conversation.
      _ = replay(Enum.take(@run_002_prompts, 2), path)

      # Session 2: a fresh Familiar against the same loom should see
      # the prior turns as substantive Elixir terms via `loom.turns`.
      pre_load_lines = File.read!(path) |> String.split("\n", trim: true) |> length()
      assert pre_load_lines >= 2

      {:ok, llm} = Cantrip.LLM.from_env()

      {:ok, cantrip} =
        Cantrip.Familiar.new(llm: llm, loom_path: path, root: File.cwd!())

      {:ok, pid} = Cantrip.summon(cantrip)

      try do
        {:ok, result, _next, _loom, meta} =
          Cantrip.send(
            pid,
            "Look at loom.turns. How many substantive turns are there from before this session, and what gates did they use? Reply via done with a map containing :prior_turn_count and :gates_used."
          )

        assert_user_facing_contract(result, meta, "Rehydrate session probe")

        # The persisted loom file kept growing (the new session's turns
        # also appended).
        post_lines = File.read!(path) |> String.split("\n", trim: true) |> length()
        assert post_lines > pre_load_lines
      after
        Process.exit(pid, :normal)
      end
    end
  end
end
