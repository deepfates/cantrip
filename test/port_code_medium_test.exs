defmodule PortCodeMediumTest do
  use ExUnit.Case, async: false

  alias Cantrip.FakeLLM

  defp port_cantrip(llm, opts \\ []) do
    gates = Keyword.get(opts, :gates, [:done, :echo])
    extra_wards = Keyword.get(opts, :extra_wards, [])
    sandbox = Keyword.get(opts, :sandbox, :port)

    wards =
      [%{max_turns: 10}, %{sandbox: sandbox}] ++ extra_wards ++ [%{code_eval_timeout_ms: 5_000}]

    Cantrip.new(
      llm: llm,
      circle: %{type: :code, gates: gates, wards: wards}
    )
  end

  test "evaluates Elixir in a port child and returns through done" do
    llm = {FakeLLM, FakeLLM.new([%{code: ~S[answer = 20 + 22; done.(answer)]}])}
    {:ok, cantrip} = port_cantrip(llm)

    assert {:ok, 42, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "compute")

    [turn] = loom.turns
    assert Enum.any?(turn.observation, &(&1.gate == "done" and not &1.is_error))
    refute Map.has_key?(turn.code_state, :port_session)
  end

  test "persists bindings across turns in the port child session" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: ~S[x = 41]},
         %{code: ~S[done.(x + 1)]}
       ])}

    {:ok, cantrip} = port_cantrip(llm)

    assert {:ok, 42, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "two turns")
    assert length(loom.turns) == 2
    assert Enum.any?(List.last(loom.turns).observation, &(&1.gate == "done"))
  end

  test "gate calls are resolved by the parent and recorded as observations" do
    llm = {FakeLLM, FakeLLM.new([%{code: ~S[value = echo.("observed"); done.(value)]}])}
    {:ok, cantrip} = port_cantrip(llm, gates: [:done, :echo])

    assert {:ok, "observed", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "echo")

    observations = loom.turns |> Enum.flat_map(& &1.observation)
    assert Enum.any?(observations, &(&1.gate == "echo" and &1.result == "observed"))
    assert Enum.any?(observations, &(&1.gate == "done" and &1.result == "observed"))
  end

  test "port child receives the parent telemetry context" do
    trace_id = "port-trace-123"

    code = """
    %{entity_id: entity_id, trace_id: trace_id} = Cantrip.Telemetry.current_context()
    done.({entity_id, trace_id})
    """

    llm = {FakeLLM, FakeLLM.new([%{code: code}])}
    {:ok, cantrip} = port_cantrip(llm, sandbox: :port_unrestricted)

    assert {:ok, {entity_id, ^trace_id}, _cantrip, _loom, _meta} =
             Cantrip.cast(cantrip, "context", trace_id: trace_id)

    assert is_binary(entity_id)
  end

  test "parent and port-child telemetry events share the same trace id" do
    trace_id = "port-boundary-trace-#{System.unique_integer([:positive])}"
    test_pid = self()
    handler_id = "port-boundary-trace-#{System.unique_integer([:positive])}"

    :telemetry.attach_many(
      handler_id,
      [[:cantrip, :entity, :start], [:cantrip, :code, :eval], [:cantrip, :redact, :hit]],
      &__MODULE__.handle_trace_event/4,
      test_pid
    )

    on_exit(fn -> :telemetry.detach(handler_id) end)

    code = """
    Cantrip.Redact.scan("OPENAI_API_KEY=sk-proj-portchild-secret-token")
    done.("ok")
    """

    llm = {FakeLLM, FakeLLM.new([%{code: code}])}
    {:ok, cantrip} = port_cantrip(llm, sandbox: :port_unrestricted)

    assert {:ok, "ok", _cantrip, _loom, _meta} =
             Cantrip.cast(cantrip, "telemetry", trace_id: trace_id)

    assert_received {:telemetry_event, [:cantrip, :entity, :start], ^trace_id}
    assert_received {:telemetry_event, [:cantrip, :code, :eval], ^trace_id}
    assert_received {:telemetry_event, [:cantrip, :redact, :hit], ^trace_id}
  end

  def handle_trace_event(event, _measurements, metadata, test_pid) do
    send(test_pid, {:telemetry_event, event, metadata[:trace_id]})
  end

  test "child stdout is captured without corrupting the port protocol" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: ~S[IO.puts("hello from child stdout"); done.("ok")]}
       ])}

    {:ok, cantrip} = port_cantrip(llm)

    assert {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "stdio")

    observations = loom.turns |> Enum.flat_map(& &1.observation)

    assert Enum.any?(
             observations,
             &(&1.gate == "stdio" and &1.result =~ "hello from child stdout")
           )

    refute Enum.any?(observations, &(&1.gate == "code" and &1.is_error))
  end

  test "configured port runner launches the child process" do
    tmp =
      Path.join(System.tmp_dir!(), "cantrip_port_runner_#{System.unique_integer([:positive])}")

    Process.put(:cantrip_port_runner_tmp, tmp)
    File.mkdir_p!(tmp)

    log_path = Path.join(tmp, "runner.log")
    runner_path = Path.join(tmp, "runner.sh")

    File.write!(runner_path, """
    #!/bin/sh
    printf '%s\\n' "$1" > #{log_path}
    exec "$@"
    """)

    File.chmod!(runner_path, 0o755)

    llm = {FakeLLM, FakeLLM.new([%{code: ~S[done.("runner ok")]}])}

    {:ok, cantrip} =
      port_cantrip(llm,
        extra_wards: [%{port_runner: [runner_path]}]
      )

    assert {:ok, "runner ok", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "runner")
    assert File.read!(log_path) =~ "elixir"
  after
    if tmp = Process.get(:cantrip_port_runner_tmp), do: File.rm_rf!(tmp)
  end

  test "port child treats epipe during reply as graceful shutdown" do
    tmp =
      Path.join(System.tmp_dir!(), "cantrip_port_epipe_#{System.unique_integer([:positive])}")

    Process.put(:cantrip_port_epipe_tmp, tmp)
    File.mkdir_p!(tmp)

    log_path = Path.join(tmp, "child-stderr.log")
    runner_path = Path.join(tmp, "runner.sh")

    File.write!(runner_path, """
    #!/bin/sh
    exec "$@" 2> #{log_path}
    """)

    File.chmod!(runner_path, 0o755)

    before_dumps = repo_crash_dumps()
    port = open_port_child(runner_path)
    send_port_frame(port, {:init, []})

    assert_receive {^port, {:data, payload}}, 5_000
    assert :erlang.binary_to_term(payload) == :ready

    ref = System.unique_integer([:positive, :monotonic])

    send_port_frame(
      port,
      {:eval, ref, ~S[Process.sleep(200); done.("late")],
       %{gate_names: ["done"], evaluator: :raw}}
    )

    Port.close(port)
    assert eventually_contains?(log_path, "Goodbye.", 2_000)
    assert repo_crash_dumps() == before_dumps
  after
    if tmp = Process.get(:cantrip_port_epipe_tmp), do: File.rm_rf!(tmp)
  end

  test "child BEAM global state does not mutate the host BEAM" do
    key = {__MODULE__, :persistent_term_isolation}
    :persistent_term.erase(key)

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           code:
             ~S[:persistent_term.put({PortCodeMediumTest, :persistent_term_isolation}, :child); done.("ok")]
         }
       ])}

    {:ok, cantrip} = port_cantrip(llm)

    assert {:ok, "ok", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "isolate")
    assert :persistent_term.get(key, :missing) == :missing
  after
    :persistent_term.erase({__MODULE__, :persistent_term_isolation})
  end

  test "default port evaluator denies ambient filesystem access" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: ~S[File.read!("/etc/hosts")]},
         %{code: ~S[done.("recovered")]}
       ])}

    {:ok, cantrip} = port_cantrip(llm)

    assert {:ok, "recovered", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "deny file")

    observations = loom.turns |> Enum.flat_map(& &1.observation)
    assert Enum.any?(observations, &(&1.gate == "code" and &1.is_error))
    assert Enum.any?(observations, &String.contains?(to_string(&1.result), "restricted"))
  end

  test "omitting a sandbox ward defaults code medium to the port sandbox" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: ~S[File.read!("/etc/hosts")]},
         %{code: ~S[done.("recovered")]}
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 10}]}
      )

    assert Cantrip.WardPolicy.sandbox(cantrip.circle.wards) == :port
    assert {:ok, "recovered", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "default port")

    observations = loom.turns |> Enum.flat_map(& &1.observation)
    assert Enum.any?(observations, &(&1.gate == "code" and &1.is_error))
    assert Enum.any?(observations, &String.contains?(to_string(&1.result), "restricted"))
  end

  test "materialized default port sandbox prevents child unrestricted override" do
    parent_code = """
    child_llm =
      {Cantrip.FakeLLM,
       Cantrip.FakeLLM.new([
         %{code: ~S[File.read!("/etc/passwd")]},
         %{code: ~S[done.("blocked")]}
       ])}

    {:ok, child} =
      Cantrip.new(
        llm: child_llm,
        circle: %{
          type: :code,
          gates: [:done],
          wards: [%{max_turns: 2}, %{sandbox: :unrestricted}]
        }
      )

    {:ok, value, _, _, _} = Cantrip.cast(child, "try child escape")
    done.(value)
    """

    llm = {FakeLLM, FakeLLM.new([%{code: parent_code}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{type: :code, gates: [:done], wards: [%{max_turns: 4}]}
      )

    assert Cantrip.WardPolicy.sandbox(cantrip.circle.wards) == :port
    assert {:ok, "blocked", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "parent default")

    observations = loom.turns |> Enum.flat_map(& &1.observation)
    assert Enum.any?(observations, &(&1.gate == "cast" and &1.result == "blocked"))

    refute Enum.any?(
             observations,
             &(is_binary(&1.result) and String.contains?(&1.result, "root:"))
           )
  end

  test "default port evaluator denies ambient system commands" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{code: ~S|System.cmd("echo", ["unsafe"])|},
         %{code: ~S[done.("recovered")]}
       ])}

    {:ok, cantrip} = port_cantrip(llm)

    assert {:ok, "recovered", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "deny system")

    observations = loom.turns |> Enum.flat_map(& &1.observation)
    assert Enum.any?(observations, &(&1.gate == "code" and &1.is_error))
    assert Enum.any?(observations, &String.contains?(to_string(&1.result), "restricted"))
  end

  test "timeout kills spawned work inside an unrestricted port child BEAM" do
    path =
      Path.join(System.tmp_dir!(), "cantrip_port_timeout_#{System.unique_integer([:positive])}")

    Process.put(:cantrip_timeout_path, path)
    File.rm(path)

    code = """
    spawn(fn ->
      Process.sleep(200)
      File.write!(#{inspect(path)}, "leaked")
    end)

    Process.sleep(:infinity)
    """

    llm = {FakeLLM, FakeLLM.new([%{code: code}, %{code: ~S[done.("recovered")]}])}

    {:ok, cantrip} =
      port_cantrip(llm, sandbox: :port_unrestricted, extra_wards: [%{code_eval_timeout_ms: 50}])

    assert {:ok, "recovered", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "timeout")
    Process.sleep(350)

    refute File.exists?(path)

    observations = loom.turns |> Enum.flat_map(& &1.observation)
    assert Enum.any?(observations, &(&1.gate == "code" and &1.is_error))
  after
    if path = Process.get(:cantrip_timeout_path), do: File.rm(path)
  end

  test "compile_and_load hot-loads into the child BEAM, not the parent" do
    suffix = System.unique_integer([:positive])
    module_name = "Elixir.Cantrip.Hot.PortDemo#{suffix}"
    module = String.to_atom(module_name)
    Process.put(:cantrip_port_hot_module, module)
    purge_module(module)

    source = """
    defmodule Cantrip.Hot.PortDemo#{suffix} do
      def value, do: 123
    end
    """

    code = """
    compile_and_load.(%{module: #{inspect(module_name)}, source: #{inspect(source)}})
    done.(Cantrip.Hot.PortDemo#{suffix}.value())
    """

    llm = {FakeLLM, FakeLLM.new([%{code: code}])}

    {:ok, cantrip} =
      port_cantrip(llm,
        gates: [:done, :compile_and_load],
        extra_wards: [%{allow_compile_modules: [module_name]}]
      )

    assert {:ok, 123, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "hot load")

    observations = loom.turns |> Enum.flat_map(& &1.observation)
    assert Enum.any?(observations, &(&1.gate == "compile_and_load" and &1.result == "ok"))
    refute Code.ensure_loaded?(module)
  after
    if module = Process.get(:cantrip_port_hot_module), do: purge_module(module)
  end

  test "hot-loaded structs cross back as plain safe maps" do
    suffix = System.unique_integer([:positive])
    module_name = "Elixir.Cantrip.Hot.PortStruct#{suffix}"
    module = String.to_atom(module_name)
    Process.put(:cantrip_port_hot_module, module)
    purge_module(module)

    source = """
    defmodule Cantrip.Hot.PortStruct#{suffix} do
      defstruct [:payload]
      def build(value), do: %__MODULE__{payload: value}
    end
    """

    code = """
    compile_and_load.(%{module: #{inspect(module_name)}, source: #{inspect(source)}})
    done.(Cantrip.Hot.PortStruct#{suffix}.build(123))
    """

    llm = {FakeLLM, FakeLLM.new([%{code: code}])}

    {:ok, cantrip} =
      port_cantrip(llm,
        gates: [:done, :compile_and_load],
        extra_wards: [%{allow_compile_modules: [module_name]}]
      )

    assert {:ok, result, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "hot struct")
    assert result == %{"__struct__" => module_name, "payload" => 123}

    observations = loom.turns |> Enum.flat_map(& &1.observation)

    assert Enum.any?(
             observations,
             &(&1.gate == "done" and get_in(&1, [:args, "answer"]) == result)
           )

    refute Enum.any?(observations, &(&1.gate == "code" and &1.is_error))
    refute Code.ensure_loaded?(module)
  after
    if module = Process.get(:cantrip_port_hot_module), do: purge_module(module)
  end

  test "hot-loaded child-only atoms cross back as strings" do
    suffix = System.unique_integer([:positive])
    module_name = "Elixir.Cantrip.Hot.PortAtom#{suffix}"
    module = String.to_atom(module_name)
    Process.put(:cantrip_port_hot_module, module)
    purge_module(module)

    source = """
    defmodule Cantrip.Hot.PortAtom#{suffix} do
      def value, do: :child_only_atom_#{suffix}
      def keyed, do: %{:child_only_key_#{suffix} => value()}
    end
    """

    code = """
    compile_and_load.(%{module: #{inspect(module_name)}, source: #{inspect(source)}})
    done.(%{value: Cantrip.Hot.PortAtom#{suffix}.value(), keyed: Cantrip.Hot.PortAtom#{suffix}.keyed()})
    """

    llm = {FakeLLM, FakeLLM.new([%{code: code}])}

    {:ok, cantrip} =
      port_cantrip(llm,
        gates: [:done, :compile_and_load],
        extra_wards: [%{allow_compile_modules: [module_name]}]
      )

    atom_text = "child_only_atom_#{suffix}"
    key_text = "child_only_key_#{suffix}"

    assert {:ok, result, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "hot atom")
    assert (Map.get(result, :value) || Map.get(result, "value")) == atom_text
    assert Map.fetch!(result, "keyed") == %{key_text => atom_text}

    observations = loom.turns |> Enum.flat_map(& &1.observation)

    assert Enum.any?(
             observations,
             &(&1.gate == "done" and get_in(&1, [:args, "answer"]) == result)
           )

    refute Enum.any?(observations, &(&1.gate == "code" and &1.is_error))
    refute Code.ensure_loaded?(module)
  after
    if module = Process.get(:cantrip_port_hot_module), do: purge_module(module)
  end

  test "nested port-created children preserve compile safety wards" do
    suffix = System.unique_integer([:positive])
    allowed_name = "Elixir.Cantrip.Hot.AllowedNested#{suffix}"
    disallowed_name = "Elixir.Cantrip.Hot.DisallowedNested#{suffix}"

    disallowed_source = """
    defmodule Cantrip.Hot.DisallowedNested#{suffix} do
      def value, do: 7
    end
    """

    child_code = """
    result =
      compile_and_load.(%{
        module: #{inspect(disallowed_name)},
        source: #{inspect(disallowed_source)}
      })

    done.(result)
    """

    parent_code = """
    child_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_code)}}])}

    {:ok, child} =
      Cantrip.new(
        llm: child_llm,
        circle: %{
          type: :code,
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 2},
            %{allow_compile_modules: [#{inspect(allowed_name)}]}
          ]
        }
      )

    {:ok, value, _, _, _} = Cantrip.cast(child, "attempt disallowed hot load")
    done.(value)
    """

    llm = {FakeLLM, FakeLLM.new([%{code: parent_code}])}

    {:ok, cantrip} =
      port_cantrip(llm,
        extra_wards: [%{code_eval_timeout_ms: 5_000}]
      )

    assert {:ok, result, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "delegate compile")
    assert result == "module not allowed: #{disallowed_name}"

    observations = loom.turns |> Enum.flat_map(& &1.observation)
    assert Enum.any?(observations, &(&1.gate == "cast" and &1.result == result))
  end

  test "parent rejects child protocol frames containing child-only atoms" do
    tmp =
      Path.join(
        System.tmp_dir!(),
        "cantrip_malicious_port_runner_#{System.unique_integer([:positive])}"
      )

    Process.put(:cantrip_malicious_runner_tmp, tmp)
    File.mkdir_p!(tmp)

    runner_path = Path.join(tmp, "runner.sh")
    child_only_atom = "__cantrip_child_only_atom_#{System.unique_integer([:positive])}"

    File.write!(runner_path, """
    #!/bin/sh
    exec "$1" -e 'atom = String.to_atom("#{child_only_atom}"); payload = :erlang.term_to_binary({:ready, atom}); IO.binwrite(<<byte_size(payload)::32, payload::binary>>); Process.sleep(:infinity)'
    """)

    File.chmod!(runner_path, 0o755)

    circle =
      Cantrip.Circle.new(%{
        type: :code,
        gates: [:done],
        wards: [
          %{sandbox: :port},
          %{port_runner: [runner_path]},
          %{code_eval_timeout_ms: 500}
        ]
      })

    {_state, observations, nil, false} =
      Cantrip.Medium.Code.Port.eval(~S[done.("nope")], %{}, %Cantrip.Runtime{circle: circle})

    assert [
             %{
               gate: "code",
               is_error: true,
               result: "port evaluator failed to start: " <> reason
             }
           ] = observations

    assert reason =~ "invalid or unsafe external representation of a term"
  after
    if tmp = Process.get(:cantrip_malicious_runner_tmp), do: File.rm_rf!(tmp)
  end

  test "code in the port child composes child cantrips through the parent API" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           {:ok, child} =
             Cantrip.new(
               identity: %{system_prompt: "Return done with child answer."},
               circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 2}]}
             )

           {:ok, value, _child, _child_loom, _meta} = Cantrip.cast(child, "child task")
           done.("parent saw " <> value)
           """
         },
         %{tool_calls: [%{gate: "done", args: %{answer: "child value"}}]}
       ])}

    {:ok, cantrip} = port_cantrip(llm)

    assert {:ok, "parent saw child value", _cantrip, loom, _meta} =
             Cantrip.cast(cantrip, "delegate")

    observations = loom.turns |> Enum.flat_map(& &1.observation)
    cast_obs = Enum.find(observations, &(&1.gate == "cast"))
    assert cast_obs
    assert cast_obs.result == "child value"
    assert length(loom.turns) >= 2

    assert Enum.any?(loom.turns, fn turn ->
             turn.entity_id != hd(loom.turns).entity_id and
               Enum.any?(turn.observation, &(&1.gate == "done" and &1.result == "child value"))
           end)
  end

  test "code in the port child can fan out with cast_batch through the parent API" do
    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           code: """
           {:ok, child} =
             Cantrip.new(
               identity: %{system_prompt: "Return done with batch answer."},
               circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 2}]}
             )

           {:ok, values, _children, _looms, _meta} =
             Cantrip.cast_batch([
               %{cantrip: child, intent: "one"},
               %{cantrip: child, intent: "two"}
             ])

           done.(Enum.join(values, "+"))
           """
         },
         %{tool_calls: [%{gate: "done", args: %{answer: "a"}}]},
         %{tool_calls: [%{gate: "done", args: %{answer: "b"}}]}
       ])}

    {:ok, cantrip} = port_cantrip(llm)

    assert {:ok, "a+a", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "batch")

    observations = loom.turns |> Enum.flat_map(& &1.observation)
    batch_obs = Enum.find(observations, &(&1.gate == "cast_batch"))
    assert batch_obs
    assert batch_obs.result == ["a", "a"]

    child_done_turns =
      Enum.filter(loom.turns, fn turn ->
        turn.entity_id != hd(loom.turns).entity_id and
          Enum.any?(turn.observation, &(&1.gate == "done"))
      end)

    assert length(child_done_turns) == 2
  end

  defp purge_module(module) do
    :code.purge(module)
    :code.delete(module)
  end

  defp open_port_child(runner_path) do
    elixir = System.find_executable("elixir")

    child_args =
      Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)]) ++
        ["-e", "Cantrip.Medium.Code.PortChild.main()"]

    Port.open({:spawn_executable, runner_path}, [
      :binary,
      :exit_status,
      {:packet, 4},
      args: [elixir | child_args]
    ])
  end

  defp send_port_frame(port, term) do
    Port.command(port, :erlang.term_to_binary(term))
  end

  defp eventually_contains?(path, expected, timeout_ms) do
    deadline = System.monotonic_time(:millisecond) + timeout_ms
    eventually_contains_until?(path, expected, deadline)
  end

  defp eventually_contains_until?(path, expected, deadline) do
    if File.exists?(path) and String.contains?(File.read!(path), expected) do
      true
    else
      if System.monotonic_time(:millisecond) >= deadline do
        false
      else
        Process.sleep(25)
        eventually_contains_until?(path, expected, deadline)
      end
    end
  end

  defp repo_crash_dumps do
    File.cwd!()
    |> Path.join("erl_crash.dump*")
    |> Path.wildcard()
    |> MapSet.new()
  end
end
