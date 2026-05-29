defmodule Cantrip.Medium.BashTest do
  use ExUnit.Case, async: true

  alias Cantrip.Medium.Bash
  alias Cantrip.Medium.Bash.Sandbox
  alias Cantrip.FakeLLM

  describe "Bash.eval/3" do
    defp runtime(opts \\ %{}) do
      circle =
        Cantrip.Circle.new(%{
          type: :bash,
          gates: [:done],
          wards: [%{max_turns: 5}],
          medium_opts: Map.merge(%{sandbox: :passthrough}, opts)
        })

      %{circle: circle}
    end

    defp expected_sandbox_path(path) do
      path = Path.expand(path)

      case :os.type() do
        {:unix, :darwin} ->
          cond do
            path == "/tmp" ->
              "/private/tmp"

            String.starts_with?(path, "/tmp/") ->
              "/private/tmp/" <> String.trim_leading(path, "/tmp/")

            path == "/var" ->
              "/private/var"

            String.starts_with?(path, "/var/") ->
              "/private/var/" <> String.trim_leading(path, "/var/")

            true ->
              path
          end

        _ ->
          path
      end
    end

    test "bubblewrap writable binds use OS-appropriate tmp path" do
      writable = Path.join(System.tmp_dir!(), "cantrip-bwrap-writable")

      Process.put(:cantrip_bash_writable_paths, [writable])
      on_exit(fn -> Process.delete(:cantrip_bash_writable_paths) end)

      {_exe, args, _opts} =
        Sandbox.command(:bubblewrap, "true", File.cwd!(), "/tmp/cantrip-session", [])

      expected = expected_sandbox_path(writable)

      assert args
             |> Enum.chunk_every(3, 1, :discard)
             |> Enum.any?(fn
               ["--bind", ^expected, ^expected] -> true
               _ -> false
             end)
    end

    test "bubblewrap mounts /dev for shell redirections" do
      {_exe, args, _opts} =
        Sandbox.command(:bubblewrap, "true", File.cwd!(), "/tmp/cantrip-session", [])

      assert args
             |> Enum.chunk_every(2, 1, :discard)
             |> Enum.any?(fn
               ["--dev", "/dev"] -> true
               _ -> false
             end)
    end

    test "bubblewrap denies network by default at the sandbox boundary" do
      {_exe, args, _opts} =
        Sandbox.command(:bubblewrap, "true", File.cwd!(), "/tmp/cantrip-session", [])

      assert "--unshare-net" in args
    end

    test "seatbelt profile allows /dev/null writes for shell redirects" do
      {_exe, ["-p", profile, "/bin/bash", "-c", "true"], _opts} =
        Sandbox.command(:seatbelt, "true", File.cwd!(), "/tmp/cantrip-session", [])

      assert profile =~ ~s[(allow file-write* (subpath "/dev/null"))]
      refute profile =~ ~s[(allow file-write* (subpath "/dev/zero"))]
      refute profile =~ ~s[(allow file-write* (subpath "/dev/random"))]
      refute profile =~ ~s[(allow file-write* (subpath "/dev/urandom"))]
    end

    defp runtime_with_circle(circle) do
      %{
        circle: circle,
        execute_gate: fn gate, args -> Cantrip.Gate.execute(circle, gate, args) end
      }
    end

    test "executes a simple command and returns output" do
      {state, [obs], _result, terminated} = Bash.eval("echo hello", %{}, runtime())

      assert obs.gate == "bash"
      assert String.contains?(obs.result, "hello")
      refute obs.is_error
      refute terminated
      assert state == %{}
    end

    test "non-zero exit code sets is_error" do
      {_state, [obs], _result, terminated} = Bash.eval("exit 1", %{}, runtime())

      assert obs.is_error
      refute terminated
    end

    test "SUBMIT: in output terminates and returns value" do
      {_state, [obs], result, terminated} = Bash.eval(~s[echo "SUBMIT: 42"], %{}, runtime())

      assert terminated
      assert result == "42"
      assert String.contains?(obs.result, "Task completed")
      refute obs.is_error
    end

    test "SUBMIT: works with shell expansion" do
      {_state, _obs, result, terminated} =
        Bash.eval(~s[echo "SUBMIT: $(expr 6 \\* 7)"], %{}, runtime())

      assert terminated
      assert result == "42"
    end

    test "SUBMIT: is case insensitive" do
      {_state, _obs, result, terminated} =
        Bash.eval(~s[echo "submit: done"], %{}, runtime())

      assert terminated
      assert result == "done"
    end

    test "command too long returns error" do
      long_command = String.duplicate("a", 6000)
      {_state, [obs], _result, terminated} = Bash.eval(long_command, %{}, runtime())

      assert obs.is_error
      assert String.contains?(obs.result, "too long")
      refute terminated
    end

    test "empty output becomes (no output)" do
      {_state, [obs], _result, _terminated} = Bash.eval("true", %{}, runtime())

      assert obs.result == "(no output)"
    end

    test "respects cwd option" do
      {_state, [obs], _result, _terminated} = Bash.eval("pwd", %{}, runtime(%{cwd: "/tmp"}))

      # /tmp may resolve to /private/tmp on macOS
      assert String.contains?(obs.result, "tmp")
    end

    test "captures stderr in output" do
      {_state, [obs], _result, _terminated} = Bash.eval("echo err >&2", %{}, runtime())

      assert String.contains?(obs.result, "err")
    end

    test "truncates very long output" do
      {_state, [obs], _result, _terminated} = Bash.eval("seq 1 100000", %{}, runtime())

      assert String.length(obs.result) <= 8200
      assert String.contains?(obs.result, "truncated")
    end

    test "projects declared gates as shell commands" do
      tmp =
        System.tmp_dir!() |> Path.join("cantrip-bash-test-#{System.unique_integer([:positive])}")

      File.mkdir_p!(tmp)
      on_exit(fn -> File.rm_rf(tmp) end)
      File.write!(Path.join(tmp, "note.txt"), "from gate")

      circle =
        Cantrip.Circle.new(%{
          type: :bash,
          gates: [%{name: "read_file", dependencies: %{root: tmp}}, %{name: "done"}],
          wards: [%{max_turns: 5}],
          medium_opts: %{sandbox: :passthrough}
        })

      {_state, observations, _result, terminated} =
        Bash.eval("read_file note.txt", %{}, runtime_with_circle(circle))

      refute terminated

      assert [%{gate: "read_file", result: "from gate", is_error: false}, %{gate: "bash"}] =
               observations

      assert List.last(observations).result == "from gate"
    end

    test "projected done gate terminates the bash episode" do
      circle =
        Cantrip.Circle.new(%{
          type: :bash,
          gates: [:done],
          wards: [%{max_turns: 5}],
          medium_opts: %{sandbox: :passthrough}
        })

      {_state, observations, result, terminated} =
        Bash.eval(~s[cantrip_done "from projected gate"], %{}, runtime_with_circle(circle))

      assert terminated
      assert result == "from projected gate"
      assert Enum.any?(observations, &match?(%{gate: "done", is_error: false}, &1))
    end

    if System.find_executable("sandbox-exec") &&
         System.get_env("CANTRIP_RUN_SEATBELT_TESTS") == "1" do
      test "seatbelt sandbox denies writes outside bash_writable_paths" do
        allowed =
          System.tmp_dir!()
          |> Path.join("cantrip-bash-allowed-#{System.unique_integer([:positive])}")

        denied =
          System.tmp_dir!()
          |> Path.join("cantrip-bash-denied-#{System.unique_integer([:positive])}")

        File.mkdir_p!(allowed)
        File.mkdir_p!(denied)
        on_exit(fn -> File.rm_rf(allowed) end)
        on_exit(fn -> File.rm_rf(denied) end)

        circle =
          Cantrip.Circle.new(%{
            type: :bash,
            gates: [:done],
            wards: [%{max_turns: 5}, %{bash_writable_paths: [allowed]}],
            medium_opts: %{sandbox: :seatbelt}
          })

        command =
          "echo ok > #{Path.join(allowed, "ok.txt")} && echo no > #{Path.join(denied, "no.txt")}"

        {_state, [obs], _result, terminated} =
          Bash.eval(command, %{}, %{circle: circle})

        refute terminated
        assert obs.is_error
        assert File.read!(Path.join(allowed, "ok.txt")) == "ok\n"
        refute File.exists?(Path.join(denied, "no.txt"))
      end
    end
  end

  describe "bash medium integration with cantrip" do
    test "bash circle can be constructed and validates" do
      llm =
        {FakeLLM,
         FakeLLM.new([%{tool_calls: [%{gate: "bash", args: %{command: ~s[echo "SUBMIT: ok"]}}]}])}

      assert {:ok, cantrip} =
               Cantrip.new(
                 llm: llm,
                 circle: %{
                   type: :bash,
                   gates: [:done],
                   wards: [%{max_turns: 5}],
                   medium_opts: %{sandbox: :passthrough}
                 }
               )

      assert cantrip.circle.type == :bash
    end

    test "bash medium presentation returns single bash tool with required" do
      circle =
        Cantrip.Circle.new(%{
          type: :bash,
          gates: [:done],
          wards: [%{max_turns: 5}],
          medium_opts: %{sandbox: :passthrough}
        })

      presentation = Cantrip.Medium.Registry.present(circle)

      assert length(presentation.tools) == 1
      assert hd(presentation.tools).name == "bash"
      assert presentation.tool_choice == "required"
      assert is_binary(presentation.capability_text)
      assert String.contains?(presentation.capability_text, "SUBMIT:")
    end

    test "cast with bash medium executes command and terminates via SUBMIT:" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "bash", args: %{command: "echo hello"}}]},
           %{tool_calls: [%{gate: "bash", args: %{command: ~s[echo "SUBMIT: done"]}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{
            type: :bash,
            gates: [:done],
            wards: [%{max_turns: 10}],
            medium_opts: %{sandbox: :passthrough}
          }
        )

      {:ok, result, _cantrip, loom, meta} = Cantrip.cast(cantrip, "run something")

      assert result == "done"
      assert length(loom.turns) == 2
      assert meta.terminated == true
    end

    test "bash medium truncates at max_turns" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{tool_calls: [%{gate: "bash", args: %{command: "echo turn1"}}]},
           %{tool_calls: [%{gate: "bash", args: %{command: "echo turn2"}}]},
           %{tool_calls: [%{gate: "bash", args: %{command: "echo turn3"}}]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{
            type: :bash,
            gates: [:done],
            wards: [%{max_turns: 2}],
            medium_opts: %{sandbox: :passthrough}
          }
        )

      {:ok, result, _cantrip, loom, _meta} = Cantrip.cast(cantrip, "keep going")

      assert length(loom.turns) <= 3
      assert is_nil(result)
    end
  end
end
