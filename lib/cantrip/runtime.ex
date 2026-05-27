defmodule Cantrip.Runtime do
  @moduledoc false

  defstruct circle: nil,
            loom: nil,
            entity_id: nil,
            execute_gate: nil,
            parent_context: nil,
            compile_and_load: nil,
            folded_summary: nil,
            observation_collector: nil,
            child_llm_ref: nil
end
