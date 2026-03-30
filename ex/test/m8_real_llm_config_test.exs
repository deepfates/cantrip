defmodule CantripM8RealLlmConfigTest do
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
      timeout_ms: System.get_env("CANTRIP_TIMEOUT_MS")
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
    end)
  end

  test "llm_from_env returns openai-compatible llm tuple" do
    System.put_env("CANTRIP_LLM_PROVIDER", "openai_compatible")
    System.put_env("OPENAI_MODEL", "gpt-5-mini")
    System.put_env("CANTRIP_MODEL", "ignored-by-openai-model")
    System.put_env("OPENAI_API_KEY", "sk-test")
    System.put_env("OPENAI_BASE_URL", "http://localhost:11434/v1")
    System.put_env("CANTRIP_TIMEOUT_MS", "12345")

    assert {:ok, {module, state}} = Cantrip.llm_from_env()

    if Code.ensure_loaded?(Cantrip.LLMs.ReqLLM) do
      assert module == Cantrip.LLMs.ReqLLM
      assert state.model == "openai:gpt-5-mini"
    else
      assert module == Cantrip.LLMs.OpenAICompatible
      assert state.model == "gpt-5-mini"
      assert state.base_url == "http://localhost:11434/v1"
    end

    assert state.timeout_ms == 12_345
  end

  test "llm_from_env requires CANTRIP_MODEL" do
    System.put_env("CANTRIP_LLM_PROVIDER", "openai_compatible")
    System.delete_env("CANTRIP_MODEL")
    System.delete_env("OPENAI_MODEL")
    assert {:error, "missing CANTRIP_MODEL or OPENAI_MODEL"} = Cantrip.llm_from_env()
  end

  defp restore_env(key, nil), do: System.delete_env(key)

  defp restore_env(key, value) do
    System.put_env(key, value)
  end
end
