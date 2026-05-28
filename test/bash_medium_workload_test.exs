defmodule Cantrip.Medium.BashWorkloadTest do
  use ExUnit.Case, async: false

  alias Cantrip.Medium.Bash

  @workload_tools ~w(git jq make)

  defp runtime(adapter, cwd) do
    circle =
      Cantrip.Circle.new(%{
        type: :bash,
        gates: [:done],
        wards: [
          %{max_turns: 5},
          %{bash_writable_paths: [cwd]},
          %{bash_network: :on},
          %{bash_timeout_ms: 15_000}
        ],
        medium_opts: %{sandbox: adapter, cwd: cwd, timeout_ms: 15_000}
      })

    %{circle: circle}
  end

  defp prepare_workspace! do
    root =
      System.tmp_dir!()
      |> Path.join("cantrip-bash-workload-#{System.unique_integer([:positive])}")

    File.mkdir_p!(root)
    File.write!(Path.join(root, "data.json"), ~s({"name":"cantrip","count":3}\n))
    File.write!(Path.join(root, "note.txt"), "hello\n")

    File.write!(Path.join(root, "Makefile"), """
    hello:
    \t@printf 'make-ok\\n'
    """)

    run!(root, "git", ["init", "-q"])
    run!(root, "git", ["config", "user.email", "cantrip@example.invalid"])
    run!(root, "git", ["config", "user.name", "Cantrip Test"])
    run!(root, "git", ["config", "commit.gpgsign", "false"])
    File.mkdir_p!(Path.join(root, ".git/hooks-disabled"))
    run!(root, "git", ["config", "core.hooksPath", ".git/hooks-disabled"])
    run!(root, "git", ["add", "data.json", "note.txt", "Makefile"])
    run!(root, "git", ["-c", "commit.gpgsign=false", "commit", "-q", "-m", "fixture"])

    root
  end

  defp run!(cwd, executable, args) do
    case System.cmd(executable, args, cd: cwd, stderr_to_stdout: true) do
      {_output, 0} ->
        :ok

      {output, exit_code} ->
        flunk("#{executable} #{Enum.join(args, " ")} failed with #{exit_code}: #{output}")
    end
  end

  defp assert_tools_available! do
    missing = Enum.reject(@workload_tools, &System.find_executable/1)
    assert missing == [], "missing shell workload tools: #{Enum.join(missing, ", ")}"
  end

  defp assert_workloads(adapter) do
    assert_tools_available!()
    root = prepare_workspace!()
    on_exit(fn -> File.rm_rf(root) end)

    workloads = [
      {"git can write /dev/null", "git log -1 --stat >/dev/null && echo 'SUBMIT: git-ok'",
       "git-ok"},
      {"jq survives stderr redirects",
       "jq -r '.name' data.json 2>/dev/null | grep cantrip >/dev/null && echo 'SUBMIT: jq-ok'",
       "jq-ok"},
      {"make can run a target", "make hello >/dev/null && echo 'SUBMIT: make-ok'", "make-ok"},
      {"find/sed/grep pipeline works",
       "find . -name '*.txt' | sed 's#^./##' | grep '^note.txt$' >/dev/null && echo 'SUBMIT: find-ok'",
       "find-ok"}
    ]

    for {name, command, expected} <- workloads do
      {_state, observations, result, terminated?} =
        Bash.eval(command, %{}, runtime(adapter, root))

      assert terminated?,
             "#{adapter} workload did not terminate: #{name}\nobservations: #{inspect(observations)}"

      assert result == expected

      refute List.last(observations).is_error,
             "#{adapter} workload errored: #{name}\nobservations: #{inspect(observations)}"
    end
  end

  if System.find_executable("bwrap") do
    test "bubblewrap sandbox supports representative shell workloads" do
      assert_workloads(:bubblewrap)
    end
  end

  if System.find_executable("sandbox-exec") do
    test "seatbelt sandbox supports representative shell workloads" do
      assert_workloads(:seatbelt)
    end
  end
end
