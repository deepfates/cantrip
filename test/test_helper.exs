defmodule Cantrip.Test.RealLLMEnv do
  @moduledoc false

  def enabled? do
    load_dotenv()
    env_on?("RUN_REAL_LLM_TESTS")
  end

  def delegation_enabled? do
    enabled?() and env_on?("RUN_REAL_DELEGATION_EVAL")
  end

  defp env_on?(name), do: System.get_env(name) == "1"

  defp load_dotenv do
    Dotenvy.source(".env",
      side_effect: fn vars ->
        for {key, value} <- vars, System.get_env(key) in [nil, ""] do
          System.put_env(key, value)
        end
      end
    )
  end
end

ExUnit.start()
