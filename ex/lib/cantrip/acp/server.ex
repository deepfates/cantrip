defmodule Cantrip.ACP.Server do
  @moduledoc """
  Stdio ACP JSON-RPC server.
  """

  alias Cantrip.ACP.Protocol

  def run(opts \\ []) do
    runtime = Keyword.get(opts, :runtime, Cantrip.ACP.Runtime.Cantrip)
    state = Protocol.new(runtime: runtime)
    loop(state, :stdio)
  end

  def handle_line(state, line) when is_binary(line) do
    case Jason.decode(String.trim(line)) do
      {:ok, request} ->
        Protocol.handle_request(state, request)

      {:error, _} ->
        {state,
         [
           %{
             "jsonrpc" => "2.0",
             "id" => nil,
             "error" => %{"code" => -32700, "message" => "parse error"}
           }
         ]}
    end
  end

  defp loop(state, io_device) do
    case IO.read(io_device, :line) do
      :eof ->
        :ok

      {:error, reason} ->
        IO.puts(:stderr, "acp server read error: #{inspect(reason)}")
        :ok

      line when is_binary(line) ->
        {next_state, responses} = handle_line(state, line)
        Enum.each(responses, &write_json/1)
        loop(next_state, io_device)
    end
  end

  defp write_json(map) do
    IO.write(Jason.encode!(map) <> "\n")
  end
end
