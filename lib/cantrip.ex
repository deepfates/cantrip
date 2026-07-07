defmodule Cantrip do
  @moduledoc """
  When you call `Cantrip.new/1`, you are constructing a cantrip: a reusable
  value that binds an LLM, an identity, and a circle. Cast it with
  `Cantrip.cast/3` and one entity is summoned into the circle for one episode;
  summon it with `Cantrip.summon/1` and the entity stays alive across many
  sends. In the default port code sandbox, a code-medium inhabitant can use the
  same `new`/`cast`/`cast_batch` calls to construct and run child cantrips;
  Dune circles use injected host closures instead. The shape is shared by
  humans and inhabitants, with sandbox-specific affordances.

  Public API for building and running Cantrip programs.

  A cantrip combines an LLM, an identity, a circle, optional loom storage,
  retry configuration, and folding options into a reusable runtime program.
  `Cantrip.new/1` validates that configuration, and `Cantrip.cast/3` runs one
  entity episode against an intent.

  The usual entry points are:

  - `new/1` to construct a reusable cantrip.
  - `cast/3` to run one episode and return `{result, next_cantrip, loom, meta}`.
  - `cast_batch/2` to fan out work to child cantrips while preserving request
    order.
  - `summon/2` and `send/3` to keep an entity process alive across multiple
    intents.
  - `Cantrip.Loom.fork/4` to replay a loom prefix and branch from an earlier
    turn.

  Composition deliberately uses this same public API. Code-medium entities
  create children with `Cantrip.new/1`, run them with `Cantrip.cast/3` or
  `Cantrip.cast_batch/2`, and return compact summaries upward.
  """

  import Kernel, except: [send: 2]

  alias Cantrip.{Identity, Circle, EntityServer, Loom, WardPolicy, Gate}
  alias Cantrip.Medium.Registry, as: MediumRegistry

  @enforce_keys [:id, :llm_module, :llm_state, :identity, :circle]
  @derive {Inspect, except: [:llm_state, :child_llm]}
  defstruct schema_version: 1,
            id: nil,
            llm_module: nil,
            llm_state: nil,
            child_llm: nil,
            node: nil,
            identity: nil,
            circle: nil,
            loom_storage: nil,
            retry: %{max_retries: 0, retryable_status_codes: []},
            folding: %{}

  @type t :: %__MODULE__{
          id: String.t(),
          schema_version: pos_integer(),
          llm_module: module(),
          llm_state: term(),
          child_llm: {module(), term()} | nil,
          node: node() | nil,
          identity: Identity.t(),
          circle: Circle.t(),
          loom_storage: term(),
          retry: map(),
          folding: map()
        }

  @retry_schema [
    max_retries: [type: :non_neg_integer, default: 0],
    retryable_status_codes: [type: {:list, :integer}, default: []],
    backoff_base_ms: [type: :pos_integer, default: 1_000],
    backoff_max_ms: [type: :pos_integer, default: 30_000]
  ]

  @root_schema [
    llm: [type: :any],
    identity: [type: :any, default: %{}],
    circle: [type: :any, default: %{}],
    child_llm: [type: :any],
    node: [type: :atom],
    loom_storage: [type: {:custom, __MODULE__, :validate_loom_storage_option, []}],
    retry: [type: :any, default: %{}],
    folding: [type: :any, default: %{}],
    schema_version: [type: {:in, [1]}, default: 1],
    parent_context: [type: :any]
  ]

  @folding_schema [
    threshold_tokens: [type: :pos_integer],
    trigger_after_turns: [type: :pos_integer]
  ]

  @doc """
  Builds a reusable cantrip from keyword or map attributes.

  Required attributes are:

  - `:llm` as `{module, state}` implementing `Cantrip.LLM`.
  - `:circle` with exactly one medium declaration, gates, and wards.

  Optional attributes include `:identity`, `:child_llm`, `:loom_storage`,
  `:retry`, and `:folding`.
  """
  @spec new(keyword() | map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) do
    attrs = normalize_input_map(attrs)

    with {:ok, attrs} <- normalize_node_attr(attrs) do
      remote_node = remote_node(attrs)

      parent_context =
        Map.get(attrs, :parent_context) || Map.get(attrs, "parent_context") ||
          Process.get(:cantrip_parent_context)

      case {remote_node, parent_context} do
        {{:remote, node}, nil} -> remote_new(node, attrs)
        {:local, nil} -> new_root(attrs)
        {{:error, reason}, _parent_context} -> {:error, reason}
        {_node, parent_context} -> new_child(attrs, parent_context)
      end
    end
  end

  @doc false
  def __remote_new__(attrs) do
    attrs = normalize_input_map(attrs)

    with {:ok, attrs} <- normalize_node_attr(attrs) do
      attrs
      |> drop_node_attr()
      |> new_root()
    end
  end

  @doc false
  def __remote_cast__(%__MODULE__{} = cantrip, intent, opts) do
    cantrip
    |> Map.put(:node, nil)
    |> run_cast(coerce_intent(intent), remote_safe_cast_opts(opts))
  end

  defp new_root(attrs) do
    with {:ok, attrs} <- validate_root_attrs(attrs),
         {:ok, retry} <- validate_retry(Map.get(attrs, :retry, %{})),
         {:ok, folding} <- validate_folding(Map.get(attrs, :folding, %{})) do
      llm = Map.get(attrs, :llm)
      identity = Identity.new(Map.get(attrs, :identity, %{}))

      circle =
        attrs
        |> Map.get(:circle, %{})
        |> Circle.new()
        |> materialize_default_code_sandbox()

      with :ok <- validate_llm(llm),
           :ok <- validate_circle(circle, identity) do
        {module, state} = llm

        {:ok,
         %__MODULE__{
           schema_version: Map.fetch!(attrs, :schema_version),
           id: "cantrip_" <> Integer.to_string(System.unique_integer([:positive])),
           llm_module: module,
           llm_state: state,
           child_llm: normalize_child_llm(Map.get(attrs, :child_llm), llm),
           node: Map.get(attrs, :node),
           identity: identity,
           circle: circle,
           loom_storage: Map.get(attrs, :loom_storage),
           retry: retry,
           folding: folding
         }}
      end
    end
  end

  defp materialize_default_code_sandbox(%Circle{type: :code, wards: wards} = circle) do
    if Enum.any?(wards, &(Map.has_key?(&1, :sandbox) or Map.has_key?(&1, "sandbox"))) do
      circle
    else
      %{circle | wards: wards ++ [%{sandbox: :port}]}
    end
  end

  defp materialize_default_code_sandbox(circle), do: circle

  @doc false
  # Internal representation of child inheritance: LLM selection, ward
  # composition, depth limits, inherited gate dependencies, cancellation,
  # streaming, and loom grafting context.
  @spec parent_context(t(), keyword() | map()) :: map()
  def parent_context(%__MODULE__{} = parent, opts \\ %{}) do
    opts = Map.new(opts)

    %{
      parent_cantrip: parent,
      depth: Map.get(opts, :depth, 0),
      child_llm:
        Map.get(opts, :child_llm) || parent.child_llm || {parent.llm_module, parent.llm_state},
      cancel_on_parent: Map.get(opts, :cancel_on_parent, []),
      stream_to: Map.get(opts, :stream_to),
      stream_barrier?: Map.get(opts, :stream_barrier?, false),
      entity_state: Map.get(opts, :entity_state),
      trace_id: Map.get(opts, :trace_id),
      child_spawn_counter: Map.get(opts, :child_spawn_counter)
    }
  end

  defp new_child(attrs, parent_context) do
    parent_context = normalize_parent_context(parent_context)
    parent = Map.fetch!(parent_context, :parent_cantrip)
    depth = Map.get(parent_context, :depth, 0)
    max_depth = WardPolicy.max_depth(parent.circle.wards)

    if is_integer(max_depth) and depth >= max_depth do
      {:error, "max_depth exceeded"}
    else
      child_llm =
        Map.get(attrs, :llm) || Map.get(attrs, "llm") || Map.get(parent_context, :child_llm) ||
          parent.child_llm || {parent.llm_module, parent.llm_state}

      circle_attrs =
        attrs
        |> child_circle_attrs()
        |> Map.put_new(:type, parent.circle.type)

      requested_gates = requested_child_gates(circle_attrs, parent)
      child_wards = fetch(circle_attrs, :wards, [])
      child_gates = resolve_child_gates(parent, requested_gates, depth + 1, max_depth)

      child_circle_for_policy = %{
        type: fetch(circle_attrs, :type, parent.circle.type),
        gates: Map.values(child_gates),
        wards: child_wards
      }

      with :ok <- WardPolicy.validate_child_spawn(parent.circle.wards, child_circle_for_policy) do
        composed_wards = WardPolicy.compose(parent.circle.wards, child_wards)

        child_circle_attrs =
          circle_attrs
          |> Map.put(:gates, Map.values(child_gates))
          |> Map.put(:wards, composed_wards)

        child_identity = child_identity_attrs(attrs)

        child_attrs = %{
          llm: child_llm,
          child_llm: Map.get(attrs, :child_llm) || Map.get(attrs, "child_llm") || child_llm,
          node: Map.get(attrs, :node) || Map.get(attrs, "node"),
          identity: child_identity,
          circle: child_circle_attrs,
          loom_storage: Map.get(attrs, :loom_storage) || Map.get(attrs, "loom_storage"),
          retry: Map.get(attrs, :retry, parent.retry),
          folding: Map.get(attrs, :folding, parent.folding)
        }

        case remote_node(child_attrs) do
          {:remote, node} -> remote_new(node, child_attrs)
          {:error, reason} -> {:error, reason}
          _local -> new_root(child_attrs)
        end
      end
    end
  end

  defp child_identity_attrs(attrs) do
    case Map.get(attrs, :identity) || Map.get(attrs, "identity") do
      nil ->
        case Map.get(attrs, :system_prompt) || Map.get(attrs, "system_prompt") do
          nil ->
            %{
              system_prompt: """
              You are a child entity working on a specific task for a parent orchestrator.
              Work in variables when your medium is code.
              Call done.(result) with a concise answer when finished.
              The parent only sees your done() result, so make it informative but brief.
              """
            }

          prompt ->
            %{system_prompt: prompt}
        end

      prompt when is_binary(prompt) ->
        %{system_prompt: prompt}

      identity ->
        identity
    end
  end

  defp child_circle_attrs(attrs) do
    attrs
    |> fetch(:circle, %{})
    |> Map.new()
    |> maybe_put(:type, fetch(attrs, :circle_type, nil))
    |> maybe_put(:type, fetch(attrs, :medium, nil))
    |> maybe_put(:gates, fetch(attrs, :gates, nil))
    |> maybe_put(:wards, fetch(attrs, :wards, nil))
    |> maybe_put(:medium_opts, fetch(attrs, :medium_opts, nil))
  end

  defp requested_child_gates(circle_attrs, parent) do
    circle_attrs
    |> fetch(:gates, Gate.names(parent.circle))
    |> Enum.map(&normalize_requested_child_gate/1)
    |> append_done_gate()
    |> uniq_requested_child_gates()
  end

  defp normalize_requested_child_gate(name) when is_atom(name),
    do: {:bare, Atom.to_string(name)}

  defp normalize_requested_child_gate(name) when is_binary(name), do: {:bare, name}

  defp normalize_requested_child_gate(%{} = gate) do
    name = fetch(gate, :name, nil)
    gate = gate |> Map.delete("name") |> Map.put(:name, to_string(name))
    {:explicit, gate}
  end

  defp append_done_gate(requested_gates) do
    if Enum.any?(requested_gates, &(requested_child_gate_name(&1) == "done")) do
      requested_gates
    else
      requested_gates ++ [{:bare, "done"}]
    end
  end

  defp uniq_requested_child_gates(requested_gates) do
    requested_gates
    |> Enum.reduce({[], []}, fn requested, {names, acc} ->
      name = requested_child_gate_name(requested)

      if name in names do
        {names, acc}
      else
        {[name | names], [requested | acc]}
      end
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp requested_child_gate_name({:bare, name}), do: name
  defp requested_child_gate_name({:explicit, gate}), do: fetch(gate, :name, nil)

  defp requested_child_gate_name(gate) do
    gate |> normalize_requested_child_gate() |> requested_child_gate_name()
  end

  defp resolve_child_gates(parent, requested_gates, _child_depth, _max_depth) do
    parent_gate_map = parent.circle.gates
    parent_dependencies = collect_parent_dependencies(parent_gate_map)

    requested_gates
    |> Enum.map(fn requested ->
      name = requested_child_gate_name(requested)
      {name, resolve_child_gate(requested, parent_gate_map, parent_dependencies)}
    end)
    |> Map.new()
  end

  defp resolve_child_gate({:bare, name}, parent_gate_map, parent_dependencies) do
    case Map.get(parent_gate_map, name) do
      nil -> build_canonical_gate(name, parent_dependencies)
      gate -> gate
    end
  end

  defp resolve_child_gate(
         {:explicit, %{name: name} = requested},
         parent_gate_map,
         parent_dependencies
       ) do
    base = Map.get(parent_gate_map, name) || build_canonical_gate(name, parent_dependencies)
    merge_child_gate(base, requested)
  end

  defp resolve_child_gate(requested, parent_gate_map, parent_dependencies) do
    requested
    |> normalize_requested_child_gate()
    |> resolve_child_gate(parent_gate_map, parent_dependencies)
  end

  defp merge_child_gate(base, requested) do
    base_deps = gate_dependencies(base)
    requested_deps = gate_dependencies(requested)

    requested =
      requested
      |> Map.delete("dependencies")
      |> Map.put(:dependencies, Map.merge(base_deps, requested_deps))

    Map.merge(base, requested)
  end

  defp gate_dependencies(gate) do
    case Map.get(gate, :dependencies) || Map.get(gate, "dependencies") do
      %{} = deps ->
        deps
        |> Enum.reduce(%{}, fn {key, value}, acc ->
          case dependency_key(key) do
            nil -> acc
            key -> Map.put(acc, key, value)
          end
        end)

      _ ->
        %{}
    end
  end

  defp build_canonical_gate(name, parent_dependencies) do
    spec = Gate.spec(name)

    inherited =
      spec.depends_required
      |> Enum.reduce(%{}, fn key, acc ->
        case Map.get(parent_dependencies, key) do
          nil -> acc
          value -> Map.put(acc, key, value)
        end
      end)

    base = %{name: name, description: spec.description, parameters: spec.parameters}
    if map_size(inherited) > 0, do: Map.put(base, :dependencies, inherited), else: base
  end

  defp collect_parent_dependencies(parent_gate_map) do
    parent_gate_map
    |> Map.values()
    |> Enum.reduce(%{}, fn gate, acc ->
      acc
      |> merge_explicit_deps(gate)
      |> maybe_take_top_level(gate, :root)
    end)
  end

  defp merge_explicit_deps(acc, gate) do
    case Map.get(gate, :dependencies) || Map.get(gate, "dependencies") do
      %{} = deps ->
        Enum.reduce(deps, acc, fn {k, v}, acc ->
          case dependency_key(k) do
            nil -> acc
            key -> if Map.has_key?(acc, key), do: acc, else: Map.put(acc, key, v)
          end
        end)

      _ ->
        acc
    end
  end

  defp dependency_key(key) when is_atom(key), do: key

  defp dependency_key(key) when is_binary(key) do
    String.to_existing_atom(key)
  rescue
    ArgumentError -> nil
  end

  defp dependency_key(_key), do: nil

  defp maybe_take_top_level(acc, gate, key) do
    case Map.get(gate, key) || Map.get(gate, Atom.to_string(key)) do
      nil -> acc
      value -> if Map.has_key?(acc, key), do: acc, else: Map.put(acc, key, value)
    end
  end

  defp fetch(map, key, default) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key), default)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  @doc """
  Creates a persistent entity without running an intent.

  Returns `{:ok, pid}`. Use `send/2` or `send/3` to run intents against the
  same process. Medium state, message history, and the loom accumulate across
  those episodes.
  """
  @spec summon(t()) :: {:ok, pid()} | {:error, term()}
  def summon(%__MODULE__{} = cantrip) do
    spec = {EntityServer, cantrip: cantrip, lazy: true}
    DynamicSupervisor.start_child(Cantrip.EntitySupervisor, spec)
  end

  @doc """
  Creates a persistent entity without running an intent, with entity options.

  This is primarily useful for hosts that need to attach runtime metadata such
  as `:trace_id` before the first intent is sent.
  """
  @spec summon(t(), keyword()) :: {:ok, pid()} | {:error, term()}
  def summon(%__MODULE__{} = cantrip, opts) when is_list(opts) do
    spec = {EntityServer, [cantrip: cantrip, lazy: true] ++ opts}
    DynamicSupervisor.start_child(Cantrip.EntitySupervisor, spec)
  end

  @doc """
  Creates a persistent entity and immediately runs the first intent.

  This is equivalent to `summon/1` followed by `send/2`. Options such as
  `:stream_to` are passed to the entity process.
  """
  @spec summon(t(), String.t(), keyword()) ::
          {:ok, pid(), term(), t(), Loom.t(), map()} | {:error, term(), t()}
  def summon(%__MODULE__{} = cantrip, intent, opts \\ []) when is_binary(intent) do
    spec = {EntityServer, [cantrip: cantrip, lazy: true] ++ opts}

    with {:ok, pid} <- DynamicSupervisor.start_child(Cantrip.EntitySupervisor, spec) do
      case send(pid, intent) do
        {:ok, result, next_cantrip, loom, meta} ->
          {:ok, pid, result, next_cantrip, loom, meta}

        {:error, reason, next_cantrip} ->
          {:error, reason, next_cantrip}

        {:error, reason} ->
          {:error, reason, cantrip}
      end
    end
  end

  @doc """
  Sends a new intent to a persistent entity.

  State owned by the entity process, including loom, code-medium bindings, and
  message history, accumulates across all sends.
  """
  @spec send(pid(), String.t()) ::
          {:ok, term(), t(), Loom.t(), map()} | {:error, term()}
  def send(pid, intent) when is_pid(pid) and is_binary(intent) do
    EntityServer.send_intent(pid, intent)
  end

  @doc "Sends a new intent with per-call options, for example `stream_to: pid`."
  def send(pid, intent, opts) when is_pid(pid) and is_binary(intent) and is_list(opts) do
    EntityServer.send_intent(pid, intent, opts)
  end

  @doc """
  Interrupts a persistent entity's active episode at the next safe turn boundary.

  The entity process stays alive, its loom records the interruption, and queued
  sends continue after the interrupted episode returns.
  """
  @spec interrupt(pid(), term()) :: :ok
  def interrupt(pid, reason \\ :interrupt) when is_pid(pid) do
    EntityServer.interrupt(pid, reason)
  end

  @doc """
  Queues a steering message for delivery at the next turn boundary.

  Steering does not end the active episode. The message is appended to the
  entity's message history and loom as an intent before the next provider turn.
  """
  @spec steer(pid(), String.t()) :: :ok
  def steer(pid, message) when is_pid(pid) and is_binary(message) do
    EntityServer.steer(pid, message)
  end

  @doc """
  Immediately terminates a persistent entity after recording and closing its loom.
  """
  @spec hard_stop(pid(), term()) :: :ok
  def hard_stop(pid, reason \\ :hard_stop) when is_pid(pid) do
    EntityServer.hard_stop(pid, reason)
  end

  @doc """
  Runs one entity episode for `intent`.

  The returned cantrip carries updated reusable runtime configuration. The loom
  contains the durable turn record for the episode, and `meta` includes
  termination information such as truncation.
  """
  @spec cast(t(), String.t() | nil) ::
          {:ok, term(), t(), Cantrip.Loom.t(), map()} | {:error, String.t(), t()}
  def cast(cantrip, nil), do: {:error, "intent is required", cantrip}

  def cast(%__MODULE__{} = cantrip, intent) when is_binary(intent) do
    cast(cantrip, intent, [])
  end

  def cast(%__MODULE__{} = cantrip, intent) do
    cast(cantrip, coerce_intent(intent), [])
  end

  @spec cast(t(), String.t() | nil, keyword()) ::
          {:ok, term(), t(), Cantrip.Loom.t(), map()} | {:error, String.t(), t()}
  def cast(cantrip, nil, _opts), do: {:error, "intent is required", cantrip}

  def cast(%__MODULE__{} = cantrip, intent, opts) when is_binary(intent) and is_list(opts) do
    run_cast_with_parent_context(cantrip, intent, opts)
  end

  def cast(%__MODULE__{} = cantrip, intent, opts) when is_list(opts) do
    run_cast_with_parent_context(cantrip, coerce_intent(intent), opts)
  end

  @doc """
  Cast multiple cantrips and return their results in request order.

  When called from inside a parent code-medium turn, this uses the same explicit
  parent context as `cast/2`, records one `cast_batch` observation on the
  parent loom, and grafts all child turns under that parent turn.
  """
  @spec cast_batch([map()], keyword()) ::
          {:ok, [term()], [t()], [Cantrip.Loom.t()], map()} | {:error, term()}
  def cast_batch(items, opts \\ []) when is_list(items) and is_list(opts) do
    parent_context = Keyword.get(opts, :parent_context) || Process.get(:cantrip_parent_context)
    max_concurrency = cast_batch_max_concurrency(parent_context)
    timeout = Keyword.get(opts, :timeout, :infinity)

    case normalize_cast_batch_items(items) do
      {:ok, normalized_items} ->
        payloads =
          normalized_items
          |> Enum.with_index()
          |> Task.async_stream(
            fn {%{cantrip: cantrip, intent: intent}, index} ->
              cast(cantrip, intent,
                parent_context: parent_context,
                record_parent_observation?: false,
                parent_gate: "cast_batch",
                batch_index: index
              )
            end,
            ordered: true,
            max_concurrency: max_concurrency,
            timeout: timeout
          )
          |> Enum.map(fn
            {:ok, payload} -> payload
            {:exit, reason} -> {:error, reason, nil}
          end)

        if Enum.any?(payloads, &match?({:error, _, _}, &1)) do
          reason =
            payloads
            |> Enum.find(&match?({:error, _, _}, &1))
            |> elem(1)

          push_parent_cast_observation(
            parent_context,
            "cast_batch",
            Cantrip.SafeFormat.inspect(reason),
            true,
            [],
            cast_batch_observation_meta(normalized_items, payloads)
          )

          {:error, reason}
        else
          values = Enum.map(payloads, fn {:ok, value, _next, _loom, _meta} -> value end)
          next_cantrips = Enum.map(payloads, fn {:ok, _value, next, _loom, _meta} -> next end)
          looms = Enum.map(payloads, fn {:ok, _value, _next, loom, _meta} -> loom end)
          child_turns = Enum.flat_map(looms, & &1.turns)

          push_parent_cast_observation(
            parent_context,
            "cast_batch",
            values,
            false,
            child_turns,
            cast_batch_observation_meta(normalized_items, payloads)
          )

          {:ok, values, next_cantrips, looms, %{count: length(values)}}
        end

      {:error, reason} ->
        push_parent_cast_observation(
          parent_context,
          "cast_batch",
          Cantrip.SafeFormat.inspect(reason),
          true,
          [],
          cast_batch_observation_meta(items, nil)
        )

        {:error, reason}
    end
  end

  defp normalize_cast_batch_items(items) do
    items
    |> Enum.with_index()
    |> Enum.reduce_while({:ok, []}, fn {item, index}, {:ok, acc} ->
      case normalize_cast_batch_item(item, index) do
        {:ok, normalized} -> {:cont, {:ok, [normalized | acc]}}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
    |> case do
      {:ok, normalized} -> {:ok, Enum.reverse(normalized)}
      error -> error
    end
  end

  defp normalize_cast_batch_item(item, index) when is_map(item) or is_list(item) do
    item = Map.new(item)

    with {:ok, cantrip} <- fetch_cast_batch_cantrip(item, index),
         {:ok, intent} <- fetch_cast_batch_intent(item, index) do
      {:ok, %{cantrip: cantrip, intent: intent}}
    end
  rescue
    ArgumentError -> {:error, {:invalid_cast_batch_item, index, :expected_map_or_keyword}}
  end

  defp normalize_cast_batch_item(_item, index),
    do: {:error, {:invalid_cast_batch_item, index, :expected_map_or_keyword}}

  defp fetch_cast_batch_cantrip(item, index) do
    case fetch_required(item, :cantrip) do
      %__MODULE__{} = cantrip -> {:ok, cantrip}
      nil -> {:error, {:invalid_cast_batch_item, index, :missing_cantrip}}
      _other -> {:error, {:invalid_cast_batch_item, index, :invalid_cantrip}}
    end
  end

  defp fetch_cast_batch_intent(item, index) do
    case fetch_required(item, :intent) do
      nil -> {:error, {:invalid_cast_batch_item, index, :missing_intent}}
      intent -> {:ok, coerce_intent(intent)}
    end
  end

  defp fetch_required(map, key) do
    Map.get(map, key) || Map.get(map, Atom.to_string(key))
  end

  defp cast_batch_max_concurrency(nil), do: System.schedulers_online()

  defp cast_batch_max_concurrency(parent_context) do
    parent_context = normalize_parent_context(parent_context)
    parent = Map.get(parent_context, :parent_cantrip)

    if parent do
      WardPolicy.max_concurrent_children(parent.circle.wards)
    else
      System.schedulers_online()
    end
  end

  @doc """
  Runs one entity episode while exposing streaming events.

  Returns `{stream, task}` where:

  - `stream` is an `Enumerable` of `{:cantrip_event, event}` tuples
  - `task` is a `Task` that resolves to the final `{:ok, result, cantrip, loom, meta}` or error

  Events follow the runtime hierarchy: `:step_start`, `:message_start`,
  `:text`, `:tool_call`, `:tool_result`, `:usage`, `:message_complete`,
  `:step_complete`, `:final_response`.
  """
  @spec cast_stream(t(), String.t()) :: {Enumerable.t(), Task.t()}
  def cast_stream(%__MODULE__{} = cantrip, intent) when is_binary(intent) do
    caller = self()

    task =
      Task.async(fn ->
        run_cast(cantrip, intent, stream_to: caller, stream_barrier?: true)
      end)

    stream =
      Stream.resource(
        fn -> :running end,
        &stream_next/1,
        fn
          :done -> :ok
          :running -> Task.shutdown(task, :brutal_kill)
        end
      )

    {stream, task}
  end

  defp stream_next(:done), do: {:halt, :done}

  defp stream_next(:running) do
    receive do
      {:cantrip_event, event} ->
        {[event], :running}

      {:cantrip_barrier, from, ref} ->
        Kernel.send(from, {:cantrip_barriered, ref})
        stream_next(:running)

      {ref, result} when is_reference(ref) ->
        # Task completed — drain any remaining events, then stop
        Process.demonitor(ref, [:flush])
        remaining = drain_events()
        {remaining ++ [{:done, result}], :done}

      {:DOWN, _ref, :process, _pid, reason} ->
        {[{:done, {:error, reason}}], :done}
    end
  end

  defp drain_events do
    receive do
      {:cantrip_event, event} ->
        [event | drain_events()]

      {:cantrip_barrier, from, ref} ->
        Kernel.send(from, {:cantrip_barriered, ref})
        drain_events()
    after
      0 -> []
    end
  end

  @doc """
  Deprecated compatibility wrapper for `Cantrip.Loom.fork/4`.
  """
  @deprecated "Use Cantrip.Loom.fork/4"
  @spec fork(t(), Loom.t(), non_neg_integer(), map()) ::
          {:ok, term(), t(), Loom.t(), map()} | {:error, term(), t()}
  def fork(%__MODULE__{} = cantrip, %Loom{} = loom, from_turn, opts) do
    Loom.fork(cantrip, loom, from_turn, opts)
  end

  @doc false
  @spec __fork__(t(), Loom.t(), non_neg_integer(), map()) ::
          {:ok, term(), t(), Loom.t(), map()} | {:error, term(), t()}
  def __fork__(%__MODULE__{} = cantrip, %Loom{} = loom, from_turn, opts) do
    opts = Map.new(opts)
    intent = Map.fetch!(opts, :intent)
    llm = Map.get(opts, :llm, {cantrip.llm_module, cantrip.llm_state})

    prefix_turns = Enum.take(loom.turns, from_turn)
    prefix_messages = messages_from_turns(prefix_turns, cantrip.identity)

    # CIRCLE-11: inject capability presentation for code/bash circles
    capability_text = MediumRegistry.present(cantrip.circle).capability_text

    prefix_messages =
      if capability_text do
        inject_capability(prefix_messages, capability_text)
      else
        prefix_messages
      end

    fork_messages = prefix_messages ++ [%{role: :user, content: intent}]
    fork_loom = %{loom | turns: prefix_turns}

    # LOOM-4: Restore sandbox state from the fork point (snapshot strategy)
    fork_code_state =
      case List.last(prefix_turns) do
        %{code_state: cs} when is_map(cs) -> cs
        _ -> %{}
      end

    {:ok, forked_cantrip} =
      new(
        llm: llm,
        identity: Map.from_struct(cantrip.identity),
        circle: %{
          gates: Map.values(cantrip.circle.gates),
          wards: cantrip.circle.wards,
          type: cantrip.circle.type
        },
        loom_storage: cantrip.loom_storage,
        child_llm: cantrip.child_llm,
        retry: cantrip.retry,
        folding: cantrip.folding
      )

    run_cast(forked_cantrip, intent,
      messages: fork_messages,
      loom: fork_loom,
      turns: length(prefix_turns),
      code_state: fork_code_state
    )
  end

  defp coerce_intent(intent) when is_binary(intent), do: intent

  defp coerce_intent(intent),
    do: Cantrip.SafeFormat.inspect(intent, pretty: true, limit: :infinity)

  defp run_cast_with_parent_context(%__MODULE__{} = cantrip, intent, opts) do
    parent_context = Keyword.get(opts, :parent_context) || Process.get(:cantrip_parent_context)

    case {remote_node(cantrip), parent_context} do
      {{:remote, node}, nil} ->
        remote_cast(node, cantrip, intent, opts)

      {{:remote, node}, parent_context} ->
        opts = Keyword.delete(opts, :parent_context)
        run_remote_child_cast(node, cantrip, intent, opts, parent_context)

      {_local, nil} ->
        run_cast(cantrip, intent, opts)

      {_local, parent_context} ->
        opts = Keyword.delete(opts, :parent_context)
        run_child_cast(cantrip, intent, opts, parent_context)
    end
  end

  defp run_remote_child_cast(node, %__MODULE__{} = cantrip, intent, opts, parent_context) do
    parent_context = normalize_parent_context(parent_context)
    entity_state = Map.get(parent_context, :entity_state)
    record_observation? = Keyword.get(opts, :record_parent_observation?, true)
    parent_gate = Keyword.get(opts, :parent_gate, "cast")
    batch_index = Keyword.get(opts, :batch_index)
    opts = Keyword.drop(opts, [:record_parent_observation?, :parent_gate, :batch_index])

    case prepare_child_cast(cantrip, parent_context) do
      {:ok, transient_cantrip, depth} ->
        cast_opts =
          opts
          |> Keyword.put_new(:depth, depth)
          |> Keyword.put_new(:trace_id, Map.get(parent_context, :trace_id))
          |> remote_safe_cast_opts()

        emit_parent_event(
          entity_state,
          {:child_start,
           child_event_meta(transient_cantrip, depth, intent,
             node: node,
             batch_index: batch_index
           )}
        )

        emit_child_start_telemetry(parent_context, depth)

        case remote_cast(node, transient_cantrip, intent, cast_opts) do
          {:ok, value, next_cantrip, child_loom, meta} ->
            next_cantrip = restore_child_declared_wards(cantrip, next_cantrip)

            emit_parent_event(
              entity_state,
              {:child_end,
               child_event_meta(transient_cantrip, depth, nil,
                 result: value,
                 node: node,
                 batch_index: batch_index
               )}
            )

            emit_child_stop_telemetry(parent_context, depth, :ok)

            if record_observation?,
              do:
                push_parent_cast_observation(
                  parent_context,
                  parent_gate,
                  value,
                  false,
                  child_loom.turns,
                  child_observation_meta(transient_cantrip,
                    node: node,
                    batch_index: batch_index
                  )
                )

            {:ok, value, next_cantrip, child_loom, meta}

          {:error, reason, next_cantrip} ->
            next_cantrip = restore_child_declared_wards(cantrip, next_cantrip)

            emit_parent_event(
              entity_state,
              {:child_end,
               child_event_meta(transient_cantrip, depth, nil,
                 error: Cantrip.SafeFormat.inspect(reason),
                 node: node,
                 batch_index: batch_index
               )}
            )

            emit_child_stop_telemetry(parent_context, depth, :error)

            if record_observation?,
              do:
                push_parent_cast_observation(
                  parent_context,
                  parent_gate,
                  Cantrip.SafeFormat.inspect(reason),
                  true,
                  [],
                  child_observation_meta(transient_cantrip,
                    node: node,
                    batch_index: batch_index
                  )
                )

            {:error, reason, %{next_cantrip | node: node}}
        end

      {:error, reason, next_cantrip} ->
        if record_observation?,
          do:
            push_parent_cast_observation(
              parent_context,
              parent_gate,
              Cantrip.SafeFormat.inspect(reason),
              true,
              [],
              child_observation_meta(cantrip, node: node, batch_index: batch_index)
            )

        {:error, reason, next_cantrip}
    end
  end

  defp run_child_cast(%__MODULE__{} = cantrip, intent, opts, parent_context) do
    parent_context = normalize_parent_context(parent_context)
    entity_state = Map.get(parent_context, :entity_state)
    record_observation? = Keyword.get(opts, :record_parent_observation?, true)
    parent_gate = Keyword.get(opts, :parent_gate, "cast")
    batch_index = Keyword.get(opts, :batch_index)
    opts = Keyword.drop(opts, [:record_parent_observation?, :parent_gate, :batch_index])

    case prepare_child_cast(cantrip, parent_context) do
      {:ok, transient_cantrip, depth} ->
        transient_cantrip = refresh_default_child_llm(transient_cantrip, parent_context)

        cast_opts =
          opts
          |> Keyword.put_new(:depth, depth)
          |> Keyword.put_new(:trace_id, Map.get(parent_context, :trace_id))
          |> Keyword.put_new(:cancel_on_parent, child_cancel_on_parent(parent_context))
          |> maybe_put_new(:stream_to, Map.get(parent_context, :stream_to))
          |> maybe_put_new(:stream_barrier?, Map.get(parent_context, :stream_barrier?))

        emit_parent_event(
          entity_state,
          {:child_start,
           child_event_meta(transient_cantrip, depth, intent, batch_index: batch_index)}
        )

        emit_child_start_telemetry(parent_context, depth)

        case run_cast(transient_cantrip, intent, cast_opts) do
          {:ok, value, next_cantrip, child_loom, meta} ->
            next_cantrip = restore_child_declared_wards(cantrip, next_cantrip)
            remember_parent_child_llm(parent_context, next_cantrip)

            emit_parent_event(
              entity_state,
              {:child_end,
               child_event_meta(transient_cantrip, depth, nil,
                 result: value,
                 batch_index: batch_index
               )}
            )

            emit_child_stop_telemetry(parent_context, depth, :ok)

            if record_observation?,
              do:
                push_parent_cast_observation(
                  parent_context,
                  parent_gate,
                  value,
                  false,
                  child_loom.turns,
                  child_observation_meta(transient_cantrip, batch_index: batch_index)
                )

            {:ok, value, next_cantrip, child_loom, meta}

          {:error, reason, next_cantrip} ->
            next_cantrip = restore_child_declared_wards(cantrip, next_cantrip)
            remember_parent_child_llm(parent_context, next_cantrip)

            emit_parent_event(
              entity_state,
              {:child_end,
               child_event_meta(transient_cantrip, depth, nil,
                 error: Cantrip.SafeFormat.inspect(reason),
                 batch_index: batch_index
               )}
            )

            emit_child_stop_telemetry(parent_context, depth, :error)

            if record_observation?,
              do:
                push_parent_cast_observation(
                  parent_context,
                  parent_gate,
                  Cantrip.SafeFormat.inspect(reason),
                  true,
                  [],
                  child_observation_meta(transient_cantrip, batch_index: batch_index)
                )

            {:error, reason, next_cantrip}
        end

      {:error, reason, _next_cantrip} = error ->
        if record_observation?,
          do:
            push_parent_cast_observation(
              parent_context,
              parent_gate,
              Cantrip.SafeFormat.inspect(reason),
              true,
              [],
              child_observation_meta(cantrip, batch_index: batch_index)
            )

        error
    end
  end

  defp prepare_child_cast(%__MODULE__{} = cantrip, parent_context) do
    parent = Map.fetch!(parent_context, :parent_cantrip)
    depth = Map.get(parent_context, :depth, 0)
    max_depth = WardPolicy.max_depth(parent.circle.wards)

    cond do
      is_integer(max_depth) and depth >= max_depth ->
        reject_child_cast(parent_context, cantrip, "max_depth exceeded")

      true ->
        with :ok <- validate_declared_child_spawn(parent_context, cantrip),
             :ok <- reserve_child_spawn(parent_context) do
          composed_wards = WardPolicy.compose(parent.circle.wards, cantrip.circle.wards)
          child_circle = %{cantrip.circle | wards: composed_wards}
          {:ok, %{cantrip | circle: child_circle}, depth + 1}
        else
          {:error, reason} -> reject_child_cast(parent_context, cantrip, reason)
        end
    end
  end

  defp validate_declared_child_spawn(parent_context, cantrip) do
    parent = Map.fetch!(parent_context, :parent_cantrip)
    WardPolicy.validate_child_spawn(parent.circle.wards, cantrip.circle)
  end

  defp reserve_child_spawn(parent_context) do
    parent = Map.fetch!(parent_context, :parent_cantrip)

    case {WardPolicy.max_children_total(parent.circle.wards),
          Map.get(parent_context, :child_spawn_counter)} do
      {nil, _counter} ->
        :ok

      {_max_total, nil} ->
        :ok

      {max_total, counter} when is_pid(counter) ->
        Agent.get_and_update(counter, fn count ->
          if count < max_total do
            {:ok, count + 1}
          else
            {{:error, "max_children_total exceeded: #{max_total}"}, count}
          end
        end)
    end
  end

  defp reject_child_cast(parent_context, cantrip, reason) do
    emit_child_rejected_telemetry(parent_context, cantrip, reason)
    {:error, reason, cantrip}
  end

  defp emit_child_rejected_telemetry(parent_context, cantrip, reason) do
    parent = Map.get(parent_context, :entity_state)

    if parent do
      Cantrip.Telemetry.execute(
        [:cantrip, :ward, :child_rejected],
        %{count: 1},
        %{
          entity_id: parent.entity_id,
          trace_id: Map.get(parent_context, :trace_id),
          child_id: cantrip.id,
          child_medium: cantrip.circle.type,
          reason: reason
        }
      )
    end
  end

  defp restore_child_declared_wards(%__MODULE__{} = declared, %__MODULE__{} = next) do
    %{next | circle: %{next.circle | wards: declared.circle.wards}}
  end

  defp run_cast(%__MODULE__{} = cantrip, intent, extra_opts) do
    spec = {EntityServer, cantrip: cantrip, intent: intent}
    spec = put_elem(spec, 1, Keyword.merge(elem(spec, 1), extra_opts))

    case DynamicSupervisor.start_child(Cantrip.EntitySupervisor, spec) do
      {:ok, pid} ->
        case safe_run_entity(pid) do
          {:ok, result, next_cantrip, loom, meta} ->
            {:ok, result, next_cantrip, loom, meta}

          {:error, reason, next_cantrip} ->
            {:error, reason, next_cantrip}

          {:error, reason} ->
            {:error, reason, cantrip}
        end

      {:error, reason} ->
        {:error, reason, cantrip}
    end
  end

  defp safe_run_entity(pid) do
    try do
      EntityServer.run(pid)
    catch
      :exit, reason -> {:error, reason}
    end
  end

  defp remote_new(node, attrs) do
    attrs = drop_node_attr(attrs)

    case rpc_call(node, __MODULE__, :__remote_new__, [attrs]) do
      {:ok, %__MODULE__{} = cantrip} ->
        {:ok, %{cantrip | node: node}}

      {:error, reason} ->
        {:error, reason}

      {:badrpc, reason} ->
        {:error,
         "remote node #{node} failed to build cantrip: #{Cantrip.SafeFormat.inspect(reason)}"}

      other ->
        {:error,
         "remote node #{node} returned invalid cantrip response: #{Cantrip.SafeFormat.inspect(other)}"}
    end
  end

  defp remote_cast(node, %__MODULE__{} = cantrip, intent, opts) do
    cantrip = %{cantrip | node: nil}

    case rpc_call(node, __MODULE__, :__remote_cast__, [
           cantrip,
           intent,
           remote_safe_cast_opts(opts)
         ]) do
      {:ok, value, %__MODULE__{} = next, loom, meta} ->
        {:ok, value, %{next | node: node}, loom, meta}

      {:error, reason, %__MODULE__{} = next} ->
        {:error, reason, %{next | node: node}}

      {:error, reason, next} ->
        {:error, reason, next}

      {:badrpc, reason} ->
        {:error,
         "remote node #{node} failed to cast cantrip: #{Cantrip.SafeFormat.inspect(reason)}",
         %{cantrip | node: node}}

      other ->
        {:error,
         "remote node #{node} returned invalid cast response: #{Cantrip.SafeFormat.inspect(other)}",
         %{cantrip | node: node}}
    end
  end

  defp remote_safe_cast_opts(opts) when is_list(opts) do
    Keyword.drop(opts, [
      :parent_context,
      :record_parent_observation?,
      :stream_to,
      :stream_barrier?,
      :cancel_on_parent
    ])
  end

  defp remote_safe_cast_opts(_opts), do: []

  defp rpc_call(node, module, function, args) do
    rpc = Application.get_env(:cantrip, :rpc_module, :rpc)
    apply(rpc, :call, [node, module, function, args, rpc_timeout()])
  end

  defp rpc_timeout do
    case Application.get_env(:cantrip, :rpc_timeout, 30_000) do
      timeout when is_integer(timeout) and timeout > 0 -> timeout
      _other -> 30_000
    end
  end

  defp remote_node(%__MODULE__{node: nil}), do: :local
  defp remote_node(%__MODULE__{node: node}) when node == node(), do: :local
  defp remote_node(%__MODULE__{node: node}) when is_atom(node), do: {:remote, node}

  defp remote_node(attrs) when is_map(attrs) do
    case Map.get(attrs, :node) || Map.get(attrs, "node") do
      nil -> :local
      node when node == node() -> :local
      node when is_atom(node) -> {:remote, node}
      other -> {:error, unknown_node_error(other)}
    end
  end

  defp normalize_node_attr(attrs) when is_map(attrs) do
    case Map.fetch(attrs, :node) do
      {:ok, node} ->
        put_normalized_node(attrs, node)

      :error ->
        case Map.fetch(attrs, "node") do
          {:ok, node} -> attrs |> Map.delete("node") |> put_normalized_node(node)
          :error -> {:ok, attrs}
        end
    end
  end

  defp put_normalized_node(attrs, node) do
    case normalize_node_value(node) do
      {:ok, node} -> {:ok, Map.put(attrs, :node, node)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp normalize_node_value(node) when is_atom(node), do: {:ok, node}

  defp normalize_node_value(node) when is_binary(node) do
    case Enum.find([node() | Node.list()], fn known -> Atom.to_string(known) == node end) do
      nil -> existing_atom_or_error(node)
      known -> {:ok, known}
    end
  end

  defp normalize_node_value(node), do: {:error, unknown_node_error(node)}

  defp existing_atom_or_error(value) do
    {:ok, String.to_existing_atom(value)}
  rescue
    ArgumentError -> {:error, unknown_node_error(value)}
  end

  defp unknown_node_error(value),
    do:
      "unknown remote node #{Cantrip.SafeFormat.inspect(value)}; connect the node before using it"

  defp drop_node_attr(attrs) when is_map(attrs) do
    attrs
    |> Map.delete(:node)
    |> Map.delete("node")
  end

  defp maybe_put_new(opts, _key, nil), do: opts
  defp maybe_put_new(opts, key, value), do: Keyword.put_new(opts, key, value)

  defp child_event_meta(%__MODULE__{} = cantrip, depth, intent, extras) do
    %{
      depth: depth,
      intent: intent,
      child_id: cantrip.id,
      circle: cantrip.circle.type
    }
    |> drop_nil_values()
    |> Map.merge(extras |> Map.new() |> drop_nil_values())
  end

  defp drop_nil_values(map) do
    Map.reject(map, fn {_key, value} -> is_nil(value) end)
  end

  defp normalize_parent_context(%{} = context) do
    Map.new(context, fn {k, v} ->
      key =
        case k do
          atom when is_atom(atom) -> atom
          "parent_cantrip" -> :parent_cantrip
          "depth" -> :depth
          "child_llm" -> :child_llm
          "cancel_on_parent" -> :cancel_on_parent
          "stream_to" -> :stream_to
          "stream_barrier?" -> :stream_barrier?
          "entity_state" -> :entity_state
          "trace_id" -> :trace_id
          "child_llm_ref" -> :child_llm_ref
          "child_spawn_counter" -> :child_spawn_counter
          "remember_child_llm?" -> :remember_child_llm?
          "observation_collector" -> :observation_collector
          "record_parent_observation?" -> :record_parent_observation?
          other -> other
        end

      {key, v}
    end)
  end

  defp child_cancel_on_parent(parent_context) do
    self_pid = self()

    [self_pid | List.wrap(Map.get(parent_context, :cancel_on_parent, []))]
    |> Enum.filter(&is_pid/1)
    |> Enum.uniq()
  end

  defp emit_parent_event(nil, _event), do: :ok
  defp emit_parent_event(%{stream_to: nil}, _event), do: :ok

  defp emit_parent_event(%{stream_to: pid} = state, event) when is_pid(pid) do
    Cantrip.Event.send(pid, state, event)
  end

  defp emit_child_start_telemetry(parent_context, depth) do
    parent = Map.get(parent_context, :entity_state)

    if parent do
      Cantrip.Telemetry.execute(
        [:cantrip, :child, :start],
        %{},
        %{
          entity_id: parent.entity_id,
          trace_id: Map.get(parent_context, :trace_id),
          child_depth: depth
        }
      )
    end
  end

  defp emit_child_stop_telemetry(parent_context, depth, outcome) do
    parent = Map.get(parent_context, :entity_state)

    if parent do
      Cantrip.Telemetry.execute(
        [:cantrip, :child, :stop],
        %{},
        %{
          entity_id: parent.entity_id,
          trace_id: Map.get(parent_context, :trace_id),
          child_depth: depth,
          outcome: outcome
        }
      )
    end
  end

  defp remember_parent_child_llm(parent_context, next_cantrip) do
    child_llm_ref = Map.get(parent_context, :child_llm_ref)

    if Map.get(parent_context, :remember_child_llm?, true) and is_pid(child_llm_ref) do
      Agent.update(child_llm_ref, fn _ -> {next_cantrip.llm_module, next_cantrip.llm_state} end)
    end
  end

  defp refresh_default_child_llm(child_cantrip, parent_context) do
    parent = Map.fetch!(parent_context, :parent_cantrip)
    default = {parent.llm_module, parent.llm_state}

    if {child_cantrip.llm_module, child_cantrip.llm_state} == default do
      {child_module, child_state} =
        Map.get(parent_context, :child_llm) || parent.child_llm || default

      %{child_cantrip | llm_module: child_module, llm_state: child_state}
    else
      child_cantrip
    end
  end

  defp push_parent_cast_observation(
         parent_context,
         gate,
         result,
         is_error,
         child_turns,
         metadata
       ) do
    case parent_context && Map.get(parent_context, :observation_collector) do
      collector when is_pid(collector) ->
        observation =
          %{gate: gate, result: result, is_error: is_error, child_turns: child_turns}
          |> Map.merge(metadata |> Map.new() |> drop_nil_values())

        Agent.update(collector, &(&1 ++ [observation]))

      _ ->
        :ok
    end
  end

  defp child_observation_meta(%__MODULE__{} = cantrip, extras) do
    %{
      child_id: cantrip.id,
      circle: cantrip.circle.type
    }
    |> Map.merge(extras |> Map.new() |> drop_nil_values())
  end

  defp cast_batch_observation_meta(items, payloads) when is_list(items) do
    children =
      items
      |> Enum.with_index()
      |> Enum.flat_map(fn
        {%{cantrip: %__MODULE__{} = cantrip}, index} ->
          [child_observation_meta(cantrip, batch_index: index)]

        {_item, _index} ->
          []
      end)

    failed_batch_index =
      if is_list(payloads) do
        Enum.find_index(payloads, &match?({:error, _, _}, &1))
      end

    base =
      %{children: children, failed_batch_index: failed_batch_index}
      |> drop_nil_values()

    case children do
      [single] -> Map.merge(single, base)
      _ -> base
    end
  end

  defp messages_from_turns(turns, call) do
    prefix =
      if is_nil(call.system_prompt),
        do: [],
        else: [%{role: :system, content: call.system_prompt}]

    Enum.reduce(turns, prefix, fn turn, acc ->
      utterance = turn[:utterance] || %{}
      observations = turn[:observation] || []
      tool_calls = utterance[:tool_calls] || []

      assistant = %{
        role: :assistant,
        content: get_in(turn, [:utterance, :content]),
        tool_calls: tool_calls
      }

      tool_messages =
        Enum.map(observations, fn obs ->
          %{
            role: :tool,
            content: to_string(obs.result),
            gate: obs.gate,
            is_error: obs.is_error,
            tool_call_id: obs[:tool_call_id]
          }
        end)

      # For code medium turns (no tool_calls, feedback is a user message),
      # reconstruct as assistant + user feedback instead of assistant + tool
      if tool_calls == [] and observations != [] do
        feedback =
          observations
          |> Enum.map(fn obs ->
            prefix = if obs.is_error, do: "Error: ", else: ""
            "#{prefix}#{Cantrip.SafeFormat.inspect(obs.result)}"
          end)
          |> Enum.join("\n")

        acc ++ [assistant, %{role: :user, content: feedback}]
      else
        acc ++ [assistant] ++ tool_messages
      end
    end)
  end

  # Insert capability text as a system message after the first system message
  defp inject_capability(messages, text) do
    case Enum.split_while(messages, &(&1.role == :system)) do
      {system_msgs, rest} when system_msgs != [] ->
        system_msgs ++ [%{role: :system, content: text}] ++ rest

      {[], rest} ->
        [%{role: :system, content: text}] ++ rest
    end
  end

  defp validate_llm(nil), do: {:error, "cantrip requires a llm"}
  defp validate_llm({module, _state}) when is_atom(module), do: :ok
  defp validate_llm(_), do: {:error, "invalid llm"}

  defp validate_circle(circle, _identity) do
    cond do
      WardPolicy.require_done_tool?(circle.wards) and not Circle.has_done?(circle) ->
        {:error, "cantrip with require_done must have a done gate"}

      not Circle.has_done?(circle) ->
        {:error, "circle must have a done gate"}

      is_nil(WardPolicy.max_turns(circle.wards)) ->
        {:error, "cantrip must have at least one truncation ward"}

      true ->
        with :ok <- Circle.validate_medium(circle),
             :ok <- validate_medium_runtime(circle) do
          :ok
        end
    end
  end

  defp validate_medium_runtime(%Circle{type: :bash} = circle),
    do: Cantrip.Medium.Bash.validate_circle(circle)

  defp validate_medium_runtime(_circle), do: :ok

  defp validate_retry(retry) do
    opts = retry |> Map.new() |> Keyword.new()

    case NimbleOptions.validate(opts, @retry_schema) do
      {:ok, validated} -> {:ok, Map.new(validated)}
      {:error, %NimbleOptions.ValidationError{message: msg}} -> {:error, msg}
    end
  end

  defp validate_root_attrs(attrs) do
    attrs = attrs |> normalize_input_map() |> prefer_atom_keys()

    case reject_non_atom_option_keys(attrs) do
      :ok ->
        case NimbleOptions.validate(Map.to_list(attrs), @root_schema) do
          {:ok, validated} -> {:ok, Map.new(validated)}
          {:error, %NimbleOptions.ValidationError{message: msg}} -> {:error, msg}
        end

      {:error, msg} ->
        {:error, msg}
    end
  end

  defp validate_folding(folding) do
    opts = folding |> normalize_input_map() |> prefer_atom_keys()

    case NimbleOptions.validate(Map.to_list(opts), @folding_schema) do
      {:ok, validated} -> {:ok, Map.new(validated)}
      {:error, %NimbleOptions.ValidationError{message: msg}} -> {:error, msg}
    end
  end

  @doc false
  def validate_loom_storage_option(nil), do: {:ok, nil}
  def validate_loom_storage_option(:memory), do: {:ok, :memory}

  def validate_loom_storage_option({:jsonl, path} = storage) when is_binary(path),
    do: {:ok, storage}

  def validate_loom_storage_option({:jsonl, _path}) do
    {:error, "expected :memory, {:jsonl, path}, {:mnesia, opts}, or {module, opts}"}
  end

  def validate_loom_storage_option({:mnesia, opts}) do
    with {:ok, opts} <- validate_mnesia_storage_opts(opts) do
      {:ok, {:mnesia, opts}}
    end
  end

  def validate_loom_storage_option({module, _opts} = storage) when is_atom(module) do
    if function_exported?(module, :init, 1) do
      {:ok, storage}
    else
      {:error, "expected storage module to implement init/1"}
    end
  end

  def validate_loom_storage_option(_other) do
    {:error, "expected :memory, {:jsonl, path}, {:mnesia, opts}, or {module, opts}"}
  end

  defp validate_mnesia_storage_opts(opts) when is_map(opts) or is_list(opts) do
    opts = opts |> normalize_input_map() |> prefer_atom_keys()

    schema = [
      table: [type: :atom],
      mnesia: [type: :atom],
      on_corrupt: [type: {:in, [:quarantine]}]
    ]

    case NimbleOptions.validate(Map.to_list(opts), schema) do
      {:ok, validated} -> {:ok, Map.new(validated)}
      {:error, %NimbleOptions.ValidationError{message: msg}} -> {:error, msg}
    end
  end

  defp validate_mnesia_storage_opts(_opts), do: {:error, "expected mnesia opts as map or keyword"}

  defp normalize_input_map(nil), do: %{}
  defp normalize_input_map(attrs) when is_map(attrs), do: attrs
  defp normalize_input_map(attrs) when is_list(attrs), do: Map.new(attrs)
  defp normalize_input_map(other), do: %{invalid: other}

  defp prefer_atom_keys(map) when is_map(map) do
    Map.new(map, fn
      {key, value} when is_atom(key) -> {key, value}
      {key, value} when is_binary(key) -> {known_root_key(key), value}
      pair -> pair
    end)
  end

  defp known_root_key("llm"), do: :llm
  defp known_root_key("identity"), do: :identity
  defp known_root_key("circle"), do: :circle
  defp known_root_key("child_llm"), do: :child_llm
  defp known_root_key("loom_storage"), do: :loom_storage
  defp known_root_key("retry"), do: :retry
  defp known_root_key("folding"), do: :folding
  defp known_root_key("schema_version"), do: :schema_version
  defp known_root_key("parent_context"), do: :parent_context
  defp known_root_key("threshold_tokens"), do: :threshold_tokens
  defp known_root_key("trigger_after_turns"), do: :trigger_after_turns
  defp known_root_key("table"), do: :table
  defp known_root_key("mnesia"), do: :mnesia
  defp known_root_key(key), do: key

  defp reject_non_atom_option_keys(map) do
    unknown = map |> Map.keys() |> Enum.reject(&is_atom/1)

    case unknown do
      [] -> :ok
      keys -> {:error, "unknown options #{inspect(keys)}"}
    end
  end

  defp normalize_child_llm(nil, llm), do: llm

  defp normalize_child_llm({module, state}, _llm) when is_atom(module),
    do: {module, state}

  defp normalize_child_llm(_, llm), do: llm
end
