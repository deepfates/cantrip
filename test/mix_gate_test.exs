defmodule Cantrip.MixGateTest do
  use ExUnit.Case, async: true

  alias Cantrip.Circle

  setup do
    root = Path.join(System.tmp_dir!(), "cantrip_mix_gate_#{System.unique_integer([:positive])}")
    File.mkdir_p!(root)

    mix_path = Path.join(root, "fake_mix")

    File.write!(mix_path, """
    #!/bin/sh
    if [ "$1" = "sleep" ]; then
      sleep 1
      exit 0
    fi
    if [ "$1" = "noisy" ]; then
      printf '1234567890abcdef'
      exit 0
    fi
    printf 'task=%s\\n' "$1"
    shift
    printf 'args=%s\\n' "$*"
    printf 'cwd=%s\\n' "$(pwd)"
    printf 'env=%s\\n' "$CANTRIP_MIX_GATE_ENV"
    """)

    File.chmod!(mix_path, 0o755)
    on_exit(fn -> File.rm_rf!(root) end)

    %{root: root, mix_path: mix_path}
  end

  defp circle(root, mix_path, wards \\ []) do
    Circle.new(%{
      type: :conversation,
      gates: [
        %{name: "mix", dependencies: %{root: root, mix_path: mix_path}},
        %{name: "done"}
      ],
      wards: wards
    })
  end

  test "runs an allowlisted task under the configured root", %{root: root, mix_path: mix_path} do
    circle =
      circle(root, mix_path, [
        %{allow_mix_tasks: ["test"], mix_timeout_ms: 1_000, max_output_bytes: 50_000}
      ])

    obs =
      Cantrip.Gate.execute(circle, "mix", %{
        "task" => "test",
        "args" => ["test/example_test.exs"],
        "env" => %{"CANTRIP_MIX_GATE_ENV" => "visible"}
      })

    assert obs.is_error == false
    assert obs.result.exit_status == 0
    assert obs.result.stderr == ""
    assert obs.result.stderr_merged == true
    assert obs.result.stdout =~ "task=test"
    assert obs.result.stdout =~ "args=test/example_test.exs"
    assert obs.result.stdout =~ "cantrip_mix_gate_"
    assert obs.result.stdout =~ "env=visible"
    assert is_integer(obs.result.duration_ms)
  end

  test "fails closed without an allow_mix_tasks ward", %{root: root, mix_path: mix_path} do
    obs = Cantrip.Gate.execute(circle(root, mix_path), "mix", %{"task" => "test"})

    assert obs.is_error == true
    assert obs.result =~ "allow_mix_tasks"
  end

  test "rejects tasks outside the allowlist", %{root: root, mix_path: mix_path} do
    obs =
      root
      |> circle(mix_path, [%{allow_mix_tasks: ["test"]}])
      |> Cantrip.Gate.execute("mix", %{"task" => "deps.clean"})

    assert obs.is_error == true
    assert obs.result =~ "not allowed"
    assert obs.result =~ "test"
  end

  test "rejects cwd traversal outside the root", %{root: root, mix_path: mix_path} do
    obs =
      root
      |> circle(mix_path, [%{allow_mix_tasks: ["test"]}])
      |> Cantrip.Gate.execute("mix", %{"task" => "test", "cwd" => "../../.."})

    assert obs.is_error == true
    assert obs.result =~ "outside sandbox root"
  end

  test "times out and returns a structured observation", %{root: root, mix_path: mix_path} do
    obs =
      root
      |> circle(mix_path, [%{allow_mix_tasks: ["sleep"], mix_timeout_ms: 20}])
      |> Cantrip.Gate.execute("mix", %{"task" => "sleep"})

    assert obs.is_error == true
    assert obs.result.exit_status == 124
    assert obs.result.timed_out == true
  end

  test "bounds output while preserving structured result", %{root: root, mix_path: mix_path} do
    obs =
      root
      |> circle(mix_path, [%{allow_mix_tasks: ["noisy"], max_output_bytes: 8}])
      |> Cantrip.Gate.execute("mix", %{"task" => "noisy"})

    assert obs.is_error == false
    assert obs.result.stdout == "12345678"
    assert obs.result.stdout_truncated == true
  end

  test "code medium exposes mix as a callable gate", %{root: root, mix_path: mix_path} do
    circle =
      Circle.new(%{
        type: :code,
        gates: [
          %{name: "done"},
          %{name: "mix", dependencies: %{root: root, mix_path: mix_path}}
        ],
        wards: [%{allow_mix_tasks: ["compile"], mix_timeout_ms: 1_000}]
      })

    runtime = %{
      circle: circle,
      execute_gate: fn gate_name, args ->
        Cantrip.Gate.execute(circle, gate_name, args)
      end
    }

    {_state, observations, result, terminated?} =
      Cantrip.Medium.Code.eval(
        ~s|result = mix.(%{task: "compile", args: ["--warnings-as-errors"]})
           done.(result.exit_status)|,
        %{},
        runtime
      )

    assert terminated?
    assert result == 0
    assert Enum.any?(observations, &(&1.gate == "mix" and &1.result.stdout =~ "task=compile"))
  end
end
