defmodule Cantrip.REPL do
  @moduledoc false

  @default_prompt "cantrip> "

  @spec default_cantrip_attrs() :: map()
  def default_cantrip_attrs do
    %{
      call: %{
        require_done_tool: true
      },
      circle: %{
        type: :code,
        gates: [:done, :echo, :call_agent, :call_agent_batch, :compile_and_load],
        wards: [%{max_turns: 24}, %{max_depth: 2}, %{max_concurrent_children: 4}]
      },
      retry: %{max_retries: 1, retryable_status_codes: [408, 429, 500, 502, 503, 504]}
    }
  end

  @spec new_cantrip() :: {:ok, Cantrip.t()} | {:error, term()}
  def new_cantrip do
    Cantrip.new_from_env(default_cantrip_attrs())
  end

  @spec run_once(String.t()) :: {:ok, term()} | {:error, term()}
  def run_once(intent) when is_binary(intent) do
    with {:ok, cantrip} <- new_cantrip(),
         {:ok, result, _next_cantrip, _loom, _meta} <- Cantrip.cast(cantrip, intent) do
      {:ok, result}
    else
      {:error, reason} -> {:error, reason}
      {:error, reason, _cantrip} -> {:error, reason}
    end
  end

  @spec run_stdio(keyword()) :: :ok
  def run_stdio(opts \\ []) do
    case new_cantrip() do
      {:ok, cantrip} ->
        if Keyword.get(opts, :no_input, false) do
          if Keyword.get(opts, :json, false) do
            IO.puts(~s({"ok":true}))
          else
            IO.puts("ok")
          end
        else
          IO.puts("Cantrip REPL started. Type `exit` or `quit` to stop.")
          loop(cantrip)
        end

      {:error, reason} ->
        IO.puts(:stderr, "failed to initialize cantrip: #{inspect(reason)}")
    end
  end

  defp loop(cantrip) do
    case IO.gets(@default_prompt) do
      nil ->
        :ok

      line ->
        case String.trim(line) do
          "" ->
            loop(cantrip)

          text when text in ["exit", "quit"] ->
            :ok

          text ->
            case Cantrip.cast(cantrip, text) do
              {:ok, result, next_cantrip, _loom, _meta} ->
                IO.puts("=> #{inspect(result)}")
                loop(next_cantrip)

              {:error, reason, next_cantrip} ->
                IO.puts(:stderr, "error: #{inspect(reason)}")
                loop(next_cantrip)
            end
        end
    end
  end
end
