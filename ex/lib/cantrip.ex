defmodule Cantrip do
  @moduledoc """
  M1 surface: cantrip configuration and crystal contract wiring.

  The runtime loop is intentionally deferred to M2+. In M1 we only validate:
  - cantrip construction invariants
  - crystal response contract invariants
  """

  alias Cantrip.{Call, Circle, Crystal, EntityServer, Loom}

  defstruct crystal_module: nil,
            crystal_state: nil,
            child_crystal: nil,
            call: nil,
            circle: nil,
            retry: %{max_retries: 0, retryable_status_codes: []},
            folding: %{}

  @type t :: %__MODULE__{
          crystal_module: module(),
          crystal_state: term(),
          child_crystal: {module(), term()} | nil,
          call: Call.t(),
          circle: Circle.t(),
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
         crystal_module: module,
         crystal_state: state,
         child_crystal: normalize_child_crystal(Map.get(attrs, :child_crystal), crystal),
         call: call,
         circle: circle,
         retry: normalize_retry(Map.get(attrs, :retry, %{})),
         folding: Map.get(attrs, :folding, %{})
       }}
    end
  end

  @doc """
  Build a cantrip from environment-based crystal configuration.

  Required env:
  - `CANTRIP_MODEL`
  Optional env:
  - `CANTRIP_CRYSTAL_PROVIDER` (default: `openai_compatible`)
  - `CANTRIP_API_KEY`
  - `CANTRIP_BASE_URL` (default: `https://api.openai.com/v1`)
  - `CANTRIP_TIMEOUT_MS` (default: `30000`)
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
    model = System.get_env("CANTRIP_MODEL")

    cond do
      model in [nil, ""] ->
        {:error, "missing CANTRIP_MODEL"}

      provider == "openai_compatible" ->
        {:ok,
         {Cantrip.Crystals.OpenAICompatible,
          %{
            model: model,
            api_key: System.get_env("CANTRIP_API_KEY"),
            base_url: System.get_env("CANTRIP_BASE_URL", "https://api.openai.com/v1"),
            timeout_ms: parse_int(System.get_env("CANTRIP_TIMEOUT_MS"), 30_000)
          }}}

      true ->
        {:error, "unsupported crystal provider: #{provider}"}
    end
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

  @spec fork(t(), Loom.t(), non_neg_integer(), map()) ::
          {:ok, term(), t(), Loom.t(), map()} | {:error, term(), t()}
  def fork(%__MODULE__{} = cantrip, %Loom{} = loom, from_turn, opts) do
    opts = Map.new(opts)
    intent = Map.fetch!(opts, :intent)
    crystal = Map.get(opts, :crystal, {cantrip.crystal_module, cantrip.crystal_state})

    prefix_turns = Enum.take(loom.turns, from_turn)
    prefix_messages = messages_from_turns(prefix_turns, cantrip.call)
    fork_messages = prefix_messages ++ [%{role: :user, content: intent}]
    fork_loom = %Loom{call: loom.call, turns: prefix_turns}

    {:ok, forked_cantrip} =
      new(
        crystal: crystal,
        call: Map.from_struct(cantrip.call),
        circle: %{
          gates: Map.values(cantrip.circle.gates),
          wards: cantrip.circle.wards,
          type: cantrip.circle.type
        },
        child_crystal: cantrip.child_crystal,
        retry: cantrip.retry,
        folding: cantrip.folding
      )

    run_cast(forked_cantrip, intent,
      messages: fork_messages,
      loom: fork_loom,
      turns: length(prefix_turns)
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
      retryable_status_codes: Map.get(retry, :retryable_status_codes, [])
    }
  end

  defp normalize_child_crystal(nil, crystal), do: crystal

  defp normalize_child_crystal({module, state}, _crystal) when is_atom(module),
    do: {module, state}

  defp normalize_child_crystal(_, crystal), do: crystal

  defp parse_int(nil, default), do: default

  defp parse_int(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} -> n
      :error -> default
    end
  end
end
