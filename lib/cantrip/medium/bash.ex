defmodule Cantrip.Medium.Bash do
  @moduledoc """
  Bash medium boundary and evaluator.

  Each command runs in a fresh subprocess (stateless across turns). Filesystem
  changes persist but shell state (variables, cd) resets between commands.

  Termination: The entity echoes a line starting with `SUBMIT:` to return its
  final answer. For example: `echo "SUBMIT: 42"` or `echo "SUBMIT: $(wc -l < file.txt)"`.
  Shell expansion happens before SUBMIT is detected, so computed values work.

  Gates are NOT projected into the shell. The entity interacts purely through
  commands and their stdout/stderr.
  """

  @behaviour Cantrip.Medium

  @max_output_chars 8000
  @max_command_length 5000
  @default_timeout_ms 30_000

  @impl true
  def present(circle, _state) do
    %{
      tools: bash_tools(),
      tool_choice: "required",
      capability_text: capability_text(circle.medium_opts)
    }
  end

  @impl true
  def execute(command, state, runtime) when is_binary(command) do
    eval_start = System.monotonic_time()
    {next_state, observations, result, terminated?} = eval(command, state, runtime)
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

  @spec eval(String.t(), map(), map()) ::
          {map(), list(map()), term(), boolean()}
  def eval(command, state, runtime) do
    command = String.trim(command)
    cwd = get_cwd(runtime)
    timeout = get_timeout(runtime)

    if String.length(command) > @max_command_length do
      error =
        "Error: Command too long (#{String.length(command)} chars). Maximum #{@max_command_length}."

      {state, [%{gate: "bash", result: error, is_error: true}], nil, false}
    else
      {output, exit_code} = execute_command(command, cwd, timeout)
      is_error = exit_code != 0
      output = String.trim(output)

      # Check output for SUBMIT: pattern (after shell expansion)
      case extract_submit(output) do
        {:ok, answer} ->
          observation = %{
            gate: "bash",
            result: "Task completed: #{answer}",
            is_error: false
          }

          {state, [observation], answer, true}

        :none ->
          output = if output == "", do: "(no output)", else: truncate_output(output)
          observation = %{gate: "bash", result: output, is_error: is_error}
          {state, [observation], nil, false}
      end
    end
  end

  @doc """
  Capability text describing the bash medium's physics.
  """
  def capability_text(opts \\ %{}) do
    cwd = Map.get(opts, :cwd, "the working directory")
    timeout_s = div(Map.get(opts, :timeout_ms, @default_timeout_ms), 1000)

    """
    ### SHELL PHYSICS (bash)
    1. Each command runs in a fresh subprocess (cwd: #{cwd}). Shell state (variables, cd) resets between commands. Filesystem changes persist.
    2. To return your final answer, echo a line starting with SUBMIT: — for example: `echo "SUBMIT: 42"` or `echo "SUBMIT: $(find lib -name '*.ex' | wc -l)"`. Shell expansion happens first, so computed values work.
    3. stdout and stderr are combined (truncated at #{@max_output_chars} chars).
    4. Commands time out after #{timeout_s}s. Max command length: #{@max_command_length} chars.
    """
  end

  # --- Private ---

  defp extract_submit(output) do
    output
    |> String.split("\n")
    |> Enum.find_value(:none, fn line ->
      line = String.trim(line)

      case Regex.run(~r/^SUBMIT:\s*(.+)$/i, line) do
        [_, value] -> {:ok, String.trim(value)}
        _ -> nil
      end
    end)
  end

  defp execute_command(command, cwd, timeout) do
    task =
      Task.async(fn ->
        try do
          System.cmd("bash", ["-c", command],
            cd: cwd,
            stderr_to_stdout: true
          )
        rescue
          e -> {"Error: #{Cantrip.SafeFormat.exception(e)}", 1}
        end
      end)

    case Task.yield(task, timeout) || Task.shutdown(task) do
      {:ok, result} -> result
      {:exit, reason} -> {"Error: Command task exited: #{Cantrip.SafeFormat.inspect(reason)}", 1}
      nil -> {"Error: Command timed out after #{div(timeout, 1000)}s", 124}
    end
  end

  defp truncate_output(output) do
    if String.length(output) > @max_output_chars do
      truncated = String.slice(output, 0, @max_output_chars)

      last_nl =
        case :binary.matches(truncated, "\n") do
          [] -> nil
          matches -> matches |> List.last() |> elem(0)
        end

      if last_nl && last_nl > div(@max_output_chars, 2) do
        String.slice(truncated, 0, last_nl) <> "\n... (truncated)"
      else
        truncated <> "\n... (truncated)"
      end
    else
      output
    end
  end

  defp get_cwd(runtime) do
    case runtime do
      %{circle: %{medium_opts: %{cwd: cwd}}} when is_binary(cwd) -> cwd
      _ -> File.cwd!()
    end
  end

  defp get_timeout(runtime) do
    case runtime do
      %{circle: %{medium_opts: %{timeout_ms: t}}} when is_integer(t) -> t
      _ -> @default_timeout_ms
    end
  end

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
