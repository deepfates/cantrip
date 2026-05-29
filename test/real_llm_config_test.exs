defmodule Cantrip.RealLLMConfigTest do
  use ExUnit.Case, async: false

  setup do
    previous = %{
      provider: System.get_env("CANTRIP_LLM_PROVIDER"),
      model: System.get_env("CANTRIP_MODEL"),
      openai_model: System.get_env("OPENAI_MODEL"),
      api_key: System.get_env("CANTRIP_API_KEY"),
      openai_api_key: System.get_env("OPENAI_API_KEY"),
      base_url: System.get_env("CANTRIP_BASE_URL"),
      openai_base_url: System.get_env("OPENAI_BASE_URL"),
      timeout_ms: System.get_env("CANTRIP_TIMEOUT_MS"),
      stream: System.get_env("CANTRIP_STREAM")
    }

    on_exit(fn ->
      restore_env("CANTRIP_LLM_PROVIDER", previous.provider)
      restore_env("CANTRIP_MODEL", previous.model)
      restore_env("OPENAI_MODEL", previous.openai_model)
      restore_env("CANTRIP_API_KEY", previous.api_key)
      restore_env("OPENAI_API_KEY", previous.openai_api_key)
      restore_env("CANTRIP_BASE_URL", previous.base_url)
      restore_env("OPENAI_BASE_URL", previous.openai_base_url)
      restore_env("CANTRIP_TIMEOUT_MS", previous.timeout_ms)
      restore_env("CANTRIP_STREAM", previous.stream)
    end)
  end

  test "LLM.from_env returns ReqLLM openai-compatible llm tuple" do
    System.put_env("CANTRIP_LLM_PROVIDER", "openai_compatible")
    System.put_env("OPENAI_MODEL", "gpt-5-mini")
    System.put_env("CANTRIP_MODEL", "ignored-by-openai-model")
    System.put_env("OPENAI_API_KEY", "sk-test")
    System.put_env("OPENAI_BASE_URL", "http://localhost:11434/v1")
    System.put_env("CANTRIP_TIMEOUT_MS", "12345")

    assert {:ok, {module, state}} = Cantrip.LLM.from_env()
    assert module == Cantrip.LLMs.ReqLLM
    assert state.model == "openai:gpt-5-mini"
    assert state.base_url == "http://localhost:11434/v1"

    assert state.timeout_ms == 12_345
  end

  test "LLM.from_env requires CANTRIP_MODEL" do
    System.put_env("CANTRIP_LLM_PROVIDER", "openai_compatible")
    System.delete_env("CANTRIP_MODEL")
    System.delete_env("OPENAI_MODEL")
    assert {:error, "missing CANTRIP_MODEL or OPENAI_MODEL"} = Cantrip.LLM.from_env()
  end

  test "LLM.from_env accepts boolean stream option and option overrides env" do
    System.put_env("CANTRIP_STREAM", "true")

    assert {:ok, {_module, state}} =
             Cantrip.LLM.from_env(
               provider: "openai_compatible",
               model: "gpt-5-mini",
               stream: false
             )

    assert state.stream == false

    assert {:ok, {_module, state}} =
             Cantrip.LLM.from_env(
               provider: "openai_compatible",
               model: "gpt-5-mini",
               stream: true
             )

    assert state.stream == true
  end

  test "LLM.from_env does not use model as base_url or api_key fallback" do
    System.delete_env("OPENAI_BASE_URL")
    System.delete_env("CANTRIP_BASE_URL")
    System.delete_env("OPENAI_API_KEY")
    System.delete_env("CANTRIP_API_KEY")

    assert {:ok, {_module, state}} =
             Cantrip.LLM.from_env(provider: "openai_compatible", model: "gpt-5-mini")

    refute Map.has_key?(state, :base_url)
    refute Map.has_key?(state, :api_key)
  end

  test "LLM.from_env accepts explicit base_url and api_key options" do
    assert {:ok, {_module, state}} =
             Cantrip.LLM.from_env(
               provider: "openai_compatible",
               model: "gpt-5-mini",
               base_url: "http://localhost:11434/v1",
               api_key: "sk-test"
             )

    assert state.base_url == "http://localhost:11434/v1"
    assert state.api_key == "sk-test"
  end

  defp restore_env(key, nil), do: System.delete_env(key)

  defp restore_env(key, value) do
    System.put_env(key, value)
  end
end
