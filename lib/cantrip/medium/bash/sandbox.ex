defmodule Cantrip.Medium.Bash.Sandbox do
  @moduledoc false

  @type adapter :: :seatbelt | :bubblewrap | :passthrough

  @writable_devices ~w(/dev/null)

  @spec detect(map()) :: {:ok, adapter()} | {:error, String.t()}
  def detect(opts \\ %{}) do
    case Map.get(opts, :sandbox) || Map.get(opts, "sandbox") do
      :passthrough ->
        passthrough()

      "passthrough" ->
        passthrough()

      :seatbelt ->
        require_executable(:seatbelt, "sandbox-exec")

      "seatbelt" ->
        require_executable(:seatbelt, "sandbox-exec")

      :bubblewrap ->
        require_executable(:bubblewrap, "bwrap")

      "bubblewrap" ->
        require_executable(:bubblewrap, "bwrap")

      nil ->
        cond do
          System.find_executable("bwrap") -> {:ok, :bubblewrap}
          System.find_executable("sandbox-exec") -> {:ok, :seatbelt}
          true -> {:error, unavailable_message()}
        end

      other ->
        {:error, "unknown bash sandbox #{Cantrip.SafeFormat.inspect(other)}"}
    end
  end

  @spec command(adapter(), String.t(), String.t(), String.t(), list(String.t())) ::
          {String.t(), list(String.t()), keyword()}
  def command(:passthrough, command, cwd, _session_dir, env) do
    {"bash", ["-c", command], [cd: cwd, stderr_to_stdout: true, env: env]}
  end

  def command(:seatbelt, command, cwd, session_dir, env) do
    profile = seatbelt_profile(cwd, session_dir)

    {"sandbox-exec", ["-p", profile, "/bin/bash", "-c", command],
     [cd: cwd, stderr_to_stdout: true, env: env]}
  end

  def command(:bubblewrap, command, cwd, session_dir, env) do
    writable_binds =
      cwd
      |> configured_writable_paths()
      |> Enum.flat_map(fn path -> ["--bind", path, path] end)

    network_args =
      case Process.get(:cantrip_bash_network, :off) do
        :on -> []
        "on" -> []
        _ -> ["--unshare-net"]
      end

    args =
      [
        "--die-with-parent",
        "--new-session",
        "--unshare-pid",
        "--ro-bind",
        "/",
        "/",
        "--bind",
        session_dir,
        session_dir,
        "--dev",
        "/dev"
      ] ++
        [
          "--proc",
          "/proc",
          "--chdir",
          cwd
        ] ++
        writable_binds ++
        network_args ++
        [
          "/bin/bash",
          "-c",
          command
        ]

    {"bwrap", args, [cd: cwd, stderr_to_stdout: true, env: env]}
  end

  @spec validate_available(map()) :: :ok | {:error, String.t()}
  def validate_available(opts \\ %{}) do
    case detect(opts) do
      {:ok, _adapter} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp passthrough do
    if Mix.env() == :test do
      {:ok, :passthrough}
    else
      {:error, "bash sandbox :passthrough is only available in test"}
    end
  end

  defp require_executable(adapter, executable) do
    if System.find_executable(executable) do
      {:ok, adapter}
    else
      {:error, "bash sandbox #{adapter} requested but #{executable} was not found"}
    end
  end

  defp unavailable_message do
    "bash medium requires an OS sandbox; install bubblewrap (Linux) or use sandbox-exec (macOS)"
  end

  defp seatbelt_profile(cwd, session_dir) do
    writable_paths =
      [realpath(session_dir) | configured_writable_paths(cwd)] ++ @writable_devices

    network_rule =
      case Process.get(:cantrip_bash_network, :off) do
        :on -> ""
        "on" -> ""
        _ -> "(deny network*)"
      end

    write_rules =
      writable_paths
      |> Enum.uniq()
      |> Enum.map(fn path ->
        ~s[(allow file-write* (subpath "#{escape_profile_string(path)}"))]
      end)
      |> Enum.join("\n")

    """
    (version 1)
    (allow default)
    #{network_rule}
    (deny file-write*)
    #{write_rules}
    """
  end

  defp configured_writable_paths(cwd) do
    cwd = realpath(cwd)

    case Process.get(:cantrip_bash_writable_paths, []) do
      paths when is_list(paths) ->
        Enum.map(paths, fn path ->
          path
          |> Path.expand(cwd)
          |> realpath()
        end)

      _ ->
        []
    end
  end

  defp realpath(path) do
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

  defp escape_profile_string(value) do
    value
    |> String.replace("\\", "\\\\")
    |> String.replace("\"", "\\\"")
  end
end
