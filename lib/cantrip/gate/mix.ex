defmodule Cantrip.Gate.Mix do
  @moduledoc false

  alias Cantrip.Gate.Path, as: GatePath

  @default_timeout_ms 60_000
  @default_max_output_bytes 50_000

  @spec execute(map() | term(), list(map()), map()) :: map()
  def execute(args, wards, gate) do
    with {:ok, opts} <- normalize_args(args),
         :ok <- validate_task_allowed(opts.task, wards),
         {:ok, cwd} <- validate_cwd(opts.cwd, gate),
         {:ok, env} <- validate_env(opts.env),
         {:ok, mix_path} <- find_mix(gate) do
      timeout_ms = positive_ward(wards, :mix_timeout_ms, @default_timeout_ms)
      max_output_bytes = positive_ward(wards, :mix_max_output_bytes, @default_max_output_bytes)

      {result, timed_out?} =
        run_mix(mix_path, opts.task, opts.args, cwd, env, timeout_ms, max_output_bytes)

      result =
        result
        |> Map.put(:duration_ms, monotonic_ms(result.started_at, result.ended_at))
        |> Map.drop([:started_at, :ended_at])

      %{gate: "mix", result: result, is_error: timed_out? or result.exit_status != 0}
    else
      {:error, reason} ->
        %{gate: "mix", result: reason, is_error: true}

      %{is_error: _} = observation ->
        %{observation | gate: "mix"}
    end
  end

  defp normalize_args(args) when is_binary(args), do: normalize_args(%{"task" => args})

  defp normalize_args(%{} = args) do
    task = fetch(args, :task)
    argv = fetch(args, :args) || []
    cwd = fetch(args, :cwd) || "."
    env = fetch(args, :env) || %{}

    with {:ok, task} <- validate_task(task),
         {:ok, argv} <- validate_argv(argv),
         {:ok, cwd} <- validate_cwd_arg(cwd) do
      {:ok, %{task: task, args: argv, cwd: cwd, env: env}}
    end
  end

  defp normalize_args(_args), do: {:error, "mix gate args must be a map or task string"}

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))

  defp validate_task(task) when is_binary(task) do
    task = String.trim(task)

    cond do
      task == "" -> {:error, "mix task is required"}
      String.contains?(task, [" ", "\t", "\n", "\r"]) -> {:error, "mix task must be one name"}
      true -> {:ok, task}
    end
  end

  defp validate_task(_), do: {:error, "mix task is required"}

  defp validate_argv(argv) when is_list(argv) do
    if Enum.all?(argv, &is_binary/1) do
      {:ok, argv}
    else
      {:error, "mix args must be a list of strings"}
    end
  end

  defp validate_argv(_), do: {:error, "mix args must be a list of strings"}

  defp validate_cwd_arg(cwd) when is_binary(cwd), do: {:ok, cwd}
  defp validate_cwd_arg(_), do: {:error, "mix cwd must be a string"}

  defp validate_task_allowed(task, wards) do
    allow = allowed_tasks(wards)

    cond do
      allow == [] ->
        {:error, "mix task #{task} is not allowed; configure allow_mix_tasks"}

      task in allow ->
        :ok

      true ->
        {:error, "mix task #{task} is not allowed; allowed tasks: #{Enum.join(allow, ", ")}"}
    end
  end

  defp allowed_tasks(wards) do
    case Cantrip.WardPolicy.get(wards, :allow_mix_tasks, []) do
      tasks when is_list(tasks) ->
        tasks
        |> Enum.filter(&is_binary/1)
        |> Enum.map(&String.trim/1)
        |> Enum.reject(&(&1 == ""))
        |> Enum.uniq()

      _ ->
        []
    end
  end

  defp validate_cwd(cwd, gate), do: GatePath.validate(cwd, gate)

  defp validate_env(env) when env == %{}, do: {:ok, []}

  defp validate_env(%{} = env) do
    if Enum.all?(env, fn {key, value} -> is_binary(key) and is_binary(value) end) do
      env =
        Enum.map(env, fn {key, value} ->
          {String.to_charlist(key), String.to_charlist(value)}
        end)

      {:ok, env}
    else
      {:error, "mix env must be a map of string keys to string values"}
    end
  end

  defp validate_env(_), do: {:error, "mix env must be a map of string keys to string values"}

  defp find_mix(gate) do
    path = dependency(gate, :mix_path) || System.find_executable("mix")

    case path do
      nil -> {:error, "mix executable not found"}
      path -> {:ok, path}
    end
  end

  defp dependency(gate, key) do
    case Map.get(gate, :dependencies) || Map.get(gate, "dependencies") do
      %{} = deps -> Map.get(deps, key) || Map.get(deps, Atom.to_string(key))
      _ -> nil
    end
  end

  defp run_mix(mix_path, task, args, cwd, env, timeout_ms, max_output_bytes) do
    started_at = System.monotonic_time(:millisecond)
    deadline = started_at + timeout_ms

    port =
      Port.open({:spawn_executable, mix_path}, [
        :binary,
        :exit_status,
        :stderr_to_stdout,
        {:args, [task | args]},
        {:cd, cwd},
        {:env, env}
      ])

    await_port(
      port,
      %{stdout: "", exit_status: nil, started_at: started_at},
      deadline,
      max_output_bytes
    )
  end

  defp await_port(port, acc, deadline, max_output_bytes) do
    remaining_ms = max(deadline - System.monotonic_time(:millisecond), 0)

    receive do
      {^port, {:data, data}} ->
        await_port(port, append_stdout(acc, data, max_output_bytes), deadline, max_output_bytes)

      {^port, {:exit_status, status}} ->
        ended_at = System.monotonic_time(:millisecond)

        result =
          acc
          |> Map.put(:exit_status, status)
          |> Map.put(:ended_at, ended_at)
          |> Map.put(:stderr_merged, true)

        {result, false}
    after
      remaining_ms ->
        Port.close(port)
        ended_at = System.monotonic_time(:millisecond)

        result =
          acc
          |> Map.put(:exit_status, 124)
          |> Map.put(:ended_at, ended_at)
          |> Map.put(:timed_out, true)
          |> Map.put(:stderr_merged, true)

        {result, true}
    end
  end

  defp monotonic_ms(started_at, ended_at), do: max(ended_at - started_at, 0)

  defp append_stdout(acc, data, max_output_bytes) do
    current = acc.stdout
    current_size = byte_size(current)

    cond do
      current_size >= max_output_bytes ->
        Map.put(acc, :stdout_truncated, true)

      current_size + byte_size(data) <= max_output_bytes ->
        %{acc | stdout: current <> data}

      true ->
        available = max_output_bytes - current_size

        acc
        |> Map.put(:stdout, current <> binary_part(data, 0, available))
        |> Map.put(:stdout_truncated, true)
    end
  end

  defp positive_ward(wards, key, default) do
    case Cantrip.WardPolicy.get(wards, key, default) do
      value when is_integer(value) and value > 0 -> value
      _ -> default
    end
  end
end
