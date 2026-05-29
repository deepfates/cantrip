defmodule Cantrip.Familiar.Eval do
  @moduledoc """
  When you change a prompt or a circle and want evidence, you run an eval. This
  harness runs Familiar scenarios across seeds, scores each run against rubric
  criteria, persists transcripts, and writes a JSON report.

  Multi-scenario, multi-seed evaluation harness for `Cantrip.Familiar`.

  Scenarios are trusted Elixir data, usually loaded from an `.exs` file or a
  directory of `.exs` / `.json` files. Each scenario creates a temporary
  workspace, runs the Familiar against a prompt, persists that run's loom
  transcript, applies rubric criteria, and contributes to a summary report.

  Minimal scenario shape:

      [
        %{
          name: "read-note",
          prompt: "Read note.txt and return the first line.",
          fixtures: %{"note.txt" => "hello\\n"},
          llm: {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: ~S[
            {:ok, reader} = Cantrip.new(%{
              identity: %{system_prompt: "Read note.txt and return its contents."},
              circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 2}]}
            })
            {:ok, text, _reader, _loom, _meta} = Cantrip.cast(reader, "Read note.txt")
            done.(String.trim(text))
          ]}])},
          rubric: [
            %{name: "terminated", terminated: true},
            %{name: "answer", expected_result: "hello"}
          ]
        }
      ]

  Rubric criteria can be data-driven (`:expected_result`, `:contains`,
  `:terminated`, `:gate_used`, `:child_medium_used`, `:forbid_code_contains`),
  function-driven via `:score`, or judge-driven via `:judge`. Function criteria
  receive the run map and return a boolean or numeric score. Judge criteria use `:judge_llm`,
  `:judge_llm_factory`, or the runner's `:judge_llm` option and expect a JSON
  object like `%{"score" => 4, "reason" => "..."}` or a bare numeric response.
  """

  alias Cantrip.Familiar
  require Logger

  @scenario_keys ~w(name prompt fixtures rubric llm llm_factory familiar_opts seeds judge_llm judge_llm_factory)a
  @criterion_keys ~w(name max_score weight score expected_result contains terminated gate_used child_medium_used forbid_code_contains judge scope)a
  @criterion_scoring_keys ~w(score expected_result contains terminated gate_used child_medium_used forbid_code_contains judge)a

  @type scenario :: map()
  @type run_result :: map()
  @type report :: map()

  @doc """
  Loads scenarios from a trusted `.exs`/`.json` file or a directory.

  `.exs` files may return either a list of scenario maps or
  `%{scenarios: scenarios}`. JSON files support data-driven criteria only.
  Directories load `*.exs` and `*.json` entries in lexical order.
  """
  @spec load_path(Path.t()) :: {:ok, [scenario()]} | {:error, String.t()}
  def load_path(path) when is_binary(path) do
    cond do
      File.dir?(path) ->
        path
        |> Path.join("*")
        |> Path.wildcard()
        |> Enum.filter(&(Path.extname(&1) in [".exs", ".json"]))
        |> Enum.sort()
        |> Enum.reduce_while({:ok, []}, fn scenario_path, {:ok, acc} ->
          case load_file(scenario_path) do
            {:ok, scenarios} -> {:cont, {:ok, acc ++ scenarios}}
            {:error, reason} -> {:halt, {:error, "#{scenario_path}: #{reason}"}}
          end
        end)

      true ->
        load_file(path)
    end
  end

  @doc """
  Loads scenarios from a trusted `.exs` file or a JSON file.
  """
  @spec load_file(Path.t()) :: {:ok, [scenario()]} | {:error, String.t()}
  def load_file(path) when is_binary(path) do
    case Path.extname(path) do
      ".exs" ->
        Logger.warning(
          "loading trusted Elixir eval scenarios from #{path}; only run .exs scenarios you wrote or audited"
        )

        {value, _binding} = Code.eval_file(path)
        normalize_loaded_scenarios(value)

      ".json" ->
        with {:ok, body} <- File.read(path),
             {:ok, decoded} <- Jason.decode(body) do
          normalize_loaded_scenarios(decoded)
        else
          {:error, %Jason.DecodeError{} = e} -> {:error, Exception.message(e)}
          {:error, reason} -> {:error, Cantrip.SafeFormat.inspect(reason)}
        end

      other ->
        {:error, "unsupported scenario file extension #{inspect(other)}; expected .exs or .json"}
    end
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  @doc """
  Loads a scenario file or directory and runs it.
  """
  @spec run_path(Path.t(), keyword()) :: {:ok, report()} | {:error, String.t()}
  def run_path(path, opts \\ []) do
    with {:ok, scenarios} <- load_path(path) do
      run(scenarios, opts)
    end
  end

  @doc """
  Loads a scenario file and runs it.
  """
  @spec run_file(Path.t(), keyword()) :: {:ok, report()} | {:error, String.t()}
  def run_file(path, opts \\ []), do: run_path(path, opts)

  @doc """
  Runs scenarios and returns a report map.

  Options:

  - `:seeds` - integer count or explicit list of seeds. Default: `1`.
  - `:out_dir` - directory for report and transcripts. Default:
    `tmp/cantrip-evals/<timestamp>`.
  - `:llm_factory` - fallback function `(scenario, seed) -> llm`.
  - `:judge_llm` - fallback LLM used by judge-driven rubric criteria.
  - `:judge_llm_factory` - fallback function `(scenario, seed) -> judge_llm`.
  - `:familiar_opts` - base options merged into every Familiar.
  """
  @spec run([scenario()], keyword()) :: {:ok, report()} | {:error, String.t()}
  def run(scenarios, opts \\ []) when is_list(scenarios) and is_list(opts) do
    out_dir = Keyword.get_lazy(opts, :out_dir, &default_out_dir/0)
    File.mkdir_p!(out_dir)

    runs =
      scenarios
      |> Enum.flat_map(fn scenario ->
        seeds_for(scenario, opts)
        |> Enum.map(fn seed -> run_one(normalize_scenario(scenario), seed, out_dir, opts) end)
      end)

    report = build_report(runs, out_dir)
    write_report!(report)
    {:ok, report}
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  end

  @doc """
  Returns a JSON-safe projection of a report.
  """
  @spec jsonable_report(report()) :: map()
  def jsonable_report(report) when is_map(report), do: jsonable(report)

  defp normalize_loaded_scenarios(%{"scenarios" => scenarios}),
    do: normalize_loaded_scenarios(scenarios)

  defp normalize_loaded_scenarios(%{scenarios: scenarios}),
    do: normalize_loaded_scenarios(scenarios)

  defp normalize_loaded_scenarios(scenarios) when is_list(scenarios),
    do: {:ok, Enum.map(scenarios, &normalize_scenario/1)}

  defp normalize_loaded_scenarios(_other), do: {:error, "scenario file must return a list"}

  defp normalize_scenario(scenario) when is_map(scenario) do
    scenario
    |> atomize_known_keys()
    |> validate_keys!(@scenario_keys, "scenario")
    |> Map.update(:rubric, [], &normalize_rubric!/1)
    |> Map.update(:fixtures, %{}, &normalize_fixtures/1)
  end

  defp normalize_rubric!(criteria) when is_list(criteria) do
    Enum.map(criteria, fn criterion ->
      criterion
      |> atomize_known_keys()
      |> validate_keys!(@criterion_keys, "rubric criterion")
      |> normalize_scope!()
      |> validate_criterion!()
    end)
  end

  defp normalize_rubric!(other) do
    raise ArgumentError, "rubric must be a list, got #{Cantrip.SafeFormat.inspect(other)}"
  end

  defp atomize_known_keys(map) when is_map(map) do
    known = @scenario_keys ++ @criterion_keys

    Map.new(map, fn
      {key, value} when is_binary(key) ->
        atom_key =
          Enum.find(known, key, fn known_key -> Atom.to_string(known_key) == key end)

        {atom_key, value}

      pair ->
        pair
    end)
  end

  defp validate_keys!(map, allowed, label) do
    unknown =
      map
      |> Map.keys()
      |> Enum.reject(&(&1 in allowed))

    case unknown do
      [] ->
        map

      keys ->
        raise ArgumentError,
              "#{label} has unknown keys: #{Enum.map_join(keys, ", ", &Cantrip.SafeFormat.inspect/1)}"
    end
  end

  defp validate_criterion!(criterion) do
    present = Enum.filter(@criterion_scoring_keys, &Map.has_key?(criterion, &1))

    case present do
      [] ->
        raise ArgumentError,
              "rubric criterion #{criterion_name(criterion)} must include one scoring key"

      [_one] ->
        criterion

      keys ->
        raise ArgumentError,
              "rubric criterion #{criterion_name(criterion)} has multiple scoring keys: #{Enum.join(keys, ", ")}"
    end
  end

  defp normalize_scope!(%{scope: scope} = criterion) when scope in [:any, "any"],
    do: Map.put(criterion, :scope, :any)

  defp normalize_scope!(%{scope: scope} = criterion) when scope in [:parent, "parent"],
    do: Map.put(criterion, :scope, :parent)

  defp normalize_scope!(%{scope: scope}) do
    raise ArgumentError, "rubric criterion scope must be :any or :parent, got #{inspect(scope)}"
  end

  defp normalize_scope!(criterion), do: criterion

  defp criterion_name(criterion),
    do: Cantrip.SafeFormat.inspect(Map.get(criterion, :name, "criterion"))

  defp normalize_fixtures(fixtures) when is_map(fixtures), do: fixtures
  defp normalize_fixtures(nil), do: %{}

  defp normalize_fixtures(other) do
    raise ArgumentError, "fixtures must be a map, got #{Cantrip.SafeFormat.inspect(other)}"
  end

  defp seeds_for(%{seeds: seeds}, _opts) when is_list(seeds), do: seeds
  defp seeds_for(%{seeds: count}, _opts) when is_integer(count) and count > 0, do: 1..count

  defp seeds_for(_scenario, opts) do
    case Keyword.get(opts, :seeds, 1) do
      seeds when is_list(seeds) -> seeds
      count when is_integer(count) and count > 0 -> 1..count
    end
  end

  defp run_one(scenario, seed, out_dir, opts) do
    name = scenario_name(scenario)
    workspace = Path.join([out_dir, "workspaces", slug(name), to_string(seed)])
    transcript_path = Path.join([out_dir, "transcripts", "#{slug(name)}-#{seed}.jsonl"])

    File.rm_rf!(workspace)
    File.mkdir_p!(workspace)
    File.mkdir_p!(Path.dirname(transcript_path))
    write_fixtures!(workspace, Map.get(scenario, :fixtures, %{}))

    started_at = DateTime.utc_now()

    run =
      case build_familiar(scenario, seed, workspace, transcript_path, opts) do
        {:ok, cantrip} ->
          cast_familiar(cantrip, scenario, seed, workspace, transcript_path, started_at)

        {:error, reason} ->
          base_run(scenario, seed, workspace, transcript_path, started_at)
          |> Map.merge(%{status: :error, error: reason, result: nil, meta: %{terminated: false}})
      end

    scores = score_run(run, Map.get(scenario, :rubric, []), scenario, opts)
    Map.put(run, :score, scores)
  end

  defp build_familiar(scenario, seed, workspace, transcript_path, opts) do
    llm = scenario_llm(scenario, seed, opts)

    familiar_opts =
      opts
      |> Keyword.get(:familiar_opts, [])
      |> Keyword.merge(Map.get(scenario, :familiar_opts, []))
      |> Keyword.put(:llm, llm)
      |> Keyword.put(:root, workspace)
      |> Keyword.put(:loom_path, transcript_path)

    Familiar.new(familiar_opts)
  end

  defp scenario_llm(%{llm: llm}, _seed, _opts), do: llm

  defp scenario_llm(%{llm_factory: factory} = scenario, seed, _opts) when is_function(factory, 2),
    do: factory.(scenario, seed)

  defp scenario_llm(scenario, seed, opts) do
    case Keyword.get(opts, :llm_factory) do
      factory when is_function(factory, 2) ->
        factory.(scenario, seed)

      _ ->
        case Cantrip.LLM.from_env() do
          {:ok, llm} -> llm
          {:error, reason} -> raise "could not build LLM from environment: #{reason}"
        end
    end
  end

  defp cast_familiar(cantrip, scenario, seed, workspace, transcript_path, started_at) do
    run = base_run(scenario, seed, workspace, transcript_path, started_at)

    case Cantrip.cast(cantrip, Map.fetch!(scenario, :prompt)) do
      {:ok, result, _next, loom, meta} ->
        run
        |> Map.merge(%{
          status: :ok,
          result: result,
          loom: loom,
          meta: meta,
          finished_at: DateTime.utc_now()
        })

      {:error, reason, _cantrip} ->
        run
        |> Map.merge(%{
          status: :error,
          error: reason,
          result: nil,
          meta: %{terminated: false},
          finished_at: DateTime.utc_now()
        })
    end
  rescue
    e ->
      base_run(scenario, seed, workspace, transcript_path, started_at)
      |> Map.merge(%{
        status: :error,
        error: Cantrip.SafeFormat.exception(e),
        result: nil,
        meta: %{terminated: false},
        finished_at: DateTime.utc_now()
      })
  end

  defp base_run(scenario, seed, workspace, transcript_path, started_at) do
    %{
      scenario: scenario_name(scenario),
      prompt: Map.get(scenario, :prompt),
      seed: seed,
      workspace: workspace,
      transcript_path: transcript_path,
      started_at: started_at
    }
  end

  defp write_fixtures!(root, fixtures) do
    Enum.each(fixtures, fn {relative_path, content} ->
      path = Path.expand(to_string(relative_path), root)
      root = Path.expand(root)

      unless String.starts_with?(path, root <> "/") or path == root do
        raise ArgumentError, "fixture path escapes workspace: #{relative_path}"
      end

      File.mkdir_p!(Path.dirname(path))
      File.write!(path, to_string(content))
    end)
  end

  defp score_run(run, rubric, scenario, opts) do
    criteria = Enum.map(rubric, &score_criterion(run, &1, scenario, opts))
    total = Enum.sum(Enum.map(criteria, & &1.score))
    max_score = Enum.sum(Enum.map(criteria, & &1.max_score))
    percent = if max_score == 0, do: 1.0, else: total / max_score
    %{total: total, max_score: max_score, percent: percent, criteria: criteria}
  end

  defp score_criterion(run, criterion, scenario, opts) do
    max_score = numeric(Map.get(criterion, :max_score, Map.get(criterion, :weight, 1)))
    {raw, details} = criterion_score(run, criterion, scenario, opts)
    score = raw |> normalize_score(max_score) |> min(max_score) |> max(0.0)

    %{
      name: to_string(Map.get(criterion, :name, "criterion")),
      score: score,
      max_score: max_score,
      passed: score >= max_score,
      details: details
    }
  end

  defp criterion_score(run, %{score: fun}, _scenario, _opts) when is_function(fun, 1),
    do: {fun.(run), %{}}

  defp criterion_score(run, %{score: fun}, _scenario, _opts) when is_function(fun, 2),
    do: {fun.(run, Map.get(run, :seed)), %{}}

  defp criterion_score(run, %{judge: prompt} = criterion, scenario, opts) do
    judge_criterion(run, prompt, criterion, scenario, opts)
  end

  defp criterion_score(run, %{expected_result: expected}, _scenario, _opts),
    do: {Map.get(run, :result) == expected, %{}}

  defp criterion_score(run, %{contains: expected}, _scenario, _opts) do
    score =
      run
      |> Map.get(:result)
      |> stringify()
      |> String.contains?(to_string(expected))

    {score, %{}}
  end

  defp criterion_score(run, %{terminated: expected}, _scenario, _opts) do
    {get_in(run, [:meta, :terminated]) == expected, %{}}
  end

  defp criterion_score(run, %{gate_used: gate} = criterion, _scenario, _opts) do
    score =
      run
      |> observations(scope: Map.get(criterion, :scope, :any))
      |> Enum.any?(&(field(&1, :gate) == to_string(gate)))

    {score, %{}}
  end

  defp criterion_score(run, %{child_medium_used: medium}, _scenario, _opts) do
    parent_ids =
      run
      |> turns(scope: :parent)
      |> Enum.map(&field(&1, :id))
      |> MapSet.new()

    score =
      run
      |> turns(scope: :any)
      |> Enum.reject(&(field(&1, :id) in parent_ids))
      |> Enum.any?(fn turn ->
        turn
        |> field(:metadata, %{})
        |> field(:medium_type)
        |> normalize_medium() == normalize_medium(medium)
      end)

    {score, %{}}
  end

  defp criterion_score(run, %{forbid_code_contains: text} = criterion, _scenario, _opts) do
    score =
      not Enum.any?(turns(run, scope: Map.get(criterion, :scope, :any)), fn turn ->
        turn
        |> field(:utterance, %{})
        |> field(:code, "")
        |> to_string()
        |> String.contains?(to_string(text))
      end)

    {score, %{}}
  end

  defp criterion_score(_run, criterion, _scenario, _opts) do
    Logger.warning(
      "Cantrip.Familiar.Eval: unknown rubric criterion #{inspect(criterion)} — scoring 0"
    )

    {0, %{error: "unknown criterion"}}
  end

  defp judge_criterion(run, prompt, criterion, scenario, opts) do
    with {:ok, {module, state}} <- judge_llm(scenario, run.seed, opts),
         request <- judge_request(run, prompt, criterion),
         {:ok, response, _next_state} <- Cantrip.LLM.request(module, state, request),
         raw_response = response.content || "",
         {:ok, score, reason} <- parse_judge_response(raw_response) do
      {score, %{judge_reason: reason, judge_raw_response: raw_response}}
    else
      {:error, reason} ->
        {0, %{judge_error: Cantrip.SafeFormat.inspect(reason)}}
    end
  end

  defp judge_llm(%{judge_llm: llm}, _seed, _opts), do: {:ok, llm}

  defp judge_llm(%{judge_llm_factory: factory} = scenario, seed, _opts)
       when is_function(factory, 2),
       do: {:ok, factory.(scenario, seed)}

  defp judge_llm(scenario, seed, opts) do
    cond do
      llm = Keyword.get(opts, :judge_llm) ->
        {:ok, llm}

      factory = Keyword.get(opts, :judge_llm_factory) ->
        {:ok, factory.(scenario, seed)}

      true ->
        Cantrip.LLM.from_env()
    end
  end

  defp judge_request(run, prompt, criterion) do
    transcript =
      run
      |> judge_payload()
      |> jsonable()
      |> Jason.encode!(pretty: true)

    %{
      messages: [
        %{
          role: :system,
          content:
            "You are scoring a Cantrip Familiar eval run. Return only JSON with keys score and reason."
        },
        %{
          role: :user,
          content: """
          Rubric criterion:
          #{prompt}

          Maximum score: #{Map.get(criterion, :max_score, Map.get(criterion, :weight, 1))}

          Run transcript:
          #{transcript}
          """
        }
      ]
    }
  end

  defp judge_payload(run) do
    %{
      scenario: run.scenario,
      prompt: run.prompt,
      seed: run.seed,
      status: run.status,
      result: Map.get(run, :result),
      meta: Map.get(run, :meta, %{}),
      turns:
        Enum.map(turns(run), fn turn ->
          %{
            sequence: field(turn, :sequence),
            terminated: field(turn, :terminated),
            utterance: field(turn, :utterance, %{}),
            observation: field(turn, :observation, [])
          }
        end)
    }
  end

  defp parse_judge_response(content) when is_binary(content) do
    trimmed = String.trim(content)

    cond do
      match?({number, ""} when is_number(number), Float.parse(trimmed)) ->
        {score, _} = Float.parse(trimmed)
        {:ok, score, ""}

      true ->
        with {:ok, decoded} <- Jason.decode(trimmed),
             {:ok, score} <- fetch_numeric(decoded, "score") do
          {:ok, score, to_string(Map.get(decoded, "reason", ""))}
        else
          {:error, reason} -> {:error, reason}
        end
    end
  end

  defp fetch_numeric(map, key) when is_map(map) do
    case Map.fetch(map, key) do
      {:ok, value} when is_integer(value) -> {:ok, value / 1}
      {:ok, value} when is_float(value) -> {:ok, value}
      {:ok, value} when is_binary(value) -> parse_numeric(value)
      _ -> {:error, "judge response must include numeric #{key}"}
    end
  end

  defp parse_numeric(value) do
    case Float.parse(String.trim(value)) do
      {number, ""} -> {:ok, number}
      _ -> {:error, "judge score is not numeric"}
    end
  end

  defp observations(run, opts) do
    run
    |> turns(opts)
    |> Enum.flat_map(&field(&1, :observation, []))
  end

  defp turns(run, opts \\ [])

  defp turns(%{loom: %{turns: turns}}, scope: :parent) do
    parent_cantrip_ids =
      turns
      |> Enum.filter(&(is_nil(field(&1, :parent_id)) and not is_nil(field(&1, :cantrip_id))))
      |> Enum.map(&field(&1, :cantrip_id))
      |> MapSet.new()

    child_ids =
      turns
      |> Enum.flat_map(&child_turns/1)
      |> Enum.map(&field(&1, :id))
      |> MapSet.new()

    Enum.filter(turns, fn turn ->
      field(turn, :cantrip_id) in parent_cantrip_ids and field(turn, :id) not in child_ids
    end)
  end

  defp turns(%{loom: %{turns: turns}}, _opts), do: Enum.flat_map(turns, &turn_with_children/1)
  defp turns(_run, _opts), do: []

  defp turn_with_children(turn) do
    # Cantrip.Loom.append_executed_turn/4 grafts child turns flat into
    # `loom.turns`; this traversal is retained for rehydrated observations
    # that still carry nested `:child_turns`.
    [turn | Enum.flat_map(child_turns(turn), &turn_with_children/1)]
  end

  defp child_turns(turn) do
    turn
    |> field(:observation, [])
    |> Enum.flat_map(fn observation -> field(observation, :child_turns, []) end)
  end

  defp normalize_score(true, max_score), do: max_score
  defp normalize_score(false, _max_score), do: 0.0
  defp normalize_score(score, _max_score) when is_number(score), do: score / 1

  defp normalize_score(other, _max_score) do
    raise ArgumentError, "criterion returned invalid score: #{Cantrip.SafeFormat.inspect(other)}"
  end

  defp numeric(value) when is_integer(value), do: value / 1
  defp numeric(value) when is_float(value), do: value

  defp field(map, key, default \\ nil)

  defp field(map, key, default) when is_map(map),
    do: Map.get(map, key, Map.get(map, to_string(key), default))

  defp field(_value, _key, default), do: default

  defp normalize_medium(value) when is_atom(value), do: Atom.to_string(value)
  defp normalize_medium(value) when is_binary(value), do: value
  defp normalize_medium(value), do: to_string(value)

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: Cantrip.SafeFormat.inspect(value)

  defp build_report(runs, out_dir) do
    %{
      schema_version: 1,
      generated_at: DateTime.utc_now(),
      out_dir: out_dir,
      summary: summarize(runs),
      scenarios: summarize_scenarios(runs),
      runs: runs
    }
  end

  defp summarize(runs) do
    percents = Enum.map(runs, &get_in(&1, [:score, :percent]))

    %{
      run_count: length(runs),
      mean_score: mean(percents),
      stddev_score: stddev(percents),
      worst_score: Enum.min(percents, fn -> 0.0 end),
      failed_runs: Enum.count(runs, &(&1.status != :ok))
    }
  end

  defp summarize_scenarios(runs) do
    runs
    |> Enum.group_by(& &1.scenario)
    |> Map.new(fn {scenario, scenario_runs} ->
      percents = Enum.map(scenario_runs, &get_in(&1, [:score, :percent]))

      {scenario,
       %{
         run_count: length(scenario_runs),
         mean_score: mean(percents),
         stddev_score: stddev(percents),
         worst_score: Enum.min(percents, fn -> 0.0 end)
       }}
    end)
  end

  defp write_report!(%{out_dir: out_dir} = report) do
    File.mkdir_p!(out_dir)

    File.write!(
      Path.join(out_dir, "report.json"),
      Jason.encode!(jsonable_report(report), pretty: true)
    )
  end

  defp mean([]), do: 0.0
  defp mean(values), do: Enum.sum(values) / length(values)

  defp stddev([]), do: 0.0
  defp stddev([_]), do: 0.0

  defp stddev(values) do
    avg = mean(values)

    variance =
      values |> Enum.map(&:math.pow(&1 - avg, 2)) |> Enum.sum() |> Kernel./(length(values))

    :math.sqrt(variance)
  end

  defp jsonable(%DateTime{} = value), do: DateTime.to_iso8601(value)

  defp jsonable(%Cantrip.Loom{} = loom) do
    %{
      turn_count: length(loom.turns),
      event_count: length(loom.events)
    }
  end

  defp jsonable(%_struct{} = struct), do: struct |> Map.from_struct() |> jsonable()

  defp jsonable(value) when is_map(value),
    do: Map.new(value, fn {k, v} -> {to_string(k), jsonable(v)} end)

  defp jsonable(value) when is_list(value), do: Enum.map(value, &jsonable/1)
  defp jsonable(value) when is_function(value), do: "#Function<>"
  defp jsonable(value) when is_atom(value), do: Atom.to_string(value)

  defp jsonable(value) when is_pid(value) or is_reference(value) or is_port(value),
    do: %{"__inspect__" => inspect(value)}

  defp jsonable(value), do: value

  defp scenario_name(%{name: name}) when is_binary(name), do: name
  defp scenario_name(%{name: name}), do: to_string(name)
  defp scenario_name(_), do: "unnamed"

  defp slug(value) do
    value
    |> to_string()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9_-]+/, "-")
    |> String.trim("-")
    |> case do
      "" -> "scenario"
      slug -> slug
    end
  end

  defp default_out_dir do
    timestamp =
      DateTime.utc_now()
      |> Calendar.strftime("%Y%m%dT%H%M%SZ")

    Path.join(["tmp", "cantrip-evals", timestamp])
  end
end
