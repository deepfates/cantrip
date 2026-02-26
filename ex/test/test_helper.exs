defmodule Cantrip.Test.RealCrystalEnv do
  @moduledoc false

  def enabled? do
    env_on?("RUN_REAL_CRYSTAL_TESTS") or autodetect_cantrip_env?()
  end

  def delegation_enabled? do
    enabled?() and env_on?("RUN_REAL_DELEGATION_EVAL")
  end

  defp autodetect_cantrip_env? do
    model_present?() and (api_key_present?() or non_openai_base_url?())
  end

  defp model_present?, do: present?(System.get_env("CANTRIP_MODEL"))
  defp api_key_present?, do: present?(System.get_env("CANTRIP_API_KEY"))

  defp non_openai_base_url? do
    base_url = System.get_env("CANTRIP_BASE_URL", "https://api.openai.com/v1")
    not String.contains?(String.downcase(base_url), "api.openai.com")
  end

  defp env_on?(name), do: System.get_env(name) == "1"
  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end

ExUnit.start()
