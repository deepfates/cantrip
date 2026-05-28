defmodule Cantrip.Familiar.Eval.CLI do
  @moduledoc """
  Argument parsing for `mix cantrip.eval`.
  """

  @switches [
    out: :string,
    seeds: :string,
    min_mean: :float,
    min_worst: :float,
    json: :boolean,
    help: :boolean
  ]

  @aliases [h: :help, o: :out]

  @type parse_result ::
          {:ok, Path.t(), keyword()}
          | {:help, keyword()}
          | {:error, String.t()}

  @spec parse_args([String.t()]) :: parse_result()
  def parse_args(args) do
    {opts, positional, invalid} =
      OptionParser.parse(args, strict: @switches, aliases: @aliases)

    cond do
      opts[:help] ->
        {:help, opts}

      invalid != [] ->
        {:error, "unknown option #{invalid |> hd() |> elem(0)}"}

      positional == [] ->
        {:error, "scenario path required"}

      length(positional) > 1 ->
        {:error, "expected one scenario path, got #{length(positional)}"}

      true ->
        with {:ok, seeds} <- parse_seeds(Keyword.get(opts, :seeds, "1")) do
          run_opts =
            []
            |> maybe_put(:out_dir, opts[:out])
            |> Keyword.put(:seeds, seeds)

          {:ok, hd(positional), Keyword.put(opts, :run_opts, run_opts)}
        end
    end
  end

  defp parse_seeds(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {:error, "seeds cannot be blank"}

      String.contains?(value, ",") ->
        value
        |> String.split(",", trim: true)
        |> Enum.map(&String.trim/1)
        |> parse_seed_list()

      true ->
        case Integer.parse(value) do
          {count, ""} when count > 0 -> {:ok, count}
          _ -> {:error, "seeds must be a positive integer or comma-separated integers"}
        end
    end
  end

  defp parse_seed_list(values) do
    Enum.reduce_while(values, {:ok, []}, fn value, {:ok, acc} ->
      case Integer.parse(value) do
        {seed, ""} -> {:cont, {:ok, [seed | acc]}}
        _ -> {:halt, {:error, "invalid seed #{inspect(value)}"}}
      end
    end)
    |> case do
      {:ok, seeds} -> {:ok, Enum.reverse(seeds)}
      error -> error
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)
end
