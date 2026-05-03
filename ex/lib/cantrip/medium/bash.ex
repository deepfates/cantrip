defmodule Cantrip.Medium.Bash do
  @moduledoc """
  Bash medium boundary.
  """

  @behaviour Cantrip.Medium

  @impl true
  def present(circle, _state) do
    %{
      tools: bash_tools(),
      tool_choice: "required",
      capability_text: Cantrip.BashMedium.capability_text(circle.medium_opts)
    }
  end

  @impl true
  def execute(command, state, runtime) when is_binary(command) do
    eval_start = System.monotonic_time()

    {next_state, observations, result, terminated?} =
      Cantrip.BashMedium.eval(command, state, runtime)

    emit_eval_stop(runtime, eval_start)

    {:ok, next_state, observations, result, terminated?}
  end

  def execute(_command, state, _runtime) do
    {:error, state, [%{gate: "bash", result: "bash utterance must be a string", is_error: true}]}
  end

  @impl true
  def snapshot(state), do: state

  @impl true
  def restore(snapshot) when is_map(snapshot), do: snapshot
  def restore(_), do: %{}

  defp emit_eval_stop(%{entity_id: entity_id}, started_at) when is_binary(entity_id) do
    duration = System.monotonic_time() - started_at
    :telemetry.execute([:cantrip, :bash, :eval], %{duration: duration}, %{entity_id: entity_id})
  end

  defp emit_eval_stop(_runtime, _started_at), do: :ok

  defp bash_tools do
    [
      %{
        name: "bash",
        description:
          "Execute a shell command. Echo a line starting with SUBMIT: to return your final result.",
        parameters: %{
          type: "object",
          properties: %{
            command: %{type: "string", description: "Shell command to execute."}
          },
          required: ["command"]
        }
      }
    ]
  end
end
