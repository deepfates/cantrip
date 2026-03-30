defmodule DuneSandboxTest do
  @moduledoc """
  Tests for the Dune-based sandboxed code evaluation path.

  Verifies that:
  1. Basic Elixir code works (maps, enums, pattern matching)
  2. File.read is blocked
  3. System.cmd is blocked
  4. Bindings persist across turns
  5. Gate closures (done., echo.) work
  6. The sandbox is opt-in via %{sandbox: :dune} ward
  """
  use ExUnit.Case, async: false

  alias Cantrip.FakeLLM

  # -- helpers --

  defp dune_cantrip(llm, opts \\ []) do
    gates = Keyword.get(opts, :gates, [:done, :echo])
    extra_wards = Keyword.get(opts, :extra_wards, [])
    wards = [%{max_turns: 10}, %{sandbox: :dune}] ++ extra_wards

    Cantrip.new(
      llm: llm,
      circle: %{type: :code, gates: gates, wards: wards}
    )
  end

  defp unsandboxed_cantrip(llm, opts \\ []) do
    gates = Keyword.get(opts, :gates, [:done, :echo])
    wards = [%{max_turns: 10}]

    Cantrip.new(
      llm: llm,
      circle: %{type: :code, gates: gates, wards: wards}
    )
  end

  # -- 1. Basic code works --

  describe "basic code execution" do
    test "map operations" do
      code = ~S"""
      m = %{a: 1, b: 2}
      m2 = Map.put(m, :c, 3)
      val = m2[:a] + m2[:b] + m2[:c]
      done.(val)
      """

      llm = {FakeLLM, FakeLLM.new([%{code: code}])}
      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, 6, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "map ops")
    end

    test "enum operations" do
      code = ~S"""
      mapped = Enum.map([1, 2, 3], fn x -> x * 2 end)
      filtered = Enum.filter(mapped, fn x -> x > 2 end)
      reduced = Enum.reduce(filtered, 0, fn x, acc -> x + acc end)
      done.(reduced)
      """

      llm = {FakeLLM, FakeLLM.new([%{code: code}])}
      {:ok, cantrip} = dune_cantrip(llm)

      # mapped = [2, 4, 6], filtered = [4, 6], reduced = 10
      assert {:ok, 10, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "enum ops")
    end

    test "pattern matching and case expressions" do
      code = ~S"""
      result = case {:ok, 42} do
        {:ok, n} when n > 0 -> n * 2
        {:error, _} -> -1
        _ -> 0
      end
      done.(result)
      """

      llm = {FakeLLM, FakeLLM.new([%{code: code}])}
      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, 84, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "case match")
    end

    test "comprehensions" do
      code = ~S"""
      squares = for n <- 1..5, do: n * n
      done.(Enum.sum(squares))
      """

      llm = {FakeLLM, FakeLLM.new([%{code: code}])}
      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, 55, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "comprehension")
    end

    test "string operations" do
      code = ~S"""
      s = "hello world"
      parts = String.split(s)
      result = Enum.map(parts, &String.upcase/1) |> Enum.join(" ")
      done.(result)
      """

      llm = {FakeLLM, FakeLLM.new([%{code: code}])}
      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, "HELLO WORLD", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "strings")
    end
  end

  # -- 2. Security: File.read is blocked --

  describe "File.read is blocked" do
    test "File.read returns sandbox restriction error" do
      code = ~S"""
      File.read("/etc/hosts")
      """

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: code},
           %{code: ~S[done.("recovered")]}
         ])}

      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, "recovered", _cantrip, loom, _meta} =
               Cantrip.cast(cantrip, "try file read")

      # First turn should have a sandbox restriction error
      first_turn = Enum.at(loom.turns, 0)
      error_obs = Enum.find(first_turn.observation, & &1.is_error)
      assert error_obs
      assert String.contains?(error_obs.result, "File.read")
      assert String.contains?(error_obs.result, "restricted")
    end
  end

  # -- 3. Security: System.cmd is blocked --

  describe "System.cmd is blocked" do
    test "System.cmd returns sandbox restriction error" do
      code = ~S"""
      System.cmd("echo", ["hello"])
      """

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: code},
           %{code: ~S[done.("recovered")]}
         ])}

      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, "recovered", _cantrip, loom, _meta} =
               Cantrip.cast(cantrip, "try system cmd")

      first_turn = Enum.at(loom.turns, 0)
      error_obs = Enum.find(first_turn.observation, & &1.is_error)
      assert error_obs
      assert String.contains?(error_obs.result, "System.cmd")
      assert String.contains?(error_obs.result, "restricted")
    end
  end

  # -- 4. Bindings persist across turns --

  describe "bindings persist across turns" do
    test "variable set in turn 1 is available in turn 2" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~S[x = 42]},
           %{code: ~S[done.(x + 8)]}
         ])}

      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, 50, _cantrip, _loom, _meta} =
               Cantrip.cast(cantrip, "persist bindings")
    end

    test "multiple variables persist and accumulate" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~S[x = 10]},
           %{code: ~S[y = x * 2]},
           %{code: ~S[done.(x + y)]}
         ])}

      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, 30, _cantrip, _loom, _meta} =
               Cantrip.cast(cantrip, "accumulate bindings")
    end

    test "bindings survive an error turn" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~S[x = 42]},
           %{code: ~S[File.read("/etc/hosts")]},
           %{code: ~S[done.(x)]}
         ])}

      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, 42, _cantrip, _loom, _meta} =
               Cantrip.cast(cantrip, "bindings survive error")
    end
  end

  # -- 5. Gate closures work --

  describe "gate closures" do
    test "done.() terminates and returns value" do
      code = ~S[done.("hello from dune")]

      llm = {FakeLLM, FakeLLM.new([%{code: code}])}
      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, "hello from dune", _cantrip, _loom, _meta} =
               Cantrip.cast(cantrip, "done gate")
    end

    test "echo.() gate is callable and returns result" do
      code = ~S"""
      result = echo.(%{text: "ping"})
      done.(result)
      """

      llm = {FakeLLM, FakeLLM.new([%{code: code}])}
      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, "ping", _cantrip, _loom, _meta} =
               Cantrip.cast(cantrip, "echo gate")
    end

    test "gate observations appear in loom" do
      code = ~S"""
      echo.(%{text: "observed"})
      done.("fin")
      """

      llm = {FakeLLM, FakeLLM.new([%{code: code}])}
      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, "fin", _cantrip, loom, _meta} =
               Cantrip.cast(cantrip, "observe gates")

      observations =
        loom.turns
        |> Enum.flat_map(&Map.get(&1, :observation, []))

      echo_obs = Enum.find(observations, &(&1.gate == "echo"))
      assert echo_obs
      assert echo_obs.result == "observed"
      refute echo_obs.is_error
    end
  end

  # -- 6. Opt-in behavior --

  describe "sandbox is opt-in" do
    test "without sandbox ward, File.read is NOT blocked (unrestricted path)" do
      code = ~S"""
      case File.read("/etc/hosts") do
        {:ok, content} -> done.("file_read_ok:" <> String.slice(content, 0, 10))
        {:error, reason} -> done.("file_read_error:" <> to_string(reason))
      end
      """

      llm = {FakeLLM, FakeLLM.new([%{code: code}])}
      {:ok, cantrip} = unsandboxed_cantrip(llm)

      assert {:ok, result, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "file read")

      # Without the sandbox ward, File.read succeeds (unrestricted)
      assert String.starts_with?(result, "file_read_ok:") or
               String.starts_with?(result, "file_read_error:")
    end

    test "with sandbox: :dune ward, File.read IS blocked" do
      code = ~S"""
      File.read("/etc/hosts")
      """

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: code},
           %{code: ~S[done.("recovered")]}
         ])}

      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, "recovered", _cantrip, loom, _meta} =
               Cantrip.cast(cantrip, "file read blocked")

      first_turn = Enum.at(loom.turns, 0)
      error_obs = Enum.find(first_turn.observation, & &1.is_error)
      assert error_obs
      assert String.contains?(error_obs.result, "restricted")
    end
  end

  # -- 7. Additional security --

  describe "additional security restrictions" do
    test "spawn is blocked" do
      code = ~S[spawn(fn -> :ok end)]

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: code},
           %{code: ~S[done.("recovered")]}
         ])}

      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, "recovered", _cantrip, loom, _meta} =
               Cantrip.cast(cantrip, "spawn blocked")

      first_turn = Enum.at(loom.turns, 0)
      error_obs = Enum.find(first_turn.observation, & &1.is_error)
      assert error_obs
      assert String.contains?(error_obs.result, "restricted")
    end

    test "Process module is blocked" do
      code = ~S[Process.get(:something)]

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: code},
           %{code: ~S[done.("recovered")]}
         ])}

      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, "recovered", _cantrip, loom, _meta} =
               Cantrip.cast(cantrip, "process blocked")

      first_turn = Enum.at(loom.turns, 0)
      error_obs = Enum.find(first_turn.observation, & &1.is_error)
      assert error_obs
      assert String.contains?(error_obs.result, "restricted")
    end

    test "Node operations are blocked" do
      code = ~S[Node.list()]

      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: code},
           %{code: ~S[done.("recovered")]}
         ])}

      {:ok, cantrip} = dune_cantrip(llm)

      assert {:ok, "recovered", _cantrip, loom, _meta} =
               Cantrip.cast(cantrip, "node blocked")

      first_turn = Enum.at(loom.turns, 0)
      error_obs = Enum.find(first_turn.observation, & &1.is_error)
      assert error_obs
      assert String.contains?(error_obs.result, "restricted")
    end
  end
end
