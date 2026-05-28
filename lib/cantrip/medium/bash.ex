defmodule Cantrip.Medium.Bash do
  @moduledoc false

  @behaviour Cantrip.Medium

  alias Cantrip.Medium.Bash.Sandbox

  @max_output_chars 8000
  @max_command_length 5000
  @default_timeout_ms 30_000
  @default_shell_path "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
  # 60_000 * 10ms poll interval = ~10 minutes max wait for a host gate response.
  @gate_response_poll_limit 60_000

  @impl true
  def present(circle, _state) do
    %{
      tools: bash_tools(),
      tool_choice: "required",
      capability_text: capability_text(circle)
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

  @spec validate_circle(Cantrip.Circle.t()) :: :ok | {:error, String.t()}
  def validate_circle(%Cantrip.Circle{medium_opts: opts}), do: Sandbox.validate_available(opts)

  @spec eval(String.t(), map(), map()) ::
          {map(), list(map()), term(), boolean()}
  def eval(command, state, runtime) do
    command = String.trim(command)
    cwd = get_cwd(runtime)
    timeout = get_timeout(runtime)
    max_output = get_max_output(runtime)

    if String.length(command) > @max_command_length do
      error =
        "Error: Command too long (#{String.length(command)} chars). Maximum #{@max_command_length}."

      {state, [%{gate: "bash", result: error, is_error: true}], nil, false}
    else
      {output, exit_code, gate_observations} = execute_command(command, cwd, timeout, runtime)
      is_error = exit_code != 0
      output = String.trim(output)

      # Check output for SUBMIT: pattern (after shell expansion)
      case completion(gate_observations, output) do
        {:ok, answer} ->
          observation = %{
            gate: "bash",
            result: "Task completed: #{answer}",
            is_error: false
          }

          {state, gate_observations ++ [observation], answer, true}

        :none ->
          output = if output == "", do: "(no output)", else: truncate_output(output, max_output)
          observation = %{gate: "bash", result: output, is_error: is_error}
          {state, gate_observations ++ [observation], nil, false}
      end
    end
  end

  @doc """
  Capability text describing the bash medium's physics.
  """
  def capability_text(%Cantrip.Circle{} = circle) do
    opts = circle.medium_opts
    cwd = Map.get(opts, :cwd, "the working directory")
    timeout_s = div(Map.get(opts, :timeout_ms, @default_timeout_ms), 1000)
    gate_text = gate_projection_text(circle)

    """
    ### SHELL PHYSICS (bash)
    1. Each command runs in a fresh subprocess (cwd: #{cwd}). Shell state (variables, cd) resets between commands. Filesystem changes persist.
    2. Declared gates are available as commands on PATH. Call `cantrip_done "answer"` to return your final answer. `SUBMIT:` output also works for shell-only answers.
    3. stdout and stderr are combined (truncated at #{@max_output_chars} chars).
    4. Commands time out after #{timeout_s}s. Max command length: #{@max_command_length} chars.
    5. The OS sandbox denies network and file writes by default; `%{bash_network: :on}` and `%{bash_writable_paths: [...]}` wards widen those boundaries.
    #{gate_text}
    """
  end

  def capability_text(opts) when is_map(opts) do
    capability_text(%Cantrip.Circle{type: :bash, medium_opts: opts, gates: %{}})
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

  defp gate_projection_text(%Cantrip.Circle{gates: gates}) when map_size(gates) == 0 do
    ""
  end

  defp gate_projection_text(%Cantrip.Circle{gates: gates}) do
    gates
    |> Map.keys()
    |> Enum.reject(&(&1 == "bash"))
    |> Enum.sort()
    |> Enum.map(&gate_command_text/1)
    |> case do
      [] ->
        ""

      lines ->
        """

        ### PROJECTED GATES
        #{Enum.join(lines, "\n")}
        """
    end
  end

  defp gate_command_text("done"),
    do: "- `cantrip_done \"answer\"` returns the final answer (`done` is a shell keyword)."

  defp gate_command_text("echo"), do: "- `echo \"text\"` echoes through the host gate."

  defp gate_command_text("read_file"),
    do: "- `read_file PATH` reads a file through its scoped gate root."

  defp gate_command_text("list_dir"),
    do: "- `list_dir PATH` lists a directory through its scoped gate root."

  defp gate_command_text("search"),
    do: "- `search PATTERN [PATH]` searches through its scoped gate root."

  defp gate_command_text("mix"), do: "- `mix TASK [ARGS...]` runs an allowlisted Mix task."
  defp gate_command_text(name), do: "- `#{name} [JSON_OR_ARGS...]` invokes the #{name} gate."

  defp execute_command(command, cwd, timeout, runtime) do
    telemetry_context = Cantrip.Telemetry.current_context()
    adapter = sandbox_adapter(runtime)
    writable_paths = bash_writable_paths(runtime)
    network = bash_network(runtime)

    {:ok, session} = start_gate_session(runtime)

    task =
      Task.async(fn ->
        with_telemetry_context(telemetry_context, fn ->
          try do
            Process.put(:cantrip_bash_writable_paths, writable_paths)
            Process.put(:cantrip_bash_network, network)
            env = gate_env(session)
            {executable, args, opts} = Sandbox.command(adapter, command, cwd, session.dir, env)
            System.cmd(executable, args, opts)
          rescue
            e -> {"Error: #{Cantrip.SafeFormat.exception(e)}", 1}
          after
            Process.delete(:cantrip_bash_writable_paths)
            Process.delete(:cantrip_bash_network)
          end
        end)
      end)

    {output, exit_code} =
      case Task.yield(task, timeout) || Task.shutdown(task) do
        {:ok, result} ->
          result

        {:exit, reason} ->
          {"Error: Command task exited: #{Cantrip.SafeFormat.inspect(reason)}", 1}

        nil ->
          {"Error: Command timed out after #{div(timeout, 1000)}s", 124}
      end

    gate_observations = stop_gate_session(session)
    {output, exit_code, gate_observations}
  end

  defp sandbox_adapter(runtime) do
    opts =
      case runtime do
        %{circle: %{medium_opts: opts}} -> opts
        _ -> %{}
      end

    case Sandbox.detect(opts) do
      {:ok, adapter} -> adapter
      {:error, reason} -> raise reason
    end
  end

  defp bash_writable_paths(runtime) do
    runtime_wards(runtime)
    |> Enum.flat_map(fn
      %{bash_writable_paths: paths} when is_list(paths) -> paths
      %{"bash_writable_paths" => paths} when is_list(paths) -> paths
      _ -> []
    end)
  end

  defp bash_network(runtime) do
    runtime
    |> runtime_wards()
    |> Enum.find_value(:off, fn
      %{bash_network: value} -> value
      %{"bash_network" => value} -> value
      _ -> nil
    end)
  end

  defp runtime_wards(%{circle: %{wards: wards}}) when is_list(wards), do: wards
  defp runtime_wards(_runtime), do: []

  defp start_gate_session(runtime) do
    dir = Path.join(System.tmp_dir!(), "cantrip-bash-#{System.unique_integer([:positive])}")
    bin_dir = Path.join(dir, "bin")
    calls_dir = Path.join(dir, "calls")
    responses_dir = Path.join(dir, "responses")

    with :ok <- File.mkdir_p(bin_dir),
         :ok <- File.mkdir_p(calls_dir),
         :ok <- File.mkdir_p(responses_dir),
         :ok <- write_gate_wrappers(runtime, bin_dir) do
      owner = self()
      ref = make_ref()

      server =
        Task.async(fn ->
          gate_server_loop(calls_dir, responses_dir, runtime, owner, ref, MapSet.new())
        end)

      {:ok,
       %{
         dir: dir,
         bin_dir: bin_dir,
         calls_dir: calls_dir,
         responses_dir: responses_dir,
         server: server,
         ref: ref
       }}
    else
      error ->
        File.rm_rf(dir)
        raise "failed to start bash gate session: #{Cantrip.SafeFormat.inspect(error)}"
    end
  end

  defp stop_gate_session(session) do
    try do
      send(session.server.pid, :stop)
      _ = Task.yield(session.server, 5_000) || Task.shutdown(session.server, :brutal_kill)
      drain_gate_observations(session.ref, [])
    after
      File.rm_rf(session.dir)
    end
  end

  defp drain_gate_observations(ref, acc) do
    receive do
      {:cantrip_bash_gate_observation, ^ref, observation} ->
        drain_gate_observations(ref, [observation | acc])
    after
      0 -> Enum.reverse(acc)
    end
  end

  defp gate_env(session) do
    [
      {"PATH", session.bin_dir <> ":" <> @default_shell_path},
      {"CANTRIP_BASH_CALLS_DIR", session.calls_dir},
      {"CANTRIP_BASH_RESPONSES_DIR", session.responses_dir}
    ]
  end

  defp write_gate_wrappers(%{circle: %{gates: gates}}, bin_dir) when is_map(gates) do
    gates
    |> Map.keys()
    |> Enum.reject(&(&1 == "bash"))
    |> Enum.each(fn gate_name ->
      path = Path.join(bin_dir, gate_name)
      File.write!(path, wrapper_script(gate_name))
      File.chmod!(path, 0o700)

      if gate_name == "done" do
        alias_path = Path.join(bin_dir, "cantrip_done")
        File.write!(alias_path, wrapper_script("done"))
        File.chmod!(alias_path, 0o700)
      end
    end)

    :ok
  end

  defp write_gate_wrappers(_runtime, _bin_dir), do: :ok

  defp wrapper_script(gate_name) do
    """
    #!/bin/sh
    set -eu
    call_id="$$-$(date +%s%N)"
    call_dir="$CANTRIP_BASH_CALLS_DIR/$call_id"
    mkdir -p "$call_dir/args"
    i=0
    for arg in "$@"; do
      printf '%s' "$arg" > "$call_dir/args/$i"
      i=$((i + 1))
    done
    : > "$call_dir/stdin"
    printf '%s' "#{gate_name}" > "$call_dir/gate"
    : > "$call_dir/ready"
    response="$CANTRIP_BASH_RESPONSES_DIR/$call_id.stdout"
    exit_file="$CANTRIP_BASH_RESPONSES_DIR/$call_id.exit"
    i=0
    while [ ! -f "$exit_file" ] && [ "$i" -lt #{@gate_response_poll_limit} ]; do
      sleep 0.01
      i=$((i + 1))
    done
    if [ ! -f "$exit_file" ]; then
      printf '%s\n' "cantrip gate #{gate_name} timed out waiting for host response" >&2
      exit 124
    fi
    if [ -f "$response" ]; then cat "$response"; fi
    exit "$(cat "$exit_file")"
    """
  end

  defp gate_server_loop(calls_dir, responses_dir, runtime, owner, ref, seen) do
    receive do
      :stop ->
        process_ready_calls(calls_dir, responses_dir, runtime, owner, ref, seen)
        :ok
    after
      10 ->
        seen = process_ready_calls(calls_dir, responses_dir, runtime, owner, ref, seen)
        gate_server_loop(calls_dir, responses_dir, runtime, owner, ref, seen)
    end
  end

  defp process_ready_calls(calls_dir, responses_dir, runtime, owner, ref, seen) do
    calls_dir
    |> File.ls!()
    |> Enum.reduce(seen, fn call_id, seen ->
      call_dir = Path.join(calls_dir, call_id)

      cond do
        MapSet.member?(seen, call_id) ->
          seen

        not File.exists?(Path.join(call_dir, "ready")) ->
          seen

        true ->
          observation = execute_shell_gate(runtime, call_dir)
          send(owner, {:cantrip_bash_gate_observation, ref, observation})
          write_gate_response(responses_dir, call_id, observation)
          MapSet.put(seen, call_id)
      end
    end)
  end

  defp execute_shell_gate(runtime, call_dir) do
    gate = File.read!(Path.join(call_dir, "gate"))
    args = read_shell_args(call_dir)
    stdin = read_file(Path.join(call_dir, "stdin"))
    gate_args = shell_gate_args(gate, args, stdin)

    case Map.get(runtime, :execute_gate) do
      execute_gate when is_function(execute_gate, 2) -> execute_gate.(gate, gate_args)
      _ -> Cantrip.Gate.execute(runtime.circle, gate, gate_args)
    end
  rescue
    e ->
      %{gate: "bash", result: Cantrip.SafeFormat.exception(e), is_error: true}
  end

  defp read_shell_args(call_dir) do
    args_dir = Path.join(call_dir, "args")

    args_dir
    |> File.ls!()
    |> Enum.sort_by(&String.to_integer/1)
    |> Enum.map(fn file -> File.read!(Path.join(args_dir, file)) end)
  end

  defp read_file(path) do
    case File.read(path) do
      {:ok, content} -> content
      _ -> ""
    end
  end

  defp shell_gate_args(gate, [json], _stdin) when is_binary(json) do
    case Jason.decode(json) do
      {:ok, decoded} when is_map(decoded) -> decoded
      _ -> shell_gate_args_from_words(gate, [json], "")
    end
  end

  defp shell_gate_args(gate, [], stdin) when stdin != "" do
    shell_gate_args_from_words(gate, [String.trim_trailing(stdin)], stdin)
  end

  defp shell_gate_args(gate, args, stdin), do: shell_gate_args_from_words(gate, args, stdin)

  defp shell_gate_args_from_words("done", args, stdin),
    do: %{answer: text_arg(args, stdin)}

  defp shell_gate_args_from_words("echo", args, stdin),
    do: %{text: text_arg(args, stdin)}

  defp shell_gate_args_from_words("read_file", [path | _], _stdin), do: %{path: path}
  defp shell_gate_args_from_words("list_dir", [path | _], _stdin), do: %{path: path}

  defp shell_gate_args_from_words("search", [pattern, path | _], _stdin),
    do: %{pattern: pattern, path: path}

  defp shell_gate_args_from_words("search", [pattern | _], _stdin),
    do: %{pattern: pattern, path: "."}

  defp shell_gate_args_from_words("mix", [task | args], _stdin),
    do: %{task: task, args: args}

  defp shell_gate_args_from_words(_gate, args, stdin), do: text_arg(args, stdin)

  defp text_arg([], stdin), do: String.trim_trailing(stdin)
  defp text_arg(args, _stdin), do: Enum.join(args, " ")

  defp write_gate_response(responses_dir, call_id, observation) do
    stdout_path = Path.join(responses_dir, call_id <> ".stdout")
    exit_path = Path.join(responses_dir, call_id <> ".exit")

    File.write!(stdout_path, observation_result_text(observation))
    File.write!(exit_path, if(observation.is_error, do: "1", else: "0"))
  end

  defp observation_result_text(%{result: result}) when is_binary(result), do: result

  defp observation_result_text(%{result: result}) when is_list(result) do
    if Enum.all?(result, &is_binary/1), do: Enum.join(result, "\n"), else: Jason.encode!(result)
  end

  defp observation_result_text(%{result: result}) when is_map(result), do: Jason.encode!(result)
  defp observation_result_text(%{result: result}), do: to_string(result)

  defp gate_done(observations) do
    Enum.find_value(observations, :none, fn
      %{gate: "done", is_error: false, result: result} -> {:ok, result}
      _ -> nil
    end)
  end

  defp completion(gate_observations, output) do
    case gate_done(gate_observations) do
      {:ok, answer} -> {:ok, answer}
      :none -> extract_submit(output)
    end
  end

  defp with_telemetry_context(%{entity_id: entity_id, trace_id: trace_id}, fun)
       when is_function(fun, 0) do
    Cantrip.Telemetry.with_context(entity_id, trace_id, fun)
  end

  defp with_telemetry_context(_context, fun) when is_function(fun, 0), do: fun.()

  defp truncate_output(output, max_output_chars) do
    if String.length(output) > max_output_chars do
      truncated = String.slice(output, 0, max_output_chars)

      last_nl =
        case :binary.matches(truncated, "\n") do
          [] -> nil
          matches -> matches |> List.last() |> elem(0)
        end

      if last_nl && last_nl > div(max_output_chars, 2) do
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
    ward_timeout =
      case runtime do
        %{circle: %{wards: wards}} when is_list(wards) ->
          Enum.find_value(wards, fn
            %{bash_timeout_ms: value} when is_integer(value) and value > 0 -> value
            %{"bash_timeout_ms" => value} when is_integer(value) and value > 0 -> value
            _ -> nil
          end)

        _ ->
          nil
      end

    case ward_timeout do
      value when is_integer(value) ->
        value

      _ ->
        case runtime do
          %{circle: %{medium_opts: %{timeout_ms: t}}} when is_integer(t) -> t
          _ -> @default_timeout_ms
        end
    end
  end

  defp get_max_output(runtime) do
    case runtime do
      %{circle: %{wards: wards}} when is_list(wards) ->
        Enum.find_value(wards, @max_output_chars, fn
          %{bash_max_output_bytes: value} when is_integer(value) and value > 0 -> value
          %{"bash_max_output_bytes" => value} when is_integer(value) and value > 0 -> value
          _ -> nil
        end)

      _ ->
        @max_output_chars
    end
  end

  defp emit_eval_stop(%{entity_id: entity_id, trace_id: trace_id}, started_at)
       when is_binary(entity_id) do
    duration = System.monotonic_time() - started_at

    Cantrip.Telemetry.execute(
      [:cantrip, :bash, :eval],
      %{duration: duration},
      %{entity_id: entity_id, trace_id: trace_id}
    )
  end

  defp emit_eval_stop(_runtime, _started_at), do: :ok

  defp bash_tools do
    [
      %{
        name: "bash",
        description:
          "Execute a sandboxed shell command. Declared gates are available as commands; use cantrip_done or SUBMIT: to return the final result.",
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
