defmodule Cantrip.Conformance.TestCase do
  @enforce_keys [:id, :description, :setup, :action, :expect]
  defstruct [:id, :description, :setup, :action, :expect]

  @type t :: %__MODULE__{
          id: String.t(),
          description: String.t(),
          setup: map(),
          action: map() | list(map()),
          expect: map()
        }
end
