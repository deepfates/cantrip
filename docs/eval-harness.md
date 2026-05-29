# Familiar Eval Harness

The Familiar eval harness turns prompt changes into measured behavior. It runs
one or more scenarios, repeats them across seeds, stores each run's loom
transcript, scores the result against a rubric, and writes a JSON report that
can be inspected by humans or used as a CI gate.

Run a scenario file or directory:

```sh
mix cantrip.eval evals/familiar --out tmp/evals/current --seeds 5
```

`SCENARIO_PATH` may be:

- a trusted `.exs` file returning a list of scenario maps or `%{scenarios: list}`
- a `.json` file for data-only scenarios
- a directory containing `.exs` and `.json` scenario files

`.exs` scenarios are code, not data. The loader evaluates them with
`Code.eval_file/1`, which is useful for deterministic LLM factories and custom
rubric functions, but it has the same trust posture as running any other
Elixir script. Only run `.exs` scenarios you wrote or audited. Use `.json`
when you need a data-only format.

The output directory contains:

- `report.json` - aggregate and per-run scores
- `transcripts/*.jsonl` - loom-style transcripts for each run
- `workspaces/<scenario>/<seed>/` - the fixture workspace used by that run

## Scenario Shape

An Elixir scenario file is the most expressive format because it can provide
deterministic test LLMs, seed-aware factories, and custom rubric functions.

```elixir
[
  %{
    name: "read-note",
    prompt: "Read note.txt and answer with its first line.",
    fixtures: %{"note.txt" => "alpha\nbeta\n"},
    llm_factory: fn _scenario, seed ->
      child_code = ~S[
        text = read_file.(%{path: "note.txt"})
        done.(text |> String.split("\n") |> hd())
      ]

      {Cantrip.FakeLLM,
       Cantrip.FakeLLM.new([
         %{code: ~s[
           child_llm = {Cantrip.FakeLLM, Cantrip.FakeLLM.new([%{code: #{inspect(child_code)}}])}
           {:ok, reader} = Cantrip.new(%{
             llm: child_llm,
             identity: %{system_prompt: "Read note.txt and return the first line."},
             circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 2}]}
           })
           {:ok, first, _reader, _loom, _meta} = Cantrip.cast(reader, "Read note.txt")
           done.("seed " <> Integer.to_string(#{seed}) <> ": " <> first)
         ]}
       ])}
    end,
    rubric: [
      %{name: "terminated", terminated: true},
      %{name: "used read_file", gate_used: "read_file"},
      %{name: "answered from fixture", contains: "alpha", max_score: 2}
    ]
  }
]
```

The runner creates a fresh workspace per scenario/seed and passes it as the
Familiar root. Fixture paths are confined to that workspace.

## Rubric Criteria

Data-driven criteria are useful for deterministic behavior tests:

- `terminated: true` - the run ended through the expected termination path
- `expected_result: value` - the final result equals `value`
- `contains: text` - the final result contains `text`
- `gate_used: name` - any recorded observation used `name`
- `child_medium_used: medium` - a child turn used the expected medium, such as
  `:conversation`, `:code`, or `:bash`
- `forbid_code_contains: text` - no recorded code turn contains `text`
- `max_score: n` or `weight: n` - score weight for the criterion

Criteria that inspect turns default to `scope: :any`, which includes child
turns grafted into the parent loom. Use `scope: :parent` when the criterion
must apply only to the parent Familiar's own turns.

Function criteria let scenario authors encode local checks without changing the
harness:

```elixir
%{
  name: "looked at the loom",
  max_score: 5,
  score: fn run ->
    Enum.any?(run.loom.turns, fn turn ->
      get_in(turn, [:utterance, :code]) =~ "loom.turns"
    end)
  end
}
```

Judge criteria use an LLM to score qualitative behavior. Provide `:judge` on
the criterion and either `:judge_llm`, `:judge_llm_factory`, or runner-level
judge options. The judge should return JSON with `score` and `reason`, or a
bare numeric score. The raw judge response is stored in the criterion details
inside `report.json` so scoring can be audited later.

```elixir
%{
  name: "prose-not-dump",
  max_score: 5,
  judge: "Score whether the final answer is concise prose rather than a raw data dump."
}
```

## CI Gates

The Mix task can fail when aggregate scores fall below a floor:

```sh
mix cantrip.eval evals/familiar --seeds 5 --min-mean 0.85 --min-worst 0.60
```

This is intentionally threshold-based for the first version. It gives prompt
work a quantitative signal without pretending to solve baseline management,
inter-evaluator agreement, or cost optimization.
