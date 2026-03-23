defmodule Cantrip.FamiliarTest do
  use ExUnit.Case, async: true

  alias Cantrip.{Familiar, FakeLLM}

  describe "Familiar.new/1" do
    test "returns a valid cantrip struct" do
      llm = {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      assert %Cantrip{} = cantrip
      assert cantrip.llm_module == FakeLLM
    end

    test "includes read_file, list_dir, search, and done gates" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      gate_names = Map.keys(cantrip.circle.gates)
      assert "done" in gate_names
      assert "read_file" in gate_names
      assert "list_dir" in gate_names
      assert "search" in gate_names
    end

    test "has a system prompt describing the familiar" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      assert is_binary(cantrip.identity.system_prompt)
      assert cantrip.identity.system_prompt =~ "Familiar"
    end

    test "respects custom max_turns" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm, max_turns: 10)

      assert Cantrip.Circle.max_turns(cantrip.circle) == 10
    end

    test "defaults max_turns to 20" do
      llm = {FakeLLM, FakeLLM.new([])}
      {:ok, cantrip} = Familiar.new(llm: llm)

      assert Cantrip.Circle.max_turns(cantrip.circle) == 20
    end

    test "configures JSONL loom storage when loom_path given" do
      llm = {FakeLLM, FakeLLM.new([])}
      path = Path.join(System.tmp_dir!(), "familiar_test_#{System.unique_integer([:positive])}.jsonl")

      {:ok, cantrip} = Familiar.new(llm: llm, loom_path: path)
      assert cantrip.loom_storage == {:jsonl, path}
    end
  end

  describe "read_file gate" do
    test "reads a real temp file" do
      tmp_dir = Path.join(System.tmp_dir!(), "familiar_rf_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      file_path = Path.join(tmp_dir, "hello.txt")
      File.write!(file_path, "hello world")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "read_file", args: %{"path" => file_path}}]},
           %{tool_calls: [%{gate: "done", args: %{answer: "read it"}}]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, result, _c, loom, _meta} = Cantrip.cast(cantrip, "read that file")

      # The read_file gate should have executed and returned file content
      read_obs =
        loom.turns
        |> Enum.flat_map(fn t -> t.observation || [] end)
        |> Enum.find(fn obs -> obs.gate == "read_file" end)

      assert read_obs != nil
      assert read_obs.result == "hello world"
      assert read_obs.is_error == false
    after
      File.rm_rf!(Path.join(System.tmp_dir!(), "familiar_rf_*"))
    end

    test "returns error for nonexistent file" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "read_file", args: %{"path" => "/nonexistent/path/file.txt"}}]},
           %{tool_calls: [%{gate: "done", args: %{answer: "handled error"}}]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, _result, _c, loom, _meta} = Cantrip.cast(cantrip, "read missing file")

      read_obs =
        loom.turns
        |> Enum.flat_map(fn t -> t.observation || [] end)
        |> Enum.find(fn obs -> obs.gate == "read_file" end)

      assert read_obs.is_error == true
    end
  end

  describe "list_dir gate" do
    test "lists a real temp directory" do
      tmp_dir = Path.join(System.tmp_dir!(), "familiar_ld_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "a.txt"), "a")
      File.write!(Path.join(tmp_dir, "b.txt"), "b")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "list_dir", args: %{"path" => tmp_dir}}]},
           %{tool_calls: [%{gate: "done", args: %{answer: "listed"}}]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, _result, _c, loom, _meta} = Cantrip.cast(cantrip, "list dir")

      list_obs =
        loom.turns
        |> Enum.flat_map(fn t -> t.observation || [] end)
        |> Enum.find(fn obs -> obs.gate == "list_dir" end)

      assert list_obs != nil
      assert list_obs.is_error == false
      # Result should contain the filenames
      assert list_obs.result =~ "a.txt"
      assert list_obs.result =~ "b.txt"
    after
      File.rm_rf!(Path.join(System.tmp_dir!(), "familiar_ld_*"))
    end
  end

  describe "search gate" do
    test "finds pattern in temp files" do
      tmp_dir = Path.join(System.tmp_dir!(), "familiar_sr_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      File.write!(Path.join(tmp_dir, "code.ex"), "defmodule Foo do\n  def hello, do: :world\nend\n")
      File.write!(Path.join(tmp_dir, "other.ex"), "no match here\n")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "search", args: %{"pattern" => "defmodule", "path" => tmp_dir}}]},
           %{tool_calls: [%{gate: "done", args: %{answer: "found it"}}]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm)
      {:ok, _result, _c, loom, _meta} = Cantrip.cast(cantrip, "search for defmodule")

      search_obs =
        loom.turns
        |> Enum.flat_map(fn t -> t.observation || [] end)
        |> Enum.find(fn obs -> obs.gate == "search" end)

      assert search_obs != nil
      assert search_obs.is_error == false
      assert search_obs.result =~ "defmodule"
    after
      File.rm_rf!(Path.join(System.tmp_dir!(), "familiar_sr_*"))
    end
  end

  describe "persistent entity" do
    test "familiar can be summoned and accumulate state across sends" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "first response"}}]},
           %{tool_calls: [%{gate: "done", args: %{answer: "second response"}}]}
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
      llm = {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

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

      llm = {FakeLLM, FakeLLM.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}

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

  describe "JSONL loom persistence" do
    test "loom persists to JSONL file" do
      path = Path.join(System.tmp_dir!(), "familiar_loom_#{System.unique_integer([:positive])}.jsonl")

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "done", args: %{answer: "persisted"}}]}
         ])}

      {:ok, cantrip} = Familiar.new(llm: llm, loom_path: path)
      {:ok, _result, _c, _loom, _meta} = Cantrip.cast(cantrip, "test persistence")

      assert File.exists?(path)
      content = File.read!(path)
      assert content =~ "turn"
      assert String.trim(content) != ""
    after
      # Cleanup
      Path.wildcard(Path.join(System.tmp_dir!(), "familiar_loom_*")) |> Enum.each(&File.rm/1)
    end
  end
end
