defmodule CantripM8RealCrystalConfigTest do
  use ExUnit.Case, async: false

  setup do
    previous = %{
      provider: System.get_env("CANTRIP_CRYSTAL_PROVIDER"),
      model: System.get_env("CANTRIP_MODEL"),
      api_key: System.get_env("CANTRIP_API_KEY"),
      base_url: System.get_env("CANTRIP_BASE_URL"),
      timeout_ms: System.get_env("CANTRIP_TIMEOUT_MS")
    }

    on_exit(fn ->
      restore_env("CANTRIP_CRYSTAL_PROVIDER", previous.provider)
      restore_env("CANTRIP_MODEL", previous.model)
      restore_env("CANTRIP_API_KEY", previous.api_key)
      restore_env("CANTRIP_BASE_URL", previous.base_url)
      restore_env("CANTRIP_TIMEOUT_MS", previous.timeout_ms)
    end)
  end

  test "crystal_from_env returns openai-compatible crystal tuple" do
    System.put_env("CANTRIP_CRYSTAL_PROVIDER", "openai_compatible")
    System.put_env("CANTRIP_MODEL", "gpt-4.1-mini")
    System.put_env("CANTRIP_API_KEY", "sk-test")
    System.put_env("CANTRIP_BASE_URL", "http://localhost:11434/v1")
    System.put_env("CANTRIP_TIMEOUT_MS", "12345")

    assert {:ok, {Cantrip.Crystals.OpenAICompatible, state}} = Cantrip.crystal_from_env()
    assert state.model == "gpt-4.1-mini"
    assert state.base_url == "http://localhost:11434/v1"
    assert state.timeout_ms == 12_345
  end

  test "crystal_from_env requires CANTRIP_MODEL" do
    System.delete_env("CANTRIP_MODEL")
    assert {:error, "missing CANTRIP_MODEL"} = Cantrip.crystal_from_env()
  end

  defp restore_env(key, nil), do: System.delete_env(key)

  defp restore_env(key, value) do
    System.put_env(key, value)
  end
end
