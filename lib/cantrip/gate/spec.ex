defmodule Cantrip.Gate.Spec do
  @moduledoc false

  @type t :: %{
          description: String.t(),
          parameters: map(),
          depends_required: [atom()],
          kind: :read | :search | :edit | :execute,
          args_summary_key: atom() | nil
        }

  @spec get(String.t()) :: t()
  def get("done") do
    %{
      description: "complete the task and return the answer",
      parameters: %{
        type: "object",
        properties: %{answer: %{type: "string", description: "Your final answer"}},
        required: ["answer"]
      },
      depends_required: [],
      kind: :execute,
      args_summary_key: :answer
    }
  end

  def get("echo") do
    %{
      description: "echo text back",
      parameters: %{
        type: "object",
        properties: %{text: %{type: "string"}},
        required: []
      },
      depends_required: [],
      kind: :execute,
      args_summary_key: :text
    }
  end

  def get("read_file") do
    %{
      description: "read_file.(path) - read a file; path is relative to the working directory",
      parameters: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "path relative to the working directory"}
        },
        required: ["path"]
      },
      depends_required: [:root],
      kind: :read,
      args_summary_key: :path
    }
  end

  def get("list_dir") do
    %{
      description:
        "list_dir.(path) - list directory contents; path is relative to the working directory",
      parameters: %{
        type: "object",
        properties: %{
          path: %{type: "string", description: "path relative to the working directory"}
        },
        required: ["path"]
      },
      depends_required: [:root],
      kind: :read,
      args_summary_key: :path
    }
  end

  def get("search") do
    %{
      description:
        "search.(%{pattern: regex, path: \".\"}) - search file contents; returns a list of %{path, line, text} matches",
      parameters: %{
        type: "object",
        properties: %{
          pattern: %{type: "string", description: "regex pattern"},
          path: %{type: "string", description: "path to search; defaults to '.'"}
        },
        required: ["pattern"]
      },
      depends_required: [:root],
      kind: :search,
      args_summary_key: :pattern
    }
  end

  def get("compile_and_load") do
    %{
      description: "compile_and_load.(opts) - compile and load an Elixir module",
      parameters: %{
        type: "object",
        properties: %{
          module: %{type: "string"},
          source: %{type: "string"},
          path: %{type: "string"},
          sha256: %{type: "string"},
          key_id: %{type: "string"},
          signature: %{type: "string"}
        },
        required: ["module", "source"]
      },
      depends_required: [],
      kind: :edit,
      args_summary_key: :module
    }
  end

  def get("mix") do
    %{
      description:
        "mix.(%{task: task, args: []}) - run an allowlisted Mix task under the configured workspace root",
      parameters: %{
        type: "object",
        properties: %{
          task: %{type: "string", description: "Mix task name, such as test or compile"},
          args: %{
            type: "array",
            items: %{type: "string"},
            description: "argv strings passed to the Mix task"
          },
          cwd: %{
            type: "string",
            description: "working directory relative to the configured root; defaults to ."
          },
          env: %{
            type: "object",
            additionalProperties: %{type: "string"},
            description: "extra environment variables for the Mix process"
          }
        },
        required: ["task"]
      },
      depends_required: [:root],
      kind: :execute,
      args_summary_key: :task
    }
  end

  def get(_other) do
    %{
      description: "invoke this gate",
      parameters: %{type: "object", properties: %{}},
      depends_required: [],
      kind: :execute,
      args_summary_key: nil
    }
  end

  @spec teaching(String.t()) :: String.t() | nil
  def teaching("done") do
    """
    `done.(answer)` ends the current cast and hands `answer` back to the
    caller. The answer can be a string, list, map, or whatever shape carries
    the meaning. The loom keeps the full path you took to get there.
    """
  end

  def teaching("echo") do
    """
    `echo.(text)` or `echo.(text: text)` returns text through the gate boundary.
    Use it for simple instrumentation and smoke tests, not for final answers.
    """
  end

  def teaching("read_file") do
    """
    `read_file.(path: path)` reads one file. Relative paths resolve against the
    gate's configured root. The function returns file content on success and
    an error string on failure; the full observation is recorded in the loom.
    """
  end

  def teaching("list_dir") do
    """
    `list_dir.(path: ".")` returns the direct children of a directory as a list
    of plain strings. Use `Enum.*` on the names directly.
    """
  end

  def teaching("search") do
    """
    `search.(%{pattern: regex, path: "."})` searches file contents and returns a
    list of `%{path, line, text}` matches. Use it to locate relevant files before
    deciding which child should read or interpret them.
    """
  end

  def teaching("compile_and_load") do
    """
    `compile_and_load.(%{module: module_name, source: source})` compiles and
    hot-loads an Elixir module into the running BEAM. This is an evolutionary
    surface: when a task recurs and you find yourself rebuilding the same shape,
    lift that shape into a module.

    Familiars expose this gate only when constructed with `evolve: true`, and
    the default ward allows only `Elixir.Cantrip.Hot.Tally`. Reuse that module
    name for iterative evolution instead of inventing fresh module names.

        compile_and_load.(%{
          module: "Elixir.Cantrip.Hot.Tally",
          source: \"\"\"
          defmodule Cantrip.Hot.Tally do
            def sum(list), do: Enum.sum(list)
          end
          \"\"\"
        })

        total = Cantrip.Hot.Tally.sum([1, 2, 3])

    The loom records what you tried; supervision and BEAM hot-code-loading
    semantics let the runtime continue with the previous version if the new
    code fails.
    """
  end

  def teaching("mix") do
    """
    `mix.(%{task: "test", args: ["test/some_test.exs"]})` runs an allowlisted
    Mix task inside the workspace root. Use it for project-native verification:
    compile, format checks, or focused tests. The result is a map with
    `exit_status`, `stdout`, `stderr`, and `duration_ms`; non-zero status and
    timeout return as error observations.
    """
  end

  def teaching(_other), do: nil
end
