# Observability

Cantrip emits structured `:telemetry` events at process, gate, and medium
boundaries. This doc is the canonical reference for what gets emitted, how to
subscribe, and what to alert on.

**Audience:** operators deploying Cantrip, instrumentation engineers,
production support.

**Standard:** every documented event is asserted by a regression test. Events
not on this list are not load-bearing.

---

## Event registry

All events are emitted under the `[:cantrip, ...]` prefix.

| Event | Measurements | Metadata | Emitted from |
|---|---|---|---|
| `[:cantrip, :entity, :start]` | — | `entity_id, intent, trace_id` | `EntityServer.handle_call(:run, ...)` when an episode begins |
| `[:cantrip, :entity, :stop]` | `duration` | `entity_id, reason, trace_id` | `EntityServer.emit_entity_stop/2` when an episode terminates or is truncated |
| `[:cantrip, :turn, :start]` | — | `entity_id, turn_number, trace_id` | `EntityServer.run_loop/1` per turn |
| `[:cantrip, :turn, :stop]` | `duration` | `entity_id, turn_number, trace_id` | `EntityServer.emit_turn_stop/3` per turn |
| `[:cantrip, :gate, :start]` | — | `entity_id, gate_name, trace_id` | `Gate.Executor.emit_gate_start/2` per gate invocation |
| `[:cantrip, :gate, :stop]` | `duration` | `entity_id, gate_name, is_error, trace_id` | `Gate.Executor.emit_gate_stop/4` per gate invocation |
| `[:cantrip, :code, :eval]` | `duration` | `entity_id, trace_id` | `Medium.Code` per LLM-emitted Elixir evaluation |
| `[:cantrip, :bash, :eval]` | `duration` | `entity_id, trace_id` | `Medium.Bash` per shell command |
| `[:cantrip, :usage]` | `prompt_tokens, completion_tokens, total_tokens` | `entity_id, turn_number, trace_id` | `EntityServer.run_loop/1` after provider response |
| `[:cantrip, :redact, :hit]` | `count` | `entity_id, trace_id` | `Redact.scan/1` when boundary redaction removes a credential |
| `[:cantrip, :fold, :trigger]` | — | `entity_id, turn_number, trace_id` | `EntityServer.run_loop/1` when folding fires |
| `[:cantrip, :ward, :truncate]` | — | `entity_id, ward, trace_id` | `EntityServer.run_loop/1` when a ward stops execution |
| `[:cantrip, :ward, :child_rejected]` | `count` | `entity_id, child_id, child_medium, reason, trace_id` | child-cast coordinator when declaration-time child wards reject a spawn |
| `[:cantrip, :child, :start]` | — | `entity_id, child_depth, trace_id` | child-cast coordinator before child cast |
| `[:cantrip, :child, :stop]` | — | `entity_id, child_depth, outcome, trace_id` | child-cast coordinator after child cast |
| `[:cantrip, :loom, :persist_error]` | `count` | `storage_module, event_type, reason, trace_id` | `Loom.append_event/2` when the storage backend rejects a write |
| `[:cantrip, :compile_and_load]` | `duration` | `entity_id, module, outcome, trace_id` | `EntityServer.execute_compile_and_load/2` per hot-load attempt |

`duration` measurements are `System.monotonic_time/0` deltas (native units —
convert with `System.convert_time_unit/3` at the subscriber).

### Metadata invariants

- **`entity_id`** is always a binary, present on every event.
- **`trace_id`** is always a binary, present on every event. Propagates from
  parent cantrip context through child cantrips so a full trace forms a tree
  rooted at the originating episode.
- User-supplied strings that are intentionally useful for operations, such as
  root intents, are passed through `Cantrip.Redact` before emission so
  credential-shaped substrings are scrubbed. LLM responses, provider response
  bodies, bearer tokens, and raw credentials must not appear in event metadata.

---

## Subscribing

### Quick local logging

```elixir
:telemetry.attach_many(
  "cantrip-logger",
  [
    [:cantrip, :entity, :start],
    [:cantrip, :entity, :stop],
    [:cantrip, :turn, :stop],
    [:cantrip, :gate, :stop]
  ],
  fn event, measurements, metadata, _config ->
    Logger.info(
      "#{Enum.join(event, ".")} | #{inspect(measurements)} | #{inspect(metadata)}"
    )
  end,
  nil
)
```

### Production observability stack

The event prefix `[:cantrip, ...]` maps cleanly to most metric backends.
Recommended subscriptions for production deployments:

- **`[:cantrip, :turn, :stop]`** → histogram of `duration` per
  `entity_id` for turn-latency tracking.
- **`[:cantrip, :gate, :stop]`** → histogram of `duration` per `gate_name`;
  counter of `is_error: true` per `gate_name` for gate-error rates.
- **`[:cantrip, :entity, :stop]`** → counter per `reason` to track terminated
  vs truncated vs error termination.
- **`[:cantrip, :usage]`** → counters for prompt/completion/total token
  volume per `entity_id`.
- **`[:cantrip, :ward, :truncate]`** → counter per `ward` to see which guard
  is stopping work.
- **`[:cantrip, :ward, :child_rejected]`** → counter per `reason` to catch
  child-spawn policy pressure or prompt drift.
- **`[:cantrip, :redact, :hit]`** → counter of credential-shaped content
  removed from entity/model-visible boundaries.
- **`[:cantrip, :child, :start]` / `[:cantrip, :child, :stop]`** → counters
  and outcome tags for delegation fanout.
- **`[:cantrip, :code, :eval]`** and **`[:cantrip, :bash, :eval]`** →
  histogram of `duration` for medium-evaluation latency.

Example StatsD attachment (using `telemetry_metrics_statsd`):

```elixir
metrics = [
  Telemetry.Metrics.distribution("cantrip.turn.stop.duration",
    event_name: [:cantrip, :turn, :stop],
    measurement: :duration,
    unit: {:native, :millisecond}
  ),
  Telemetry.Metrics.distribution("cantrip.gate.stop.duration",
    event_name: [:cantrip, :gate, :stop],
    measurement: :duration,
    unit: {:native, :millisecond},
    tags: [:gate_name]
  ),
  Telemetry.Metrics.counter("cantrip.gate.error.count",
    event_name: [:cantrip, :gate, :stop],
    keep: &(&1.is_error)
  )
]

TelemetryMetricsStatsd.start_link(metrics: metrics)
```

Prometheus, Datadog, and other backends have equivalent
`Telemetry.Metrics`-based adapters.

---

## Recommended alerts

| Signal | Threshold | Why |
|---|---|---|
| `cantrip.gate.error.rate` | > 5% over 5 min, per `gate_name` | High gate error rate = LLM misuse or provider drift |
| `cantrip.turn.stop.duration` p95 | > 60s | Long turns suggest provider slowness, runaway code-medium evaluation, or hung gate |
| `cantrip.entity.stop.reason` = `:truncated` | > 10% over 1 hour | High truncation rate = `max_turns` ward set too low for the workload |
| `cantrip.ward.truncate.count` | sudden increase by `ward` | A runtime guard is stopping work more often than expected |
| `cantrip.redact.hit.count` | any unexpected sustained rate | User data or files contain credential-shaped content reaching observation boundaries |
| `cantrip.code.eval.duration` p95 | > 30s | Long code-medium evaluations suggest sandbox starvation or hung port |

---

## Trace correlation

`trace_id` propagates through child cantrips via the parent context. A full
trace for a parent episode that spawns N child cantrips is:

```
trace_id = "<root-uuid>"
  ├─ [:cantrip, :entity, :start] entity_id=parent_id
  │  ├─ [:cantrip, :turn, :start] turn_number=1
  │  ├─ [:cantrip, :gate, :start] gate_name=call_entity → spawns child
  │  │  ├─ [:cantrip, :entity, :start] entity_id=child_id  (same trace_id)
  │  │  ├─ [:cantrip, :turn, :start] turn_number=1
  │  │  └─ [:cantrip, :entity, :stop] entity_id=child_id
  │  ├─ [:cantrip, :gate, :stop] gate_name=call_entity
  │  └─ [:cantrip, :turn, :stop] turn_number=1
  └─ [:cantrip, :entity, :stop] entity_id=parent_id
```

All events in this tree carry the same `trace_id`. To correlate to external
systems (HTTP request IDs, job queue IDs, etc.), pass the external ID as
`trace_id` when running the top-level cantrip:

```elixir
Cantrip.cast(cantrip, intent, trace_id: external_request_id)
```

ACP requests can use the protocol metadata channel. Put a non-empty string in
`_meta.trace_id` (or `_meta.cantrip_trace_id`) on `session/new` or
`session/prompt`; the Familiar ACP runtime stores it on the session and passes
it into `Cantrip.summon/3` or `Cantrip.send/3` so entity, turn, gate, usage,
child, and code events carry the caller's external trace ID. Other `_meta`
fields are ignored by Cantrip's ACP boundary; editor metadata cannot override
the configured LLM, loom path, or turn budget.

```json
{
  "jsonrpc": "2.0",
  "id": 7,
  "method": "session/prompt",
  "params": {
    "sessionId": "sess_123",
    "_meta": {"trace_id": "http-request-abc"},
    "prompt": [{"type": "text", "text": "Inspect the failing test"}]
  }
}
```

When no external trace ID is supplied, Cantrip mints a fresh per-session entity
trace ID.

---

## What is not emitted (and why)

- **LLM provider request/response bodies.** Too large and contain prompts.
  Use `:telemetry.attach_many` with your own redaction if you need partial
  visibility into provider traffic; do not log raw bodies.
- **Loom record contents.** The loom is the durable trace; subscribe to the
  loom directly via `Cantrip.Loom` API if you need turn-level data. Telemetry
  is for operational metrics, not data plane.
- **Stack traces.** Errors arrive as already-redacted observation strings.
  Unredacted stack traces stay internal.

---

## Event Registry In Code

The runtime event registry is used by tests and documentation review. New
telemetry surfaces should be added there first, then pinned by a regression
test and documented in the table above.
