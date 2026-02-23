defmodule Cantrip.Call do
  @enforce_keys []
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

  @spec new(map() | keyword()) :: t()
  def new(attrs \\ %{}) do
    attrs = Map.new(attrs)

    %__MODULE__{
      system_prompt: Map.get(attrs, :system_prompt) || Map.get(attrs, "system_prompt"),
      temperature: Map.get(attrs, :temperature) || Map.get(attrs, "temperature"),
      tool_choice: Map.get(attrs, :tool_choice) || Map.get(attrs, "tool_choice"),
      require_done_tool:
        Map.get(attrs, :require_done_tool) || Map.get(attrs, "require_done_tool") || false
    }
  end
end
