defmodule Cantrip.Conformance.Expect do
  @moduledoc "Expectation helpers for YAML conformance checks."

  @spec check!(map(), map()) :: :ok
  def check!(expect, result) do
    Enum.each(expect, fn {key, expected} ->
      case key do
        "result" -> assert_equal!(expected, result[:result], "result")
        :result -> assert_equal!(expected, result[:result], "result")
        "truncated" -> assert_equal!(expected, result[:meta][:truncated], "truncated")
        :truncated -> assert_equal!(expected, result[:meta][:truncated], "truncated")
        "turns" -> assert_equal!(expected, result[:meta][:turns], "turn_count")
        :turns -> assert_equal!(expected, result[:meta][:turns], "turn_count")
        _ -> :ok
      end
    end)

    :ok
  end

  defp assert_equal!(expected, actual, label) do
    if expected != actual do
      raise "expectation failed for #{label}: expected #{inspect(expected)} got #{inspect(actual)}"
    end
  end
end
