defmodule Cantrip.Examples do
  @moduledoc """
  Runnable pattern catalog (01..16) built on top of Cantrip primitives.
  """

  alias Cantrip.FakeCrystal

  @ids Enum.map(1..16, &String.pad_leading(Integer.to_string(&1), 2, "0"))

  def ids, do: @ids

  def catalog do
    [
      {"01", "Minimal Crystal + done"},
      {"02", "Gate Primitive Loop"},
      {"03", "Require done tool"},
      {"04", "Truncation ward"},
      {"05", "Done ordering"},
      {"06", "Provider portability (env)"},
      {"07", "Conversation medium"},
      {"08", "Code medium"},
      {"09", "Stateful code turns"},
      {"10", "Parallel delegation"},
      {"11", "Folding"},
      {"12", "Full code agent"},
      {"13", "ACP-ready cantrip"},
      {"14", "Recursive delegation"},
      {"15", "Research-style read gate"},
      {"16", "Familiar-style persistent loom"}
    ]
    |> Enum.map(fn {id, title} -> %{id: id, title: title} end)
  end

  def run(id, opts \\ %{}) when is_binary(id) do
    opts = Map.new(opts)

    with {:ok, {intent, cantrip}} <- build(id, opts),
         {:ok, result, next_cantrip, loom, meta} <- Cantrip.cast(cantrip, intent) do
      {:ok, result, next_cantrip, loom, meta}
    end
  end

  defp build("01", opts), do: build_basic("pattern 01", %{gates: [:done]}, opts)
  defp build("02", opts), do: build_basic("pattern 02", %{gates: [:done, :echo]}, opts)

  defp build("03", opts) do
    build_basic("pattern 03", %{gates: [:done], call: %{require_done_tool: true}}, opts)
  end

  defp build("04", opts),
    do: build_basic("pattern 04", %{gates: [:done, :echo], max_turns: 2}, opts)

  defp build("05", opts), do: build_basic("pattern 05", %{gates: [:done, :echo]}, opts)
  defp build("06", opts), do: build_from_env("pattern 06", opts)

  defp build("07", opts),
    do: build_basic("pattern 07", %{gates: [:done, :echo], type: :conversation}, opts)

  defp build("08", opts), do: build_basic("pattern 08", %{gates: [:done], type: :code}, opts)

  defp build("09", opts),
    do: build_basic("pattern 09", %{gates: [:done, :echo], type: :code}, opts)

  defp build("10", opts) do
    build_basic(
      "pattern 10",
      %{gates: [:done, :call_agent, :call_agent_batch], type: :code, max_depth: 1},
      opts
    )
  end

  defp build("11", opts) do
    build_basic("pattern 11", %{gates: [:done, :echo], folding: %{trigger_after_turns: 2}}, opts)
  end

  defp build("12", opts),
    do: build_basic("pattern 12", %{gates: [:done, :read], type: :code}, opts)

  defp build("13", opts), do: build_basic("pattern 13", %{gates: [:done, :echo]}, opts)

  defp build("14", opts),
    do: build_basic("pattern 14", %{gates: [:done, :call_agent], type: :code, max_depth: 2}, opts)

  defp build("15", opts),
    do: build_basic("pattern 15", %{gates: [:done, :read], type: :code}, opts)

  defp build("16", opts) do
    storage =
      Map.get(
        opts,
        :loom_storage,
        {:jsonl, Path.join(System.tmp_dir!(), "cantrip_familiar.jsonl")}
      )

    build_basic(
      "pattern 16",
      %{gates: [:done, :call_agent, :call_agent_batch], type: :code, loom_storage: storage},
      opts
    )
  end

  defp build(_, _opts), do: {:error, "unknown pattern id"}

  defp build_basic(intent, spec, opts) do
    crystal = Map.get(opts, :crystal, default_crystal())
    child_crystal = Map.get(opts, :child_crystal, crystal)
    type = Map.get(spec, :type, :conversation)
    gates = Map.get(spec, :gates, [:done])
    max_turns = Map.get(spec, :max_turns, 12)

    wards =
      [%{max_turns: max_turns}]
      |> maybe_put_ward(:max_depth, Map.get(spec, :max_depth))

    attrs = %{
      crystal: crystal,
      child_crystal: child_crystal,
      call: Map.get(spec, :call, %{}),
      circle: %{type: type, gates: gates, wards: wards},
      folding: Map.get(spec, :folding, %{}),
      loom_storage: Map.get(spec, :loom_storage)
    }

    case Cantrip.new(Enum.reject(attrs, fn {_k, v} -> is_nil(v) end)) do
      {:ok, cantrip} -> {:ok, {intent, cantrip}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp build_from_env(intent, opts) do
    attrs = %{
      circle: %{gates: [:done, :echo], wards: [%{max_turns: 12}]},
      call: Map.get(opts, :call, %{})
    }

    case Cantrip.new_from_env(attrs) do
      {:ok, cantrip} -> {:ok, {intent, cantrip}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_put_ward(wards, _key, nil), do: wards
  defp maybe_put_ward(wards, key, value), do: wards ++ [%{key => value}]

  defp default_crystal do
    {FakeCrystal, FakeCrystal.new([%{tool_calls: [%{gate: "done", args: %{answer: "ok"}}]}])}
  end
end
