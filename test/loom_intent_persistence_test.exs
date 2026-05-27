defmodule Cantrip.LoomIntentPersistenceTest do
  @moduledoc """
  User intents — the prompts a human (or parent) sends an entity — must
  be part of the loom. Turns are narrowly entity utterance ↔ circle
  observation; intents are a different shape and live on the loom's event
  log with `type: :intent`, with a cached `loom.intents` projection for
  ergonomic access. The
  `Loom.transcript/1` helper composes them with entity turns into the
  interleaved conversation view a long-lived persistent entity needs.

  This pins:
    * intents persist via `Loom.append_intent/3`
    * `loom.intents` is populated alongside `loom.turns`
    * `loom.turns` is unaffected (LOOP-1 contract preserved)
    * intents survive cross-session rehydration from durable storage
    * `Loom.transcript/1` interleaves intents and entity turns in order
  """

  use ExUnit.Case, async: false

  alias Cantrip.{Familiar, FakeLLM, Loom}

  describe "single-session: send_intent records the intent on the loom" do
    test "loom.intents contains the intent; loom.turns is unaffected" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.("ok")|}])}
      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, pid} = Cantrip.summon(cantrip)

      try do
        {:ok, _result, _next, loom, _meta} = Cantrip.send(pid, "hello there")

        assert [intent] = loom.intents
        assert get_in(intent, [:utterance, :content]) == "hello there"
        assert intent.role == "intent"

        # `loom.turns` keeps its LOOP-1 contract: only entity-side turns.
        assert Enum.all?(loom.turns, fn t -> Map.get(t, :role) == "turn" end),
               "loom.turns must not contain intent records"
      after
        Process.exit(pid, :normal)
      end
    end

    test "multiple sends produce multiple intent records in order" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s|done.("first")|},
           %{code: ~s|done.("second")|}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, pid} = Cantrip.summon(cantrip)

      try do
        {:ok, _, _, _, _} = Cantrip.send(pid, "alpha")
        {:ok, _, _, loom, _} = Cantrip.send(pid, "beta")

        assert Enum.map(loom.intents, &get_in(&1, [:utterance, :content])) == ["alpha", "beta"]
      after
        Process.exit(pid, :normal)
      end
    end
  end

  describe "first-cast: an intent provided at construction is recorded" do
    test "Cantrip.cast records the intent on the loom" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s|done.("ok")|}])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      {:ok, _result, _next, loom, _meta} = Cantrip.cast(cantrip, "do the thing")

      assert [intent] = loom.intents
      assert get_in(intent, [:utterance, :content]) == "do the thing"
    end
  end

  describe "cross-session: intents survive rehydration from durable storage" do
    test "fresh Loom against the same JSONL path projects prior intents" do
      tmp =
        Path.join(System.tmp_dir!(), "loom_intent_jsonl_#{System.unique_integer([:positive])}")

      loom_path = Path.join(tmp, "familiar.jsonl")
      File.mkdir_p!(tmp)

      try do
        llm_1 = {FakeLLM, FakeLLM.new([%{code: ~s|done.("session-1 reply")|}])}
        {:ok, c1} = Familiar.new(llm: llm_1, loom_path: loom_path, root: tmp)
        {:ok, pid1} = Cantrip.summon(c1)
        {:ok, _, _, _, _} = Cantrip.send(pid1, "remember this please")
        Process.exit(pid1, :normal)

        rehydrated = Loom.new(c1.identity, storage: {:jsonl, loom_path})

        contents = Enum.map(rehydrated.intents, &get_in(&1, [:utterance, :content]))

        assert "remember this please" in contents,
               "expected prior intent on rehydrated loom; got: #{inspect(contents)}"
      after
        File.rm_rf!(tmp)
      end
    end
  end

  describe "transcript: interleaved view of intents and entity turns" do
    test "transcript order survives cross-session rehydration" do
      # Regression for a Copilot-caught bug: `transcript/1` previously
      # sorted by `event.sequence`, but storage adapters strip the
      # event wrapper's `:sequence` on persistence (they only round-trip
      # the typed payload). After rehydration every event collapsed to
      # sequence 0, and only stable-sort accident kept the order
      # correct. This test fails if `transcript/1` reintroduces a sort
      # by event sequence after a real round-trip through JSONL.
      tmp =
        Path.join(
          System.tmp_dir!(),
          "loom_transcript_order_#{System.unique_integer([:positive])}"
        )

      loom_path = Path.join(tmp, "familiar.jsonl")
      File.mkdir_p!(tmp)

      try do
        llm =
          {FakeLLM,
           FakeLLM.new([
             %{code: ~s|done.("first reply")|},
             %{code: ~s|done.("second reply")|}
           ])}

        {:ok, c1} = Familiar.new(llm: llm, loom_path: loom_path, root: tmp)
        {:ok, pid} = Cantrip.summon(c1)
        {:ok, _, _, _, _} = Cantrip.send(pid, "first")
        {:ok, _, _, _, _} = Cantrip.send(pid, "second")
        Process.exit(pid, :normal)

        rehydrated = Loom.new(c1.identity, storage: {:jsonl, loom_path})

        substantive_roles =
          rehydrated
          |> Loom.transcript()
          |> Enum.reject(fn r ->
            r.role == "turn" and Map.get(r, :utterance) in [nil, %{}]
          end)
          |> Enum.map(& &1.role)

        assert Enum.take(substantive_roles, 4) == ["intent", "turn", "intent", "turn"],
               "post-rehydration transcript order broken; got: #{inspect(substantive_roles)}"
      after
        File.rm_rf!(tmp)
      end
    end

    test "intents appear before the entity turns they provoked, in order" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s|done.("first reply")|},
           %{code: ~s|done.("second reply")|}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, pid} = Cantrip.summon(cantrip)

      try do
        {:ok, _, _, _, _} = Cantrip.send(pid, "alpha")
        {:ok, _, _, loom, _} = Cantrip.send(pid, "beta")

        roles = loom |> Loom.transcript() |> Enum.map(& &1.role)

        # Each send: an intent record, then an entity turn (the LLM's response).
        # We allow extra entity turns (continuation markers, etc.) but the
        # order of substantive records must be intent, turn, intent, turn.
        substantive_roles =
          loom
          |> Loom.transcript()
          |> Enum.reject(fn r ->
            r.role == "turn" and Map.get(r, :utterance) in [nil, %{}]
          end)
          |> Enum.map(& &1.role)

        assert Enum.take(substantive_roles, 4) == ["intent", "turn", "intent", "turn"],
               "got transcript roles: #{inspect(roles)}"
      after
        Process.exit(pid, :normal)
      end
    end
  end
end
