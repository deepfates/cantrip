defmodule Cantrip do
  @moduledoc """
  M1 surface: cantrip configuration and crystal contract wiring.

  The runtime loop is intentionally deferred to M2+. In M1 we only validate:
  - cantrip construction invariants
  - crystal response contract invariants
  """

  alias Cantrip.{Call, Circle, Crystal, EntityServer, Loom}

  defstruct id: nil,
            crystal_module: nil,
            crystal_state: nil,
            child_crystal: nil,
            call: nil,
            circle: nil,
            loom_storage: nil,
            retry: %{max_retries: 0, retryable_status_codes: []},
            folding: %{}

  @type t :: %__MODULE__{
          id: String.t(),
          crystal_module: module(),
          crystal_state: term(),
          child_crystal: {module(), term()} | nil,
          call: Call.t(),
          circle: Circle.t(),
          loom_storage: term(),
          retry: map(),
          folding: map()
        }

  @spec new(keyword() | map()) :: {:ok, t()} | {:error, String.t()}
  def new(attrs) do
    attrs = Map.new(attrs)
    crystal = Map.get(attrs, :crystal)
    call = Call.new(Map.get(attrs, :call, %{}))
    circle = Circle.new(Map.get(attrs, :circle, %{}))

    with :ok <- validate_crystal(crystal),
         :ok <- validate_circle(circle, call) do
      {module, state} = crystal

      {:ok,
       %__MODULE__{
         id: "cantrip_" <> Integer.to_string(System.unique_integer([:positive])),
         crystal_module: module,
         crystal_state: state,
         child_crystal: normalize_child_crystal(Map.get(attrs, :child_crystal), crystal),
         call: call,
         circle: circle,
         loom_storage: normalize_loom_storage(Map.get(attrs, :loom_storage)),
         retry: normalize_retry(Map.get(attrs, :retry, %{})),
         folding: Map.get(attrs, :folding, %{})
       }}
    end
  end

  @doc """
  Build a cantrip from environment-based crystal configuration.

  Required env:
  - `CANTRIP_MODEL` (or provider-specific: `ANTHROPIC_MODEL`, `GEMINI_MODEL`, `OPENAI_MODEL`)
  Optional env:
  - `CANTRIP_CRYSTAL_PROVIDER` (default: `openai_compatible`)
  - `CANTRIP_API_KEY` (or provider-specific: `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `OPENAI_API_KEY`)
  - `CANTRIP_BASE_URL` (or provider-specific variants)
  - `CANTRIP_TIMEOUT_MS` (default: `30000`)

  Provider-specific env vars take precedence over `CANTRIP_*` generics,
  so you can have all three API keys set simultaneously and switch via
  `CANTRIP_CRYSTAL_PROVIDER`.
  """
  @spec new_from_env(keyword() | map()) :: {:ok, t()} | {:error, String.t()}
  def new_from_env(attrs \\ %{}) do
    attrs = Map.new(attrs)

    with {:ok, crystal} <- crystal_from_env() do
      new(Map.put(attrs, :crystal, crystal))
    end
  end

  @spec crystal_from_env() :: {:ok, {module(), map()}} | {:error, String.t()}
  def crystal_from_env do
    provider = System.get_env("CANTRIP_CRYSTAL_PROVIDER", "openai_compatible")

    case provider do
      "openai_compatible" ->
        model = env_first(["OPENAI_MODEL", "CANTRIP_MODEL"])

        if model in [nil, ""] do
          {:error, "missing CANTRIP_MODEL or OPENAI_MODEL"}
        else
          {:ok,
           {Cantrip.Crystals.OpenAICompatible,
            %{
              model: model,
              api_key: env_first(["OPENAI_API_KEY", "CANTRIP_API_KEY"]),
              base_url:
                env_first(["OPENAI_BASE_URL", "CANTRIP_BASE_URL"]) || "https://api.openai.com/v1",
              timeout_ms: parse_int(System.get_env("CANTRIP_TIMEOUT_MS"), 30_000)
            }}}
        end

      "anthropic" ->
        model = env_first(["ANTHROPIC_MODEL", "CANTRIP_MODEL"])

        if model in [nil, ""] do
          {:error, "missing CANTRIP_MODEL or ANTHROPIC_MODEL"}
        else
          {:ok,
           {Cantrip.Crystals.Anthropic,
            %{
              model: model,
              api_key: env_first(["ANTHROPIC_API_KEY", "CANTRIP_API_KEY"]),
              base_url:
                System.get_env("ANTHROPIC_BASE_URL") || "https://api.anthropic.com",
              timeout_ms: parse_int(System.get_env("CANTRIP_TIMEOUT_MS"), 30_000),
              max_tokens: parse_int(System.get_env("CANTRIP_MAX_TOKENS"), 4096)
            }}}
        end

      "gemini" ->
        model = env_first(["GEMINI_MODEL", "CANTRIP_MODEL"])

        if model in [nil, ""] do
          {:error, "missing CANTRIP_MODEL or GEMINI_MODEL"}
        else
          {:ok,
           {Cantrip.Crystals.Gemini,
            %{
              model: model,
              api_key: env_first(["GEMINI_API_KEY", "CANTRIP_API_KEY"]),
              base_url:
                System.get_env("GEMINI_BASE_URL") || "https://generativelanguage.googleapis.com",
              timeout_ms: parse_int(System.get_env("CANTRIP_TIMEOUT_MS"), 30_000)
            }}}
        end

      _ ->
        {:error, "unsupported crystal provider: #{provider}"}
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
  Invoke the configured crystal once and validate/normalize the response contract.
  Returns updated cantrip with advanced crystal state.
  """
  @spec crystal_query(t(), map()) ::
          {:ok, map(), t()} | {:error, term(), t()}
  def crystal_query(%__MODULE__{} = cantrip, request) do
    case Crystal.invoke(cantrip.crystal_module, cantrip.crystal_state, request) do
      {:ok, response, next_state} ->
        {:ok, response, %{cantrip | crystal_state: next_state}}

      {:error, reason, next_state} ->
        {:error, reason, %{cantrip | crystal_state: next_state}}
    end
  end

  @doc """
  M1 exposes the immutability contract as an explicit error path.
  """
  def mutate_call(_cantrip, _attrs), do: {:error, "call is immutable"}

  def delete_turn(_cantrip, loom, turn_index), do: Loom.delete_turn(loom, turn_index)

  def annotate_reward(%__MODULE__{} = cantrip, loom, turn_index, reward) do
    case Loom.annotate_reward(loom, turn_index, reward) do
      {:ok, loom} -> {:ok, loom, cantrip}
      {:error, reason} -> {:error, reason, cantrip}
    end
  end

  def extract_thread(%__MODULE__{}, loom), do: Loom.extract_thread(loom)

  @doc """
  ENTITY-5: Start a persistent entity that can receive multiple intents.
  Returns `{:ok, pid, result, cantrip, loom, meta}` after the first cast completes.
  The entity remains alive — send additional intents with `send_intent/2`.
  """
  @spec invoke(t(), String.t()) ::
          {:ok, pid(), term(), t(), Loom.t(), map()} | {:error, term(), t()}
  def invoke(%__MODULE__{} = cantrip, intent) when is_binary(intent) do
    spec = {EntityServer, cantrip: cantrip, intent: intent}

    with {:ok, pid} <- DynamicSupervisor.start_child(Cantrip.EntitySupervisor, spec) do
      case EntityServer.run_persistent(pid) do
        {:ok, result, next_cantrip, loom, meta} ->
          {:ok, pid, result, next_cantrip, loom, meta}

        {:error, reason, next_cantrip} ->
          {:error, reason, next_cantrip}
      end
    end
  end

  @doc """
  ENTITY-5: Send a new intent to a persistent entity, running another loop episode.
  State (loom, code_state, messages) accumulates across all casts.
  """
  @spec send_intent(pid(), String.t()) ::
          {:ok, term(), t(), Loom.t(), map()} | {:error, term()}
  def send_intent(pid, intent) when is_pid(pid) and is_binary(intent) do
    EntityServer.cast_intent(pid, intent)
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

  @spec cast(t(), String.t() | nil, keyword()) ::
          {:ok, term(), t(), Cantrip.Loom.t(), map()} | {:error, String.t(), t()}
  def cast(cantrip, nil, _opts), do: {:error, "intent is required", cantrip}

  def cast(%__MODULE__{} = cantrip, intent, opts) when is_binary(intent) and is_list(opts) do
    run_cast(cantrip, intent, opts)
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
    crystal = Map.get(opts, :crystal, {cantrip.crystal_module, cantrip.crystal_state})

    prefix_turns = Enum.take(loom.turns, from_turn)
    prefix_messages = messages_from_turns(prefix_turns, cantrip.call)
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
        crystal: crystal,
        call: Map.from_struct(cantrip.call),
        circle: %{
          gates: Map.values(cantrip.circle.gates),
          wards: cantrip.circle.wards,
          type: cantrip.circle.type
        },
        loom_storage: cantrip.loom_storage,
        child_crystal: cantrip.child_crystal,
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

  defp run_cast(%__MODULE__{} = cantrip, intent, extra_opts) do
    spec = {EntityServer, cantrip: cantrip, intent: intent}
    spec = put_elem(spec, 1, Keyword.merge(elem(spec, 1), extra_opts))

    with {:ok, pid} <- DynamicSupervisor.start_child(Cantrip.EntitySupervisor, spec) do
      case safe_run_entity(pid) do
        {:ok, result, next_cantrip, loom, meta} ->
          {:ok, result, next_cantrip, loom, meta}

        {:error, reason} ->
          {:error, reason, cantrip}
      end
    else
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

  defp messages_from_turns(turns, call) do
    prefix =
      if is_nil(call.system_prompt),
        do: [],
        else: [%{role: :system, content: call.system_prompt}]

    Enum.reduce(turns, prefix, fn turn, acc ->
      assistant = %{role: :assistant, content: get_in(turn, [:utterance, :content])}
      tools = Enum.map(turn.observation || [], &%{role: :tool, content: to_string(&1.result)})
      acc ++ [assistant] ++ tools
    end)
  end

  defp validate_crystal(nil), do: {:error, "cantrip requires a crystal"}
  defp validate_crystal({module, _state}) when is_atom(module), do: :ok
  defp validate_crystal(_), do: {:error, "invalid crystal"}

  defp validate_circle(circle, call) do
    cond do
      call.require_done_tool and not Circle.has_done?(circle) ->
        {:error, "cantrip with require_done must have a done gate"}

      not Circle.has_done?(circle) ->
        {:error, "circle must have a done gate"}

      is_nil(Circle.max_turns(circle)) ->
        {:error, "cantrip must have at least one truncation ward"}

      true ->
        :ok
    end
  end

  defp normalize_retry(retry) do
    retry = Map.new(retry)

    %{
      max_retries: Map.get(retry, :max_retries, 0),
      retryable_status_codes: Map.get(retry, :retryable_status_codes, []),
      backoff_base_ms: Map.get(retry, :backoff_base_ms, 1_000),
      backoff_max_ms: Map.get(retry, :backoff_max_ms, 30_000)
    }
  end

  defp normalize_child_crystal(nil, crystal), do: crystal

  defp normalize_child_crystal({module, state}, _crystal) when is_atom(module),
    do: {module, state}

  defp normalize_child_crystal(_, crystal), do: crystal

  defp normalize_loom_storage(nil), do: nil
  defp normalize_loom_storage(storage), do: storage

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end
end
