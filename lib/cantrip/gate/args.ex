defmodule Cantrip.Gate.Args do
  @moduledoc false

  defmodule Done do
    @moduledoc false
    @enforce_keys [:answer]
    defstruct [:answer]
    @type t :: %__MODULE__{answer: term()}
  end

  defmodule Echo do
    @moduledoc false
    @enforce_keys [:text]
    defstruct [:text]
    @type t :: %__MODULE__{text: term()}
  end

  defmodule ReadFile do
    @moduledoc false
    @enforce_keys [:path]
    defstruct [:path]
    @type t :: %__MODULE__{path: term()}
  end

  defmodule ListDir do
    @moduledoc false
    @enforce_keys [:path]
    defstruct [:path]
    @type t :: %__MODULE__{path: term()}
  end

  defmodule Search do
    @moduledoc false
    @enforce_keys [:pattern, :path]
    defstruct [:pattern, :path]
    @type t :: %__MODULE__{pattern: term(), path: term()}
  end

  defmodule CompileAndLoad do
    @moduledoc false
    @enforce_keys [:module, :source, :path, :sha256, :key_id, :signature]
    defstruct [:module, :source, :path, :sha256, :key_id, :signature]

    @type t :: %__MODULE__{
            module: term(),
            source: term(),
            path: term(),
            sha256: term(),
            key_id: term(),
            signature: term()
          }
  end

  defmodule Mix do
    @moduledoc false
    @enforce_keys [:task, :args, :cwd, :env]
    defstruct [:task, :args, :cwd, :env]
    @type t :: %__MODULE__{task: term(), args: term(), cwd: term(), env: term()}
  end

  defmodule Generic do
    @moduledoc false
    @enforce_keys [:value]
    defstruct [:value]
    @type t :: %__MODULE__{value: term()}
  end

  @spec new(String.t(), term()) :: {:ok, struct()} | {:error, String.t()}
  def new("done", args) do
    with {:ok, answer} <- fetch_required(args, :answer, "answer is required") do
      {:ok, %Done{answer: answer}}
    end
  end

  def new("echo", text) when is_binary(text), do: {:ok, %Echo{text: text}}

  def new("echo", args) do
    {:ok, %Echo{text: fetch(args, :text)}}
  end

  def new("read_file", path) when is_binary(path), do: {:ok, %ReadFile{path: path}}

  def new("read_file", args) do
    with {:ok, path} <- fetch_required(args, :path, "path is required") do
      {:ok, %ReadFile{path: path}}
    end
  end

  def new("list_dir", path) when is_binary(path), do: {:ok, %ListDir{path: path}}

  def new("list_dir", args) do
    with {:ok, path} <- fetch_required(args, :path, "path is required") do
      {:ok, %ListDir{path: path}}
    end
  end

  def new("search", args) do
    with {:ok, pattern} <- fetch_required(args, :pattern, "pattern is required") do
      {:ok, %Search{pattern: pattern, path: fetch(args, :path, ".")}}
    end
  end

  def new("compile_and_load", args) do
    with {:ok, module_name} <- fetch_required(args, :module, "module is required"),
         {:ok, source} <- fetch_required(args, :source, "source is required") do
      {:ok,
       %CompileAndLoad{
         module: module_name,
         source: source,
         path: fetch(args, :path),
         sha256: fetch(args, :sha256),
         key_id: fetch(args, :key_id),
         signature: fetch(args, :signature)
       }}
    end
  end

  def new("mix", task) when is_binary(task) do
    {:ok, %Mix{task: task, args: [], cwd: ".", env: %{}}}
  end

  def new("mix", args) do
    with {:ok, task} <- fetch_required(args, :task, "mix task is required") do
      {:ok,
       %Mix{
         task: task,
         args: fetch(args, :args, []),
         cwd: fetch(args, :cwd, "."),
         env: fetch(args, :env, %{})
       }}
    end
  end

  def new(_gate_name, value), do: {:ok, %Generic{value: value}}

  defp fetch_required(args, key, message) do
    case fetch(args, key, :__cantrip_missing__) do
      :__cantrip_missing__ -> {:error, message}
      value -> {:ok, value}
    end
  end

  defp fetch(args, key, default \\ nil)

  defp fetch(%{} = args, key, default) do
    cond do
      Map.has_key?(args, key) -> Map.fetch!(args, key)
      Map.has_key?(args, Atom.to_string(key)) -> Map.fetch!(args, Atom.to_string(key))
      true -> default
    end
  end

  defp fetch(_args, _key, default), do: default
end
