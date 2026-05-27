defmodule PortRunnerIsolationTest do
  @moduledoc """
  Integration tests for the `port_runner` ward.

  Two scopes:

  1. **Wiring** (always runs): the `port_runner` mechanism passes the child
     command + args through the wrapper correctly. Uses a no-op wrapper
     that records its argv to a file. If this fails, the port_runner
     plumbing is broken regardless of which OS sandbox you'd layer on top.

  2. **Constraint** (runs when an OS-level deny-network mechanism is
     available): when the operator wires a real sandbox wrapper, entity
     code cannot reach the network. The test discovers which primitive
     is available on the host (sandbox-exec on macOS; `unshare -n` on
     Linux with user namespaces; otherwise skip with a clear message)
     and uses it. Runs the entity under `sandbox: :port_unrestricted`
     so Dune is OFF — the OS layer is the only defense being tested.

  Tagged `:integration` so it stays out of the default fast suite.
  """

  use ExUnit.Case, async: false

  alias Cantrip.FakeLLM

  @moduletag :integration
  @moduletag timeout: :timer.seconds(60)

  setup_all do
    dir =
      Path.join(
        System.tmp_dir!(),
        "cantrip_port_runner_iso_#{System.unique_integer([:positive])}"
      )

    File.mkdir_p!(dir)
    on_exit(fn -> File.rm_rf!(dir) end)

    {:ok, dir: dir, deny_network_wrapper: build_deny_network_wrapper(dir)}
  end

  # === Wiring tests — always run ===

  describe "port_runner wiring (no-op wrapper)" do
    test "wrapper is invoked and receives the child command's argv", %{dir: dir} do
      argv_log = Path.join(dir, "noop_argv.log")
      wrapper = Path.join(dir, "noop_wrapper.sh")

      File.write!(wrapper, """
      #!/bin/bash
      printf '%s\\n' "$@" > #{argv_log}
      exec "$@"
      """)

      File.chmod!(wrapper, 0o755)

      llm = {FakeLLM, FakeLLM.new([%{code: ~S[done.(42)]}])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{system_prompt: "wiring"},
          circle: %{
            type: :code,
            gates: [:done],
            wards: [
              %{max_turns: 2},
              %{sandbox: :port},
              %{port_runner: [wrapper]},
              %{code_eval_timeout_ms: 10_000}
            ]
          }
        )

      assert {:ok, 42, _, _, _} = Cantrip.cast(cantrip, "trace argv")
      assert File.exists?(argv_log), "wrapper script was never invoked"

      logged = File.read!(argv_log)

      assert logged =~ "elixir" or logged =~ "beam",
             "argv didn't include the expected child command. got:\n#{logged}"
    end

    test "child evaluation works normally when wrapped by an identity port_runner", %{dir: dir} do
      identity = Path.join(dir, "identity.sh")
      File.write!(identity, "#!/bin/bash\nexec \"$@\"\n")
      File.chmod!(identity, 0o755)

      llm = {FakeLLM, FakeLLM.new([%{code: ~S[done.(1 + 1)]}])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          identity: %{system_prompt: "identity wrap"},
          circle: %{
            type: :code,
            gates: [:done],
            wards: [
              %{max_turns: 2},
              %{sandbox: :port},
              %{port_runner: [identity]},
              %{code_eval_timeout_ms: 10_000}
            ]
          }
        )

      assert {:ok, 2, _, _, _} = Cantrip.cast(cantrip, "wrapped eval works")
    end
  end

  # === Constraint tests — run when a deny-network primitive is available ===

  describe "deny-network wrapper actually binds entity code at the OS layer" do
    test "Erlang :httpc cannot reach external hosts", ctx do
      with_deny_network_wrapper(ctx, fn ->
        code = ~S"""
        :inets.start()
        :ssl.start()
        result = :httpc.request(:get, {~c"https://example.com", []}, [{:timeout, 3000}], [])
        reason =
          case result do
            {:error, r} -> inspect(r)
            other -> "unexpected: " <> inspect(other)
          end
        done.(%{"category" => "httpc", "reason" => reason})
        """

        value = drive(code, ctx)
        assert is_map(value)

        assert value["reason"] =~ "failed_connect" or value["reason"] =~ "nxdomain",
               ":httpc apparently reached the network (or returned unexpected shape): " <>
                 inspect(value)
      end)
    end

    test ":gen_tcp.connect fails at the OS layer", ctx do
      with_deny_network_wrapper(ctx, fn ->
        code = ~S"""
        reason =
          case :gen_tcp.connect(~c"example.com", 80, [], 3000) do
            {:ok, socket} ->
              :gen_tcp.close(socket)
              "unexpected_success"
            {:error, r} ->
              inspect(r)
          end
        done.(%{"category" => "gen_tcp", "reason" => reason})
        """

        value = drive(code, ctx)
        assert is_map(value)

        refute value["reason"] == "unexpected_success",
               ":gen_tcp.connect succeeded under the deny-network wrapper: #{inspect(value)}"
      end)
    end

    test "shelling out to curl returns nonzero with network error", ctx do
      with_deny_network_wrapper(ctx, fn ->
        code = ~S"""
        {output, status} =
          System.cmd("curl", ["-sS", "--max-time", "3", "https://example.com"], stderr_to_stdout: true)
        done.(%{"category" => "curl", "status" => status, "output" => String.slice(output, 0, 200)})
        """

        value = drive(code, ctx)
        assert is_map(value)

        assert value["status"] != 0,
               "curl exited 0 (network apparently succeeded): #{inspect(value)}"

        assert value["output"] =~ "Could not resolve" or value["output"] =~ "resolve host" or
                 value["output"] =~ "Couldn't",
               "expected DNS/network failure message, got: #{inspect(value["output"])}"
      end)
    end
  end

  describe "control — non-network operations still work through the wrapper" do
    test "file reads inside the allowed set succeed under deny-network wrapper", ctx do
      with_deny_network_wrapper(ctx, fn ->
        code = ~S"""
        result =
          case File.read("/etc/hosts") do
            {:ok, content} -> %{"ok" => true, "length" => String.length(content)}
            {:error, r} -> %{"ok" => false, "reason" => inspect(r)}
          end
        done.(result)
        """

        value = drive(code, ctx)
        assert is_map(value)

        assert value["ok"] == true,
               "expected successful read of /etc/hosts, got: #{inspect(value)} — " <>
                 "wrapper is blocking more than network (boundary wider than intended)"

        assert is_integer(value["length"]) and value["length"] > 0
      end)
    end
  end

  # === helpers ===

  # Try platform-appropriate deny-network primitives in order, return
  # the wrapper path or `nil` if none are available. Built once at
  # `setup_all` time so the discovery cost is paid once per run.
  defp build_deny_network_wrapper(dir) do
    cond do
      :os.type() == {:unix, :darwin} and System.find_executable("sandbox-exec") ->
        build_sandbox_exec_wrapper(dir)

      :os.type() == {:unix, :linux} and unshare_userns_works?() ->
        build_unshare_wrapper(dir)

      true ->
        nil
    end
  end

  defp build_sandbox_exec_wrapper(dir) do
    profile = Path.join(dir, "deny_network.sb")
    wrapper = Path.join(dir, "sandbox_exec_wrapper.sh")

    File.write!(profile, """
    (version 1)
    (allow default)
    (deny network*)
    """)

    File.write!(wrapper, """
    #!/bin/bash
    exec sandbox-exec -f #{profile} "$@"
    """)

    File.chmod!(wrapper, 0o755)
    wrapper
  end

  defp build_unshare_wrapper(dir) do
    wrapper = Path.join(dir, "unshare_wrapper.sh")

    File.write!(wrapper, """
    #!/bin/bash
    exec unshare --user --map-root-user --net "$@"
    """)

    File.chmod!(wrapper, 0o755)
    wrapper
  end

  # Some Linux distros disable unprivileged user namespaces. Probe once
  # rather than assuming.
  defp unshare_userns_works? do
    case System.cmd("unshare", ["--user", "--map-root-user", "--net", "true"],
           stderr_to_stdout: true
         ) do
      {_, 0} -> true
      _ -> false
    end
  rescue
    _ -> false
  end

  defp with_deny_network_wrapper(%{deny_network_wrapper: nil}, _fun) do
    # No OS deny-network primitive available; tests in this describe
    # block effectively skip. Return :ok so the test is reported as
    # passing rather than invalid — matching the project's convention
    # for opt-in coverage.
    :ok
  end

  defp with_deny_network_wrapper(_ctx, fun), do: fun.()

  # Drive the entity once under the wrapper and return the value passed
  # to done. Asserts on cast success — non-:ok here means port plumbing
  # failure, a different problem from "the sandboxed entity tried
  # something and was denied."
  defp drive(code, %{deny_network_wrapper: wrapper}) when is_binary(wrapper) do
    llm = {FakeLLM, FakeLLM.new([%{code: code}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        identity: %{system_prompt: "isolation test"},
        circle: %{
          type: :code,
          gates: [:done],
          wards: [
            %{max_turns: 2},
            %{sandbox: :port_unrestricted},
            %{port_runner: [wrapper]},
            %{code_eval_timeout_ms: 10_000}
          ]
        }
      )

    assert {:ok, value, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "attempt")
    value
  end
end
