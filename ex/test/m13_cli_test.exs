defmodule CantripM13CliTest do
  use ExUnit.Case, async: false

  alias Cantrip.CLI

  test "help command prints usage and exits zero" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert CLI.run(["help"]) == 0
      end)

    assert output =~ "usage: cantrip <command> [args]"
  end

  test "invalid command prints usage and exits non-zero" do
    output =
      ExUnit.CaptureIO.capture_io(:stderr, fn ->
        assert CLI.run(["unknown"]) == 1
      end)

    assert output =~ "usage: cantrip <command> [args]"
  end

  test "example list prints catalog and exits zero" do
    output =
      ExUnit.CaptureIO.capture_io(fn ->
        assert CLI.run(["example", "list"]) == 0
      end)

    assert output =~ "01  Minimal Crystal + done"
    assert output =~ "16  Familiar-style persistent loom"
  end
end
