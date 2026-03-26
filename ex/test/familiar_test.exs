defmodule Cantrip.FamiliarTest do
  use ExUnit.Case, async: true

  alias Cantrip.{Familiar, FakeLLM, Circle}

  describe "Familiar.new/1 — spec-conformant orchestrator" do
    test "returns a cantrip with code medium (not conversation)" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s[done.("ok")]}])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      assert %Cantrip{} = cantrip
      assert cantrip.circle.type == :code
    end

    test "includes observation gates: read_file, list_dir, search" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      gate_names = Map.keys(cantrip.circle.gates)
      assert "done" in gate_names
      assert "read_file" in gate_names
      assert "list_dir" in gate_names
      assert "search" in gate_names
    end

    test "includes orchestration gates: cantrip, cast, cast_batch, dispose" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      gate_names = Map.keys(cantrip.circle.gates)
      assert "cantrip" in gate_names
      assert "cast" in gate_names
      assert "cast_batch" in gate_names
      assert "dispose" in gate_names
    end

    test "system prompt mentions orchestration and child cantrips" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      prompt = cantrip.identity.system_prompt
      assert is_binary(prompt)
      assert prompt =~ "Familiar"
      assert prompt =~ "orchestrat"
      assert prompt =~ "cantrip"
      assert prompt =~ "child"
    end

    test "respects custom max_turns" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm, max_turns: 10)

      assert Circle.max_turns(cantrip.circle) == 10
    end

    test "defaults max_turns to 20" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      assert Circle.max_turns(cantrip.circle) == 20
    end

    test "configures JSONL loom storage when loom_path given" do
      llm = {FakeLLM, FakeLLM.new([])}
      path = Path.join(System.tmp_dir!(), "familiar_test_#{System.unique_integer([:positive])}.jsonl")

      {:ok, cantrip} = Familiar.new(llm: llm, loom_path: path)
      assert cantrip.loom_storage == {:jsonl, path}
    end
  end

  describe "observation gates work in code medium" do
    test "read_file gate reads a real temp file via code" do
      tmp_dir = Path.join(System.tmp_dir!(), "familiar_rf_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      file_path = Path.join(tmp_dir, "hello.txt")
      File.write!(file_path, "hello world")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s[content = read_file.(%{path: "#{file_path}"})\ndone.("got:" <> content)]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "read that file")
      assert result == "got:hello world"
    after
      File.rm_rf!(Path.join(System.tmp_dir!(), "familiar_rf_*"))
    end

    test "list_dir gate lists directory contents via code" do
      tmp_dir = Path.join(System.tmp_dir!(), "familiar_ld_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "a.txt"), "a")
      File.write!(Path.join(tmp_dir, "b.txt"), "b")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s[entries = list_dir.(%{path: "#{tmp_dir}"})\ndone.(entries)]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "list dir")
      assert result =~ "a.txt"
      assert result =~ "b.txt"
    after
      File.rm_rf!(Path.join(System.tmp_dir!(), "familiar_ld_*"))
    end

    test "search gate finds pattern in temp files via code" do
      tmp_dir = Path.join(System.tmp_dir!(), "familiar_sr_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "code.ex"), "defmodule Foo do\n  def hello, do: :world\nend\n")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s[result = search.(%{pattern: "defmodule", path: "#{tmp_dir}"})\ndone.(result)]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "search for defmodule")
      assert result =~ "defmodule"
    after
      File.rm_rf!(Path.join(System.tmp_dir!(), "familiar_sr_*"))
    end
  end

  describe "cantrip() + cast() orchestration pattern" do
    test "cantrip() constructs a child config and cast() executes it" do
      # Parent: construct a child cantrip, cast an intent to it, return the result
      parent =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             id = cantrip.(%{
               identity: "You are a helper. Call done with the answer.",
               circle: %{medium: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             result = cast.(id, "What is 6 * 7?")
             done.(result)
             """
           }
         ])}

      # Child responds with done
      child =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "42"}}]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: parent, child_llm: child)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "delegate to child")
      assert result == "42"
    end

    test "cast_batch() executes multiple children in parallel" do
      parent =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             id1 = cantrip.(%{
               identity: "Analyzer 1",
               circle: %{medium: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             id2 = cantrip.(%{
               identity: "Analyzer 2",
               circle: %{medium: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             results = cast_batch.([
               %{cantrip: id1, intent: "analyze trends"},
               %{cantrip: id2, intent: "analyze risks"}
             ])
             done.(Enum.join(results, " | "))
             """
           }
         ])}

      child =
        {FakeLLM,
         FakeLLM.new(
           [
             %{tool_calls: [%{gate: "done", args: %{answer: "trend-result"}}]},
             %{tool_calls: [%{gate: "done", args: %{answer: "risk-result"}}]}
           ],
           shared: true
         )}

      {:ok, cantrip} = Familiar.new(llm: parent, child_llm: child)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "parallel analysis")
      assert result =~ "trend-result"
      assert result =~ "risk-result"
    end

    test "dispose() cleans up a constructed cantrip" do
      parent =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             id = cantrip.(%{
               identity: "temp helper",
               circle: %{medium: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             dispose.(id)
             done.("disposed")
             """
           }
         ])}

      {:ok, cantrip} = Familiar.new(llm: parent)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "dispose test")
      assert result == "disposed"
    end

    test "cast() with a disposed cantrip raises an error" do
      parent =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             id = cantrip.(%{
               identity: "temp helper",
               circle: %{medium: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             dispose.(id)
             try do
               cast.(id, "should fail")
               done.("should not reach")
             rescue
               e -> done.("error: " <> Exception.message(e))
             end
             """
           }
         ])}

      {:ok, cantrip} = Familiar.new(llm: parent)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "cast after dispose")
      assert result =~ "error:"
    end
  end

  describe "persistent entity" do
    test "familiar can be summoned and accumulate state across sends" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s[done.("first response")]},
           %{code: ~s[done.("second response")]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, pid} = Cantrip.summon(cantrip)
      assert Process.alive?(pid)

      {:ok, r1, _c1, loom1, _m1} = Cantrip.send(pid, "hello")
      assert r1 == "first response"
      assert length(loom1.turns) == 1

      {:ok, r2, _c2, loom2, _m2} = Cantrip.send(pid, "continue")
      assert r2 == "second response"
      assert length(loom2.turns) == 2
    end
  end

  describe "ACP runtime (Familiar)" do
    test "new_session returns a session with familiar gates" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s[done.("ok")]}])}

      {:ok, session} =
        Cantrip.ACP.Runtime.Familiar.new_session(%{
          "cwd" => System.tmp_dir!(),
          "llm" => llm
        })

      gate_names = Map.keys(session.cantrip.circle.gates)
      assert "done" in gate_names
      assert "read_file" in gate_names
      assert "list_dir" in gate_names
      assert "search" in gate_names
    end

    test "new_session includes familiar system prompt" do
      llm = {FakeLLM, FakeLLM.new([])}

      {:ok, session} =
        Cantrip.ACP.Runtime.Familiar.new_session(%{
          "cwd" => System.tmp_dir!(),
          "llm" => llm
        })

      assert session.cantrip.identity.system_prompt =~ "Familiar"
    end

    test "ACP protocol works with familiar runtime" do
      state = Cantrip.ACP.Protocol.new(runtime: Cantrip.ACP.Runtime.Familiar)

      # Initialize
      {state, [resp]} =
        Cantrip.ACP.Protocol.handle_request(state, %{
          "jsonrpc" => "2.0",
          "id" => 1,
          "method" => "initialize"
        })

      assert resp["result"]["protocolVersion"] == 1

      llm = {FakeLLM, FakeLLM.new([%{code: ~s[done.("ok")]}])}

      # Create session with injected LLM
      {_state, [resp]} =
        Cantrip.ACP.Protocol.handle_request(state, %{
          "jsonrpc" => "2.0",
          "id" => 2,
          "method" => "session/new",
          "params" => %{"cwd" => System.tmp_dir!(), "llm" => llm}
        })

      assert resp["result"]["sessionId"]
    end
  end

  describe "JSONL loom persistence" do
    test "loom persists to JSONL file" do
      path = Path.join(System.tmp_dir!(), "familiar_loom_#{System.unique_integer([:positive])}.jsonl")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s[done.("persisted")]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm, loom_path: path)
      {:ok, _result, _c, _loom, _meta} = Cantrip.cast(cantrip, "test persistence")

      assert File.exists?(path)
      content = File.read!(path)
      assert content =~ "turn"
      assert String.trim(content) != ""
    after
      Path.wildcard(Path.join(System.tmp_dir!(), "familiar_loom_*")) |> Enum.each(&File.rm/1)
    end
  end

  describe "Mix task --acp flag" do
    test "option parser accepts --acp flag" do
      {opts, _positional, _} =
        OptionParser.parse(["--acp"],
          strict: [
            loom_path: :string,
            max_turns: :integer,
            help: :boolean,
            acp: :boolean
          ],
          aliases: [h: :help]
        )

      assert opts[:acp] == true
    end
  end
end
