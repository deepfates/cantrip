defmodule Cantrip.Gate.Path do
  @moduledoc false

  # A missing path is a structured observation, not a crash. Returning an
  # observation map directly keeps callers' `with {:ok, path} <- ...` paths
  # compact while still surfacing a gate-shaped error to the entity.
  @spec validate(String.t() | nil, map()) :: {:ok, String.t()} | map()
  def validate(nil, gate), do: missing_path_observation(gate)
  def validate("", gate), do: missing_path_observation(gate)

  def validate(path, gate) do
    root = root(gate)

    if is_nil(root) do
      missing_root_observation(gate)
    else
      abs_root = real_path_or_expanded(root)
      abs_path = path |> Elixir.Path.expand(abs_root) |> real_path_or_expanded()

      if abs_path == abs_root or String.starts_with?(abs_path, abs_root <> "/") do
        {:ok, abs_path}
      else
        gate_name = Map.get(gate, :name, "gate")
        %{gate: gate_name, result: "path #{path} is outside sandbox root #{root}", is_error: true}
      end
    end
  end

  @spec root(map()) :: String.t() | nil
  def root(gate) do
    case Map.get(gate, :dependencies) || Map.get(gate, "dependencies") do
      %{} = deps -> Map.get(deps, :root) || Map.get(deps, "root")
      _ -> Map.get(gate, :root) || Map.get(gate, "root")
    end || Map.get(gate, :root) || Map.get(gate, "root")
  end

  defp real_path_or_expanded(path) do
    path
    |> Elixir.Path.expand()
    |> Elixir.Path.split()
    |> Enum.reduce(nil, fn part, acc ->
      next = if is_nil(acc), do: part, else: Elixir.Path.join(acc, part)
      resolve_symlink(next, 0)
    end)
  end

  defp resolve_symlink(path, depth) when depth >= 20, do: path

  defp resolve_symlink(path, depth) do
    case :file.read_link_info(String.to_charlist(path)) do
      {:ok,
       {:file_info, _size, :symlink, _access, _atime, _mtime, _ctime, _mode, _links, _major,
        _minor, _inode, _uid, _gid}} ->
        case :file.read_link(String.to_charlist(path)) do
          {:ok, target} ->
            target = List.to_string(target)

            target
            |> symlink_target_path(path)
            |> resolve_symlink(depth + 1)

          {:error, _reason} ->
            path
        end

      _ ->
        path
    end
  end

  defp symlink_target_path(target, link_path) do
    case Elixir.Path.type(target) do
      :absolute -> Elixir.Path.expand(target)
      _ -> target |> Elixir.Path.expand(Elixir.Path.dirname(link_path))
    end
  end

  defp missing_path_observation(gate) do
    gate_name = Map.get(gate, :name, "gate")
    %{gate: gate_name, result: "path is required", is_error: true}
  end

  defp missing_root_observation(gate) do
    gate_name = Map.get(gate, :name, "gate")
    %{gate: gate_name, result: "root dependency is required", is_error: true}
  end
end
