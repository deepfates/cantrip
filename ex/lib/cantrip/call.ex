defmodule Cantrip.Call do
  @moduledoc """
  Immutable call configuration (identity + crystal knobs).
  """

  defstruct system_prompt: nil,
            temperature: nil,
            tool_choice: nil,
            require_done_tool: false

  @type t :: %__MODULE__{
          system_prompt: String.t() | nil,
          temperature: number() | nil,
          tool_choice: String.t() | nil,
          require_done_tool: boolean()
        }

  @spec new(keyword() | map()) :: t()
  def new(attrs \\ %{}) do
    attrs = Map.new(attrs)

    %__MODULE__{
      system_prompt: fetch(attrs, :system_prompt),
      temperature: fetch(attrs, :temperature),
      tool_choice: fetch(attrs, :tool_choice),
      require_done_tool: fetch(attrs, :require_done_tool) || false
    }
  end

  defp fetch(map, key), do: Map.get(map, key) || Map.get(map, Atom.to_string(key))
end
