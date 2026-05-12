defmodule Cantrip.FamiliarRealLLMIntegrationTest do
  @moduledoc """
  End-to-end checks for the production `Cantrip.Familiar` against a real
  LLM. Gated by env vars (RUN_REAL_LLM_TESTS=1, plus CANTRIP_MODEL /
  CANTRIP_API_KEY / CANTRIP_BASE_URL) so default CI stays fast and the
  test costs nothing unless explicitly opted in.

  These pin the contract that motivated the SpawnFn / Gate.spec changes:
  a real LLM driving the Familiar must be able to delegate filesystem
  work to children with `gates: ["read_file"]` and see real file content
  come back, not crashes or empty strings.
  """

  use ExUnit.Case, async: false

  alias Cantrip.Test.RealLLMEnv

  @moduletag :integration

  setup do
    dir = Path.join(System.tmp_dir!(), "familiar_realllm_#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, "alpha.txt"), "first line of alpha\n")
    File.write!(Path.join(dir, "beta.txt"), "first line of beta\n")
    on_exit(fn -> File.rm_rf!(dir) end)
    {:ok, dir: dir}
  end

  test "Familiar delegates a file read to a child with bare read_file gate", %{dir: dir} do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      {:ok, llm} = Cantrip.llm_from_env()
      {:ok, cantrip} = Cantrip.Familiar.new(llm: llm, root: dir)

      {:ok, result, _next_cantrip, loom, meta} =
        Cantrip.cast(
          cantrip,
          "Delegate to a child cantrip to read alpha.txt and return its first line. The child should use circle type :code with gates [\"read_file\", \"done\"]."
        )

      assert meta.terminated
      assert is_binary(to_string(result))

      # Real LLMs vary in framing; the read child should have produced a
      # successful read_file observation against the inherited sandbox.
      all_obs = Enum.flat_map(loom.turns, & &1.observation)

      assert Enum.any?(all_obs, fn obs ->
               obs.gate == "read_file" and not obs.is_error and
                 is_binary(obs.result) and obs.result =~ "first line of alpha"
             end),
             "expected a successful child read_file observation containing the file contents"

      # The parent's done answer should mention the content (loose check —
      # real LLMs vary in exact phrasing).
      assert to_string(result) =~ "alpha"
    end
  end

  test "Familiar fans out parallel reader children via cast_batch", %{dir: dir} do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      {:ok, llm} = Cantrip.llm_from_env()
      {:ok, cantrip} = Cantrip.Familiar.new(llm: llm, root: dir)

      {:ok, _result, _next, loom, meta} =
        Cantrip.cast(
          cantrip,
          "Read both alpha.txt and beta.txt by delegating each to its own child cantrip (use cast_batch). Return both first lines joined with a space."
        )

      assert meta.terminated

      reads =
        loom.turns
        |> Enum.flat_map(& &1.observation)
        |> Enum.filter(fn obs -> obs.gate == "read_file" and not obs.is_error end)

      # LLMs invoke `read_file` either as `read_file.("alpha.txt")` (bare
      # string) or `read_file.(%{path: "alpha.txt"})` (map). Both shapes
      # are equivalent at the gate boundary; normalize when introspecting.
      paths =
        reads
        |> Enum.map(fn obs ->
          case obs.args do
            arg when is_binary(arg) -> arg
            %{} = m -> m["path"] || m[:path]
            _ -> nil
          end
        end)
        |> Enum.reject(&is_nil/1)
        |> Enum.uniq()

      assert "alpha.txt" in paths
      assert "beta.txt" in paths
    end
  end

  # =====================================================================
  # Trial scenarios from the original Zed run transcripts
  # (scratch/familiar-run-001.md, scratch/familiar-run-002.md)
  # =====================================================================
  #
  # These pin the substrate against the same open-ended user prompts
  # that crashed in production. Each verifies that the Familiar produces
  # a coherent answer without the function_clause / nil-path / BitString
  # failures that originally surfaced.

  test "open-ended exploration: 'check out the harness'", %{dir: _} do
    if not RealLLMEnv.enabled?() do
      :ok
    else
      # The original user prompt from familiar-run-002.md. The Familiar
      # should navigate, optionally delegate, and produce a textual
      # answer — never crash with File.read(nil) or surface a stack
      # trace as a tool result.
      root = File.cwd!()
      {:ok, llm} = Cantrip.llm_from_env()
      {:ok, cantrip} = Cantrip.Familiar.new(llm: llm, root: root)

      {:ok, result, _next, loom, meta} =
        Cantrip.cast(cantrip, "Check out the new harness, what do you think?")

      assert meta.terminated, "Familiar must reach done() for open-ended exploration"

      # `done.(answer)` can return any shape (string, list, map, ...) per
      # the substrate's contract (L7 in familiar_behavior_test pins this).
      # Production ACP clients consume the answer through
      # `Cantrip.ACP.EventBridge.stringify/1`; that's the right assertion
      # surface — if the bridge produces non-empty text, the user sees an
      # answer regardless of the underlying shape.
      stringified = Cantrip.ACP.EventBridge.stringify(result)

      assert is_binary(stringified) and stringified != "",
             "Familiar must return an answer the bridge can convey"

      # No observation may surface a function_clause / GenServer crash
      # string — those were the original failure mode.
      all_obs = Enum.flat_map(loom.turns, & &1.observation)

      refute Enum.any?(all_obs, fn obs ->
               is_binary(obs.result) and obs.result =~ "function_clause"
             end),
             "no observation should surface a function_clause crash"

      refute Enum.any?(all_obs, fn obs ->
               is_binary(obs.result) and obs.result =~ "IO.chardata_to_string"
             end),
             "no observation should surface an IO.chardata_to_string(nil) crash"
    end
  end

  test "delegated reads survive when LLM omits the path arg" do
    # Original trace failure mode: the child's LLM forgot to pass `path`
    # to read_file. Pre-fix that produced a function_clause crash that
    # escaped the gate boundary as `{{:function_clause, ...}}` text.
    # Post-fix it must surface as a structured `is_error: true`
    # observation the parent can introspect or recover from.
    if not RealLLMEnv.enabled?() do
      :ok
    else
      tmp = Path.join(System.tmp_dir!(), "realllm_recov_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp)
      File.write!(Path.join(tmp, "data.txt"), "the secret is 42\n")

      try do
        {:ok, llm} = Cantrip.llm_from_env()
        {:ok, cantrip} = Cantrip.Familiar.new(llm: llm, root: tmp)

        # Note the intent deliberately doesn't name the file, just hints
        # at the directory. Some LLM choices will end up calling
        # read_file without `path`, which the substrate must survive.
        {:ok, _result, _next, loom, _meta} =
          Cantrip.cast(
            cantrip,
            "There's a file in this directory; delegate to a child cantrip to find and read it, then summarize."
          )

        all_obs = Enum.flat_map(loom.turns, & &1.observation)

        refute Enum.any?(all_obs, fn obs ->
                 is_binary(obs.result) and
                   (obs.result =~ "function_clause" or obs.result =~ "GenServer")
               end),
               "no observation should surface a runtime crash"
      after
        File.rm_rf!(tmp)
      end
    end
  end
end
