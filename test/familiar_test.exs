defmodule Cantrip.FamiliarTest do
  use ExUnit.Case, async: true

  alias Cantrip.{Familiar, FakeLLM}

  describe "Familiar.new/1 — spec-conformant orchestrator" do
    test "returns a cantrip with code medium (not conversation)" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s[done.("ok")]}])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      assert %Cantrip{} = cantrip
      assert cantrip.circle.type == :code
      assert Cantrip.WardPolicy.sandbox(cantrip.circle.wards) == :port
    end

    test "unrestricted sandbox option is an explicit escape hatch" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s[done.("ok")]}])}

      {:ok, cantrip} = Familiar.new(llm: llm, sandbox: :unrestricted)
      assert Cantrip.WardPolicy.sandbox(cantrip.circle.wards) == :unrestricted
    end

    test "port runner option is carried as a ward for the code medium" do
      llm = {FakeLLM, FakeLLM.new([%{code: ~s[done.("ok")]}])}

      {:ok, cantrip} = Familiar.new(llm: llm, port_runner: ["/usr/bin/env"])
      assert Cantrip.WardPolicy.get(cantrip.circle.wards, :port_runner) == ["/usr/bin/env"]
    end

    test "includes navigation gates: list_dir, search (not read_file)" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      gate_names = Map.keys(cantrip.circle.gates)
      assert "done" in gate_names
      assert "list_dir" in gate_names
      assert "search" in gate_names
      refute "read_file" in gate_names
      refute "compile_and_load" in gate_names
    end

    test "compile_and_load is opt-in through evolve: true" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm, evolve: true)

      gate_names = Map.keys(cantrip.circle.gates)
      assert "compile_and_load" in gate_names

      assert Cantrip.WardPolicy.get(cantrip.circle.wards, :allow_compile_namespaces) == [
               "Elixir.Cantrip.Hot."
             ]

      refute cantrip.identity.system_prompt =~ "compile_and_load"

      capability_text = Cantrip.Medium.Registry.present(cantrip.circle).capability_text
      assert capability_text =~ "compile_and_load"
      assert capability_text =~ "Cantrip.Hot.Tally"
    end

    test "default circle does not teach hot-load evolution" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      refute cantrip.identity.system_prompt =~ "compile_and_load"
      refute Cantrip.WardPolicy.get(cantrip.circle.wards, :allow_compile_namespaces)

      capability_text = Cantrip.Medium.Registry.present(cantrip.circle).capability_text
      refute capability_text =~ "compile_and_load"
    end

    test "does not expose a second orchestration gate ontology" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      gate_names = Map.keys(cantrip.circle.gates)
      refute "cantrip" in gate_names
      refute "cast" in gate_names
      refute "cast_batch" in gate_names
      refute "dispose" in gate_names
    end

    test "system prompt teaches the helper-summoning paradigm" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      prompt = cantrip.identity.system_prompt
      assert is_binary(prompt)
      # Operative naming: the Familiar is a long-lived entity that can
      # summon other entities via cantrips, into circles bounded by gates/wards.
      assert prompt =~ "Familiar"
      assert prompt =~ "cantrip"
      assert prompt =~ "fellow entity"
      assert prompt =~ ~r/gates?/
      assert prompt =~ ~r/wards?/
      assert prompt =~ "loom"
      assert prompt =~ "active inference loop"
    end

    test "respects custom max_turns" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm, max_turns: 10)

      assert Cantrip.WardPolicy.get(cantrip.circle.wards, :max_turns) == 10
    end

    test "defaults max_turns to 20" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      assert Cantrip.WardPolicy.get(cantrip.circle.wards, :max_turns) == 20
    end

    test "configures JSONL loom storage when loom_path given" do
      llm = {FakeLLM, FakeLLM.new([])}

      path =
        Path.join(System.tmp_dir!(), "familiar_test_#{System.unique_integer([:positive])}.jsonl")

      {:ok, cantrip} = Familiar.new(llm: llm, loom_path: path)
      assert cantrip.loom_storage == {:jsonl, path}
    end
  end

  describe "observation gates work in code medium" do
    test "list_dir gate lists directory contents via code" do
      tmp_dir = Path.join(System.tmp_dir!(), "familiar_ld_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "a.txt"), "a")
      File.write!(Path.join(tmp_dir, "b.txt"), "b")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s[entries = list_dir.(%{path: "."})\ndone.(entries)]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm, root: tmp_dir)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "list dir")
      # Public API contract: list_dir returns plain bare names. done() preserves the
      # value the script passed, so the cast result is the list itself.
      assert is_list(result)
      assert "a.txt" in result
      assert "b.txt" in result
    after
      File.rm_rf!(Path.join(System.tmp_dir!(), "familiar_ld_*"))
    end

    test "search gate finds pattern in temp files via code" do
      tmp_dir = Path.join(System.tmp_dir!(), "familiar_sr_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)

      File.write!(
        Path.join(tmp_dir, "code.ex"),
        "defmodule Foo do\n  def hello, do: :world\nend\n"
      )

      # search returns a list of %{path, line, text} maps (consistent
      # with list_dir returning a list). The entity composes that list
      # in code rather than parsing a joined string.
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{
             code:
               ~s[matches = search.(%{pattern: "defmodule", path: "."})\nfirst = List.first(matches)\ndone.(first.text)]
           }
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm, root: tmp_dir)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "search for defmodule")
      assert result =~ "defmodule"
    after
      File.rm_rf!(Path.join(System.tmp_dir!(), "familiar_sr_*"))
    end
  end

  # ===========================================================================
  # CIRCLE-10: Filesystem gates sandboxed to root
  # ===========================================================================

  describe "filesystem gate sandboxing" do
    test "list_dir rejects traversal outside root" do
      tmp_dir =
        Path.join(System.tmp_dir!(), "familiar_sandbox_ld_#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp_dir)

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s[result = list_dir.("../../..")\ndone.(result)]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm, root: tmp_dir)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "try traversal")
      assert result =~ "outside sandbox root"
    after
      File.rm_rf!(Path.join(System.tmp_dir!(), "familiar_sandbox_ld_*"))
    end

    test "read_file rejects symlink escapes outside root" do
      tmp_dir =
        Path.join(
          System.tmp_dir!(),
          "familiar_sandbox_symlink_#{System.unique_integer([:positive])}"
        )

      outside_path =
        Path.join(
          System.tmp_dir!(),
          "familiar_sandbox_outside_#{System.unique_integer([:positive])}"
        )

      Process.put(:familiar_sandbox_symlink_tmp, tmp_dir)
      Process.put(:familiar_sandbox_symlink_outside, outside_path)
      File.mkdir_p!(tmp_dir)
      File.write!(outside_path, "outside secret")

      link_path = Path.join(tmp_dir, "inside_link")

      case File.ln_s(outside_path, link_path) do
        :ok ->
          llm =
            {FakeLLM,
             FakeLLM.new([
               %{code: ~s[result = read_file.(%{path: "inside_link"})\ndone.(result)]}
             ])}

          {:ok, cantrip} =
            Cantrip.new(
              llm: llm,
              circle: %{
                type: :code,
                gates: [%{name: "done"}, %{name: "read_file", dependencies: %{root: tmp_dir}}],
                wards: [%{max_turns: 3}]
              }
            )

          {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "try symlink")

          assert result =~ "outside sandbox root"
          refute result =~ "outside secret"

        {:error, :enotsup} ->
          :ok
      end
    after
      if tmp_dir = Process.get(:familiar_sandbox_symlink_tmp), do: File.rm_rf!(tmp_dir)
      if outside_path = Process.get(:familiar_sandbox_symlink_outside), do: File.rm(outside_path)
    end
  end

  describe "isomorphic Cantrip.new + Cantrip.cast orchestration pattern" do
    test "Cantrip.new constructs a child and Cantrip.cast executes it" do
      # Parent: construct a child cantrip, cast an intent to it, return the result
      parent =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             {:ok, child} = Cantrip.new(%{
               identity: %{system_prompt: "You are a helper. Call done with the answer."},
               circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             {:ok, result, _child, _child_loom, _meta} = Cantrip.cast(child, "What is 6 * 7?")
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

    test "Cantrip.cast_batch executes multiple children in parallel" do
      parent =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             trend_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([
               %{tool_calls: [%{gate: "done", args: %{answer: "trend-result"}}]}
             ])}
             risk_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([
               %{tool_calls: [%{gate: "done", args: %{answer: "risk-result"}}]}
             ])}
             {:ok, analyzer_1} = Cantrip.new(%{
               llm: trend_llm,
               identity: %{system_prompt: "Analyzer 1"},
               circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             {:ok, analyzer_2} = Cantrip.new(%{
               llm: risk_llm,
               identity: %{system_prompt: "Analyzer 2"},
               circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             {:ok, results, _children, _looms, _meta} = Cantrip.cast_batch([
               %{cantrip: analyzer_1, intent: "analyze trends"},
               %{cantrip: analyzer_2, intent: "analyze risks"}
             ])
             done.(Enum.join(results, " | "))
             """
           }
         ])}

      {:ok, cantrip} = Familiar.new(llm: parent)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "parallel analysis")
      assert result =~ "trend-result"
      assert result =~ "risk-result"
    end

    test "cast-mode children are plain values and need no dispose step" do
      parent =
        {FakeLLM,
         FakeLLM.new([
           %{
             code: """
             {:ok, child} = Cantrip.new(%{
               identity: %{system_prompt: "temp helper"},
               circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             %Cantrip{} = child
             done.(true)
             """
           }
         ])}

      {:ok, cantrip} = Familiar.new(llm: parent)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "child value test")
      assert result == true
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
      assert "list_dir" in gate_names
      assert "search" in gate_names
      refute "read_file" in gate_names
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

    test "ACP AgentHandler works with familiar runtime" do
      alias Cantrip.ACP.AgentHandler

      table = AgentHandler.new(runtime: Cantrip.ACP.Runtime.Familiar)

      # Initialize
      assert {:ok, %ACP.InitializeResponse{protocol_version: 1}} =
               AgentHandler.handle_request(
                 {:initialize,
                  %ACP.InitializeRequest{
                    protocol_version: 1,
                    client_capabilities: %ACP.ClientCapabilities{},
                    client_info: %{"name" => "test"}
                  }},
                 table
               )

      llm = {FakeLLM, FakeLLM.new([%{code: ~s[done.("ok")]}])}

      # Create session with injected LLM via meta
      assert {:ok, %ACP.NewSessionResponse{session_id: session_id}} =
               AgentHandler.handle_request(
                 {:new_session,
                  %ACP.NewSessionRequest{
                    cwd: System.tmp_dir!(),
                    meta: %{"llm" => llm}
                  }},
                 table
               )

      assert is_binary(session_id)
    end
  end

  describe "JSONL loom persistence" do
    test "loom persists to JSONL file" do
      path =
        Path.join(System.tmp_dir!(), "familiar_loom_#{System.unique_integer([:positive])}.jsonl")

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

  # ===========================================================================
  # A.12: Child cantrip values must persist across turns
  # ===========================================================================

  describe "child cantrip persistence across turns" do
    test "child constructed on turn 1 can be cast on turn 2" do
      # Turn 1: construct a child cantrip, store the value in a variable
      # Turn 2: cast the child using the stored value
      # Turn 3: done with the result
      parent =
        {FakeLLM,
         FakeLLM.new([
           # Turn 1: construct child
           %{
             code: """
             {:ok, child} = Cantrip.new(%{
               identity: %{system_prompt: "You are a helper. Call done with the answer."},
               circle: %{type: :conversation, gates: ["done"], wards: [%{max_turns: 3}]}
             })
             """
           },
           # Turn 2: cast the child using the value from turn 1
           %{
             code: """
             {:ok, result, _child, _child_loom, _meta} = Cantrip.cast(child, "What is 6 * 7?")
             done.(result)
             """
           }
         ])}

      child =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "42"}}]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: parent, child_llm: child)
      {:ok, result, _c, _loom, _meta} = Cantrip.cast(cantrip, "cross-turn orchestration")
      assert result == "42"
    end
  end
end
