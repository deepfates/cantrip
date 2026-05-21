defmodule Cantrip do
  @moduledoc """
  M1 surface: cantrip configuration and llm contract wiring.

  The runtime loop is intentionally deferred to M2+. In M1 we only validate:
  - cantrip construction invariants
  - llm response contract invariants
  """

  import Kernel, except: [send: 2]

  alias Cantrip.{Identity, Circle, LLM, EntityServer, Loom, WardPolicy, Gate}
  alias Cantrip.Medium.Registry, as: MediumRegistry

  defstruct id: nil,
            llm_module: nil,
            llm_state: nil,
            child_llm: nil,
            identity: nil,
            circle: nil,
            loom_storage: nil,
            retry: %{max_retries: 0, retryable_status_codes: []},
            folding: %{}

  @type t :: %__MODULE__{
          id: String.t(),
          llm_module: module(),
          llm_state: term(),
          child_llm: {module(), term()} | nil,
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

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) do
    attrs = Map.new(attrs)

    case Map.get(attrs, :parent_context) || Map.get(attrs, "parent_context") ||
           Process.get(:cantrip_parent_context) do
      nil -> new_root(attrs)
      parent_context -> new_child(attrs, parent_context)
    end
  end

  defp new_root(attrs) do
    llm = Map.get(attrs, :llm)
    identity = Identity.new(Map.get(attrs, :identity, %{}))
    circle = Circle.new(Map.get(attrs, :circle, %{}))

    with :ok <- validate_llm(llm),
         :ok <- validate_circle(circle, identity),
         {:ok, retry} <- validate_retry(Map.get(attrs, :retry, %{})) do
      {module, state} = llm

      {:ok,
       %__MODULE__{
         id: "cantrip_" <> Integer.to_string(System.unique_integer([:positive])),
         llm_module: module,
         llm_state: state,
         child_llm: normalize_child_llm(Map.get(attrs, :child_llm), llm),
         identity: identity,
         circle: circle,
         loom_storage: Map.get(attrs, :loom_storage),
         retry: retry,
         folding: Map.get(attrs, :folding, %{})
       }}
    end
  end

  @doc """
  Build the explicit parent context used when a cantrip constructs children.

  This is the core-package representation of the inheritance rules that used
  to live only behind `call_entity`: child LLM selection, ward composition,
  depth limits, inherited gate dependencies, cancellation, streaming, and loom
  grafting context.
  """
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
      entity_state: Map.get(opts, :entity_state)
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
      composed_wards = WardPolicy.compose(parent.circle.wards, child_wards)
      child_gates = resolve_child_gates(parent, requested_gates, depth + 1, max_depth)

      child_circle_attrs =
        circle_attrs
        |> Map.put(:gates, Map.values(child_gates))
        |> Map.put(:wards, composed_wards)

      child_identity = child_identity_attrs(attrs)

      child_attrs = %{
        llm: child_llm,
        child_llm: Map.get(attrs, :child_llm) || Map.get(attrs, "child_llm") || child_llm,
        identity: child_identity,
        circle: child_circle_attrs,
        loom_storage: Map.get(attrs, :loom_storage) || Map.get(attrs, "loom_storage"),
        retry: Map.get(attrs, :retry, parent.retry),
        folding: Map.get(attrs, :folding, parent.folding)
      }

      new_root(child_attrs)
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
    |> Enum.map(&to_string/1)
    |> Enum.uniq()
    |> then(&(&1 ++ ["done"]))
    |> Enum.uniq()
  end

  defp resolve_child_gates(parent, requested_gates, child_depth, max_depth) do
    parent_gate_map = parent.circle.gates
    parent_dependencies = collect_parent_dependencies(parent_gate_map)
    delegation_gates = MapSet.new(["call_entity", "call_entity_batch"])
    strip_delegation = is_integer(max_depth) and child_depth >= max_depth

    requested_gates
    |> Enum.reject(fn name -> strip_delegation and MapSet.member?(delegation_gates, name) end)
    |> Enum.map(fn name ->
      {name, resolve_child_gate(name, parent_gate_map, parent_dependencies)}
    end)
    |> Map.new()
  end

  defp resolve_child_gate(name, parent_gate_map, parent_dependencies) do
    case Map.get(parent_gate_map, name) do
      nil -> build_canonical_gate(name, parent_dependencies)
      gate -> gate
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
  Build a cantrip from environment-based llm configuration.

  Required env:
  - `CANTRIP_MODEL` (or provider-specific: `ANTHROPIC_MODEL`, `GEMINI_MODEL`, `OPENAI_MODEL`)
  Optional env:
  - `CANTRIP_LLM_PROVIDER` (default: `openai_compatible`)
  - `CANTRIP_API_KEY` (or provider-specific: `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`)
  - `CANTRIP_BASE_URL` (or provider-specific variants)
  - `CANTRIP_TIMEOUT_MS` (default: `30000`)

  Provider-specific env vars take precedence over `CANTRIP_*` generics,
  so you can have all three API keys set simultaneously and switch via
  `CANTRIP_LLM_PROVIDER`.
  """
  @spec new_from_env(keyword() | map()) :: {:ok, t()} | {:error, String.t()}
  def new_from_env(attrs \\ %{}) do
    attrs = Map.new(attrs)

    with {:ok, llm} <- llm_from_env() do
      new(Map.put(attrs, :llm, llm))
    end
  end

  @req_llm_prefixes %{
    "openai_compatible" => "openai",
    "anthropic" => "anthropic",
    "gemini" => "google"
  }

  @spec llm_from_env() :: {:ok, {module(), map()}} | {:error, String.t()}
  def llm_from_env do
    provider = System.get_env("CANTRIP_LLM_PROVIDER", "openai_compatible")

    # Prefer ReqLLM when available for all providers
    if Code.ensure_loaded?(Cantrip.LLMs.ReqLLM) and Map.has_key?(@req_llm_prefixes, provider) do
      llm_from_env_req_llm(provider)
    else
      llm_from_env_legacy(provider)
    end
  end

  defp llm_from_env_req_llm(provider) do
    prefix = Map.fetch!(@req_llm_prefixes, provider)
    model = model_for_provider(provider)

    if model in [nil, ""] do
      {:error, missing_model_error(provider)}
    else
      base_url = base_url_for_provider(provider)
      api_key = api_key_for_provider(provider)

      state = %{
        model: "#{prefix}:#{model}",
        stream: System.get_env("CANTRIP_STREAM") == "true",
        timeout_ms: parse_int(System.get_env("CANTRIP_TIMEOUT_MS"), 60_000),
        temperature: parse_float(System.get_env("CANTRIP_TEMPERATURE")),
        max_tokens: parse_int(System.get_env("CANTRIP_MAX_TOKENS"), nil)
      }

      state = if base_url, do: Map.put(state, :base_url, base_url), else: state
      state = if api_key, do: Map.put(state, :api_key, api_key), else: state

      {:ok, {Cantrip.LLMs.ReqLLM, state}}
    end
  end

  defp base_url_for_provider("openai_compatible"),
    do: env_first(["OPENAI_BASE_URL", "CANTRIP_BASE_URL"])

  defp base_url_for_provider(_), do: nil

  defp api_key_for_provider("openai_compatible"),
    do: env_first(["OPENAI_API_KEY", "CANTRIP_API_KEY"])

  defp api_key_for_provider("anthropic"),
    do: env_first(["ANTHROPIC_API_KEY", "CANTRIP_API_KEY"])

  defp api_key_for_provider("gemini"),
    do: env_first(["GEMINI_API_KEY", "CANTRIP_API_KEY"])

  defp api_key_for_provider(_), do: nil

  defp model_for_provider("openai_compatible"), do: env_first(["OPENAI_MODEL", "CANTRIP_MODEL"])
  defp model_for_provider("anthropic"), do: env_first(["ANTHROPIC_MODEL", "CANTRIP_MODEL"])
  defp model_for_provider("gemini"), do: env_first(["GEMINI_MODEL", "CANTRIP_MODEL"])
  defp model_for_provider(_), do: env_first(["CANTRIP_MODEL"])

  defp missing_model_error("openai_compatible"), do: "missing CANTRIP_MODEL or OPENAI_MODEL"
  defp missing_model_error("anthropic"), do: "missing CANTRIP_MODEL or ANTHROPIC_MODEL"
  defp missing_model_error("gemini"), do: "missing CANTRIP_MODEL or GEMINI_MODEL"
  defp missing_model_error(_), do: "missing CANTRIP_MODEL"

  defp llm_from_env_legacy(provider) do
    case provider do
      "openai_compatible" ->
        model = env_first(["OPENAI_MODEL", "CANTRIP_MODEL"])

        if model in [nil, ""] do
          {:error, "missing CANTRIP_MODEL or OPENAI_MODEL"}
        else
          {:ok,
           {Cantrip.LLMs.OpenAICompatible,
            %{
              model: model,
              api_key: env_first(["OPENAI_API_KEY", "CANTRIP_API_KEY"]),
              base_url:
                env_first(["OPENAI_BASE_URL", "CANTRIP_BASE_URL"]) || "https://api.openai.com/v1",
              timeout_ms: parse_int(System.get_env("CANTRIP_TIMEOUT_MS"), 120_000)
            }}}
        end

      "anthropic" ->
        model = env_first(["ANTHROPIC_MODEL", "CANTRIP_MODEL"])

        if model in [nil, ""] do
          {:error, "missing CANTRIP_MODEL or ANTHROPIC_MODEL"}
        else
          {:ok,
           {Cantrip.LLMs.Anthropic,
            %{
              model: model,
              api_key: env_first(["ANTHROPIC_API_KEY", "CANTRIP_API_KEY"]),
              base_url: System.get_env("ANTHROPIC_BASE_URL") || "https://api.anthropic.com",
              timeout_ms: parse_int(System.get_env("CANTRIP_TIMEOUT_MS"), 120_000),
              max_tokens: parse_int(System.get_env("CANTRIP_MAX_TOKENS"), 4096)
            }}}
        end

      "gemini" ->
        model = env_first(["GEMINI_MODEL", "CANTRIP_MODEL"])

        if model in [nil, ""] do
          {:error, "missing CANTRIP_MODEL or GEMINI_MODEL"}
        else
          {:ok,
           {Cantrip.LLMs.Gemini,
            %{
              model: model,
              api_key: env_first(["GEMINI_API_KEY", "CANTRIP_API_KEY"]),
              base_url:
                System.get_env("GEMINI_BASE_URL") || "https://generativelanguage.googleapis.com",
              timeout_ms: parse_int(System.get_env("CANTRIP_TIMEOUT_MS"), 120_000)
            }}}
        end

      _ ->
        {:error, "unsupported llm provider: #{provider}"}
    end
  end

  defp env_first(keys) do
    Enum.find_value(keys, fn key ->
      case System.get_env(key) do
        nil -> nil
        "" -> nil
        val -> val
      end
    end)
  end

  @doc """
  Invoke the configured llm once and validate/normalize the response contract.
  Returns updated cantrip with advanced llm state.
  """
  @spec llm_query(t(), map()) ::
          {:ok, map(), t()} | {:error, term(), t()}
  def llm_query(%__MODULE__{} = cantrip, request) do
    case LLM.request(cantrip.llm_module, cantrip.llm_state, request) do
      {:ok, response, next_state} ->
        {:ok, response, %{cantrip | llm_state: next_state}}

      {:error, reason, next_state} ->
        {:error, reason, %{cantrip | llm_state: next_state}}
    end
  end

  def annotate_reward(%__MODULE__{} = cantrip, loom, turn_index, reward) do
    case Loom.annotate_reward(loom, turn_index, reward) do
      {:ok, loom} -> {:ok, loom, cantrip}
      {:error, reason} -> {:error, reason, cantrip}
    end
  end

  def extract_thread(%__MODULE__{}, loom), do: Loom.extract_thread(loom)

  @doc """
  ENTITY-5: Create a persistent entity without running any intent.
  Returns `{:ok, pid}`. Use `send/2` to run intents.
  """
  @spec summon(t()) :: {:ok, pid()} | {:error, term()}
  def summon(%__MODULE__{} = cantrip) do
    spec = {EntityServer, cantrip: cantrip, lazy: true}
    DynamicSupervisor.start_child(Cantrip.EntitySupervisor, spec)
  end

  @doc "Summon with additional EntityServer opts (e.g. stream_to: pid)."
  def summon_with(%__MODULE__{} = cantrip, opts) when is_list(opts) do
    spec = {EntityServer, [cantrip: cantrip, lazy: true] ++ opts}
    DynamicSupervisor.start_child(Cantrip.EntitySupervisor, spec)
  end

  @doc """
  ENTITY-5: Create a persistent entity and immediately run the first intent.
  Convenience wrapper: equivalent to `summon/1` followed by `send/2`.
  Accepts optional keyword opts (e.g. `stream_to: pid`) passed to EntityServer.
  """
  @spec summon(t(), String.t(), keyword()) ::
          {:ok, pid(), term(), t(), Loom.t(), map()} | {:error, term(), t()}
  def summon(%__MODULE__{} = cantrip, intent, opts \\ []) when is_binary(intent) do
    spec = {EntityServer, [cantrip: cantrip, lazy: true] ++ opts}

    with {:ok, pid} <- DynamicSupervisor.start_child(Cantrip.EntitySupervisor, spec) do
      case send(pid, intent) do
        {:ok, result, next_cantrip, loom, meta} ->
          {:ok, pid, result, next_cantrip, loom, meta}

        {:error, reason} ->
          {:error, reason, cantrip}
      end
    end
  end

  @doc """
  ENTITY-5: Send a new intent to a persistent entity, running another loop episode.
  State (loom, code_state, messages) accumulates across all casts.
  """
  @spec send(pid(), String.t()) ::
          {:ok, term(), t(), Loom.t(), map()} | {:error, term()}
  def send(pid, intent) when is_pid(pid) and is_binary(intent) do
    EntityServer.send_intent(pid, intent)
  end

  @doc "Send with opts (e.g. stream_to: pid for per-call event delivery)."
  def send(pid, intent, opts) when is_pid(pid) and is_binary(intent) and is_list(opts) do
    EntityServer.send_intent(pid, intent, opts)
  end

  @doc """
  M2 cast entrypoint: executes one loop episode in an entity process.
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
          |> Task.async_stream(
            fn %{cantrip: cantrip, intent: intent} ->
              cast(cantrip, intent,
                parent_context: parent_context,
                record_parent_observation?: false
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

          push_parent_cast_observation("cast_batch", inspect(reason), true, [])
          {:error, reason}
        else
          values = Enum.map(payloads, fn {:ok, value, _next, _loom, _meta} -> value end)
          next_cantrips = Enum.map(payloads, fn {:ok, _value, next, _loom, _meta} -> next end)
          looms = Enum.map(payloads, fn {:ok, _value, _next, loom, _meta} -> loom end)
          child_turns = Enum.flat_map(looms, & &1.turns)
          push_parent_cast_observation("cast_batch", values, false, child_turns)
          {:ok, values, next_cantrips, looms, %{count: length(values)}}
        end

      {:error, reason} ->
        push_parent_cast_observation("cast_batch", inspect(reason), true, [])
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
  Cast with streaming events. Returns `{stream, task}` where:
  - `stream` is an `Enumerable` of `{:cantrip_event, event}` tuples
  - `task` is a `Task` that resolves to the final `{:ok, result, cantrip, loom, meta}` or error

  Events follow the spec §7.5 hierarchy: `:step_start`, `:message_start`,
  `:text`, `:tool_call`, `:tool_result`, `:usage`, `:message_complete`,
  `:step_complete`, `:final_response`.
  """
  @spec cast_stream(t(), String.t()) :: {Enumerable.t(), Task.t()}
  def cast_stream(%__MODULE__{} = cantrip, intent) when is_binary(intent) do
    caller = self()

    task =
      Task.async(fn ->
        run_cast(cantrip, intent, stream_to: caller)
      end)

    stream =
      Stream.resource(
        fn -> :running end,
        fn
          :done ->
            {:halt, :done}

          :running ->
            receive do
              {:cantrip_event, event} ->
                {[event], :running}

              {ref, result} when is_reference(ref) ->
                # Task completed — drain any remaining events, then stop
                Process.demonitor(ref, [:flush])
                remaining = drain_events()
                {remaining ++ [{:done, result}], :done}

              {:DOWN, _ref, :process, _pid, reason} ->
                {[{:done, {:error, reason}}], :done}
            end
        end,
        fn _ -> :ok end
      )

    {stream, task}
  end

  defp drain_events do
    receive do
      {:cantrip_event, event} -> [event | drain_events()]
    after
      0 -> []
    end
  end

  @spec fork(t(), Loom.t(), non_neg_integer(), map()) ::
          {:ok, term(), t(), Loom.t(), map()} | {:error, term(), t()}
  def fork(%__MODULE__{} = cantrip, %Loom{} = loom, from_turn, opts) do
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
  defp coerce_intent(intent), do: inspect(intent, pretty: true, limit: :infinity)

  defp run_cast_with_parent_context(%__MODULE__{} = cantrip, intent, opts) do
    case Keyword.get(opts, :parent_context) || Process.get(:cantrip_parent_context) do
      nil ->
        run_cast(cantrip, intent, opts)

      parent_context ->
        opts = Keyword.delete(opts, :parent_context)
        run_child_cast(cantrip, intent, opts, parent_context)
    end
  end

  defp run_child_cast(%__MODULE__{} = cantrip, intent, opts, parent_context) do
    parent_context = normalize_parent_context(parent_context)
    entity_state = Map.get(parent_context, :entity_state)
    depth = Map.get(parent_context, :depth, 0) + 1
    record_observation? = Keyword.get(opts, :record_parent_observation?, true)
    parent_gate = Keyword.get(opts, :parent_gate, "cast")
    opts = Keyword.drop(opts, [:record_parent_observation?, :parent_gate])

    cantrip = refresh_default_child_llm(cantrip, parent_context)

    cast_opts =
      opts
      |> Keyword.put_new(:depth, depth)
      |> Keyword.put_new(:cancel_on_parent, child_cancel_on_parent(parent_context))
      |> maybe_put_new(:stream_to, Map.get(parent_context, :stream_to))
      |> maybe_put_new(:stream_barrier?, Map.get(parent_context, :stream_barrier?))

    emit_parent_event(entity_state, {:child_start, %{depth: depth, intent: intent}})

    case run_cast(cantrip, intent, cast_opts) do
      {:ok, value, next_cantrip, child_loom, _meta} = ok ->
        remember_parent_child_llm(parent_context, next_cantrip)
        emit_parent_event(entity_state, {:child_end, %{depth: depth, result: value}})

        if record_observation?,
          do: push_parent_cast_observation(parent_gate, value, false, child_loom.turns)

        ok

      {:error, reason, next_cantrip} = error ->
        remember_parent_child_llm(parent_context, next_cantrip)
        emit_parent_event(entity_state, {:child_end, %{depth: depth, error: inspect(reason)}})

        if record_observation?,
          do: push_parent_cast_observation(parent_gate, inspect(reason), true, [])

        error
    end
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

  defp maybe_put_new(opts, _key, nil), do: opts
  defp maybe_put_new(opts, key, value), do: Keyword.put_new(opts, key, value)

  defp normalize_parent_context(%{} = context) do
    Map.new(context, fn {k, v} ->
      key = if is_atom(k), do: k, else: String.to_atom(to_string(k))
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

  defp remember_parent_child_llm(parent_context, next_cantrip) do
    if Map.get(parent_context, :remember_child_llm?, true) do
      Process.put(:cantrip_child_llm, {next_cantrip.llm_module, next_cantrip.llm_state})
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

  defp push_parent_cast_observation(gate, result, is_error, child_turns) do
    case Process.get(:cantrip_code_observations) do
      observations when is_list(observations) ->
        observation = %{gate: gate, result: result, is_error: is_error, child_turns: child_turns}
        Process.put(:cantrip_code_observations, observations ++ [observation])

      _ ->
        :ok
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
            "#{prefix}#{inspect(obs.result)}"
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
        Circle.validate_medium(circle)
    end
  end

  defp validate_retry(retry) do
    opts = retry |> Map.new() |> Keyword.new()

    case NimbleOptions.validate(opts, @retry_schema) do
      {:ok, validated} -> {:ok, Map.new(validated)}
      {:error, %NimbleOptions.ValidationError{message: msg}} -> {:error, msg}
    end
  end

  defp normalize_child_llm(nil, llm), do: llm

  defp normalize_child_llm({module, state}, _llm) when is_atom(module),
    do: {module, state}

  defp normalize_child_llm(_, llm), do: llm

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end

  defp parse_float(nil), do: nil

  defp parse_float(value) when is_binary(value) do
    case Float.parse(value) do
      {f, _} -> f
      :error -> nil
    end
  end
end
