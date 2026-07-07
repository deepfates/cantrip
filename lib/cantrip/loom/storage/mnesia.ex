defmodule Cantrip.Loom.Storage.Mnesia do
  @moduledoc false

  @behaviour Cantrip.Loom.Storage
  import Cantrip.LLMs.Helpers, only: [normalize_opts: 1]

  @version 1

  @impl true
  def init(opts) do
    if not available?() do
      {:error, "mnesia storage not available"}
    else
      opts = normalize_opts(opts)
      table = Map.get(opts, :table, default_table())
      mnesia = Map.get(opts, :mnesia, :mnesia)

      case with_schema_lock(fn ->
             with :ok <- preflight_store(opts, mnesia),
                  :ok <- ensure_mnesia_started(mnesia),
                  :ok <- ensure_table(table, mnesia) do
               {:ok, %{table: table, mnesia: mnesia}}
             end
           end) do
        {:ok, state} -> {:ok, state}
        {:error, reason} -> {:error, Cantrip.SafeFormat.inspect(reason)}
      end
    end
  end

  @impl true
  def append_turn(%{table: table} = state, turn) do
    mnesia = Map.get(state, :mnesia, :mnesia)
    key = System.unique_integer([:positive, :monotonic])
    event = storage_event(%{type: :turn, turn: turn})

    case durable_transaction(mnesia, fn -> call(mnesia, :write, [{table, key, event}]) end) do
      {:atomic, :ok} -> {:ok, state}
      {:aborted, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  @impl true
  def annotate_reward(%{table: table} = state, index, reward) do
    mnesia = Map.get(state, :mnesia, :mnesia)
    key = System.unique_integer([:positive, :monotonic])
    event = storage_event(%{type: :reward, index: index, reward: reward})

    case durable_transaction(mnesia, fn -> call(mnesia, :write, [{table, key, event}]) end) do
      {:atomic, :ok} -> {:ok, state}
      {:aborted, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  @impl true
  def append_event(%{table: table} = state, event) do
    mnesia = Map.get(state, :mnesia, :mnesia)
    key = System.unique_integer([:positive, :monotonic])
    event = storage_event(event)

    case durable_transaction(mnesia, fn -> call(mnesia, :write, [{table, key, event}]) end) do
      {:atomic, :ok} -> {:ok, state}
      {:aborted, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  @impl true
  def load(%{table: table} = state) do
    case read_events(table, Map.get(state, :mnesia, :mnesia)) do
      {:ok, events} ->
        {evts, trns} = classify_native(events)
        {:ok, %{events: evts, turns: trns}}

      {:error, _reason} = err ->
        err
    end
  end

  @impl true
  def flush(%{mnesia: mnesia} = state) do
    case call(mnesia, :sync_log, []) do
      :ok -> {:ok, state}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  rescue
    e -> {:error, Cantrip.SafeFormat.exception(e)}
  catch
    :exit, reason -> {:error, {:exit, reason}}
  end

  @impl true
  def close(_state), do: :ok

  defp classify_native(events) do
    {evts, trns} =
      Enum.reduce(events, {[], []}, fn stored_event, {evts_acc, trns_acc} ->
        event = upcast!(stored_event)
        type = Map.get(event, :type) || Map.get(event, "type")

        cond do
          type in [:turn, "turn"] ->
            turn =
              event
              |> Map.get(:turn, Map.get(event, "turn"))
              |> Cantrip.Loom.CodeStateDelta.expand_turn(List.first(trns_acc))

            {[%{type: :turn, turn: turn} | evts_acc], [turn | trns_acc]}

          type in [:reward, "reward"] ->
            reward_event = %{
              type: :reward,
              index: Map.get(event, :index) || Map.get(event, "index"),
              reward: Map.get(event, :reward) || Map.get(event, "reward")
            }

            {[reward_event | evts_acc], trns_acc}

          true ->
            {[event | evts_acc], trns_acc}
        end
      end)

    {Enum.reverse(evts), Enum.reverse(trns)}
  end

  defp read_events(table, mnesia) when is_atom(table) do
    case call(mnesia, :transaction, [fn -> call(mnesia, :match_object, [{table, :_, :_}]) end]) do
      {:atomic, rows} ->
        events =
          rows
          |> Enum.sort_by(fn {_table, key, _event} -> key end)
          |> Enum.map(fn {_table, _key, event} -> event end)

        {:ok, events}

      {:aborted, reason} ->
        {:error, reason}

      other ->
        {:error, other}
    end
  end

  defp durable_transaction(mnesia, fun) when is_function(fun, 0) do
    if function_exported?(mnesia, :sync_transaction, 1) do
      call(mnesia, :sync_transaction, [fun])
    else
      call(mnesia, :transaction, [fun])
    end
  end

  defp ensure_mnesia_started(mnesia) do
    case call(mnesia, :system_info, [:is_running]) do
      :yes ->
        :ok

      _ ->
        with :ok <- ensure_schema(mnesia) do
          case call(mnesia, :start, []) do
            :ok -> :ok
            {:error, {:already_started, :mnesia}} -> :ok
            {:error, reason} -> {:error, reason}
            other -> {:error, other}
          end
        end
    end
  end

  defp preflight_store(opts, mnesia) do
    case call(mnesia, :system_info, [:is_running]) do
      :yes ->
        :ok

      _ ->
        dir = mnesia_dir()

        case corrupt_log_files(dir) do
          [] ->
            :ok

          corrupt ->
            maybe_quarantine_corrupt_store(dir, corrupt, opts)
        end
    end
  rescue
    _ -> :ok
  catch
    :exit, _ -> :ok
  end

  defp mnesia_dir do
    case Application.get_env(:mnesia, :dir) do
      nil -> ~c"Mnesia.#{node()}"
      dir -> dir
    end
    |> to_string()
  end

  defp corrupt_log_files(dir) do
    ["LATEST.LOG", "PREVIOUS.LOG"]
    |> Enum.map(&Path.join(dir, &1))
    |> Enum.filter(&File.regular?/1)
    |> Enum.flat_map(fn path ->
      case probe_log(path) do
        :ok -> []
        {:error, reason} -> [{path, reason}]
      end
    end)
  end

  defp probe_log(path) do
    name = :"#{__MODULE__}.probe.#{System.unique_integer([:positive])}"

    case :disk_log.open(name: name, file: String.to_charlist(path), mode: :read_only) do
      {:ok, ^name} ->
        :disk_log.close(name)
        :ok

      {:repaired, ^name, _recovered, _badbytes} ->
        :disk_log.close(name)
        :ok

      {:error, {:need_repair, ^name}} ->
        :disk_log.close(name)
        :ok

      {:error, {:not_a_log_file, _} = reason} ->
        {:error, reason}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp maybe_quarantine_corrupt_store(dir, corrupt, opts) do
    case Map.get(opts, :on_corrupt) || Map.get(opts, "on_corrupt") do
      :quarantine ->
        quarantine_corrupt_store(dir, corrupt)

      "quarantine" ->
        quarantine_corrupt_store(dir, corrupt)

      _ ->
        {:error,
         {:corrupt_mnesia_store,
          %{
            dir: dir,
            corrupt_logs: corrupt,
            repair: "pass on_corrupt: :quarantine to move this store aside and start a fresh loom"
          }}}
    end
  end

  defp quarantine_corrupt_store(dir, corrupt) do
    quarantine_dir = quarantine_dir(dir)
    do_quarantine_corrupt_store(dir, quarantine_dir, corrupt)
  end

  defp do_quarantine_corrupt_store(dir, quarantine_dir, corrupt) do
    with :ok <- File.mkdir_p!(Path.dirname(quarantine_dir)),
         :ok <- File.rename(dir, quarantine_dir),
         :ok <- File.mkdir_p(dir) do
      :ok
    else
      {:error, reason} ->
        {:error,
         {:corrupt_mnesia_store_quarantine_failed,
          %{dir: dir, quarantine_dir: quarantine_dir, corrupt_logs: corrupt, reason: reason}}}
    end
  rescue
    e ->
      {:error,
       {:corrupt_mnesia_store_quarantine_failed,
        %{
          dir: dir,
          quarantine_dir: quarantine_dir,
          corrupt_logs: corrupt,
          reason: Exception.message(e)
        }}}
  end

  defp quarantine_dir(dir) do
    stamp =
      DateTime.utc_now()
      |> Calendar.strftime("%Y%m%dT%H%M%SZ")

    "#{dir}-corrupt-#{stamp}-#{System.unique_integer([:positive])}"
  end

  defp ensure_schema(mnesia) do
    case call(mnesia, :create_schema, [[node()]]) do
      :ok -> :ok
      {:error, {_kind, {:already_exists, _node}}} -> :ok
      {:error, {:already_exists, _node}} -> :ok
      {:error, reason} -> {:error, reason}
    end
  end

  defp ensure_table(table, mnesia) do
    # Disc copies require a named node. On `:nonode@nohost` (unnamed
    # BEAM, e.g. tests, REPL without distributed Erlang) Mnesia
    # rejects `disc_copies` with `:bad_type`. Fall back to in-memory
    # `ram_copies` there; production deployments that need persistence
    # are expected to run on a named node (--sname/--name), in which
    # case `disc_copies` fires and the table is on disk.
    copies_key =
      case node() do
        :nonode@nohost -> :ram_copies
        _ -> :disc_copies
      end

    create_opts = [
      {:attributes, [:key, :value]},
      {:type, :ordered_set},
      {copies_key, [node()]}
    ]

    case call(mnesia, :create_table, [table, create_opts]) do
      {:atomic, :ok} ->
        wait_for_table(table, mnesia)

      {:aborted, {:already_exists, ^table}} ->
        wait_for_table(table, mnesia)

      {:aborted, reason} ->
        {:error, reason}
    end
  end

  defp wait_for_table(table, mnesia) do
    case call(mnesia, :wait_for_tables, [[table], 5_000]) do
      :ok -> :ok
      {:timeout, _tables} = timeout -> {:error, timeout}
      {:error, reason} -> {:error, reason}
      other -> {:error, other}
    end
  end

  defp default_table do
    :"cantrip_loom_mnesia_#{System.unique_integer([:positive])}"
  end

  # Mnesia is listed in cantrip's `included_applications` so it's
  # loaded (modules on the code path) but not auto-started. We start
  # it lazily from `init/1` so the caller can configure `:dir` first.
  defp available? do
    Code.ensure_loaded?(:mnesia)
  end

  defp call(mnesia, fun, args) do
    apply(mnesia, fun, args)
  end

  defp with_schema_lock(fun) when is_function(fun, 0) do
    :global.trans({__MODULE__, :schema_setup}, fun, [node()])
  end

  defp storage_event(event) do
    {:cantrip_loom_event, @version, normalize_event(event)}
  end

  defp event_type(event), do: Map.get(event, :type) || Map.get(event, "type")

  defp normalize_event(event) do
    case event_type(event) do
      :turn ->
        %{type: "turn", turn: Map.fetch!(event, :turn)}

      "turn" ->
        %{type: "turn", turn: Map.fetch!(event, :turn)}

      :reward ->
        %{type: "reward", index: Map.fetch!(event, :index), reward: Map.fetch!(event, :reward)}

      "reward" ->
        %{type: "reward", index: Map.fetch!(event, :index), reward: Map.fetch!(event, :reward)}

      :intent ->
        %{type: "intent", intent: Map.fetch!(event, :intent)}

      "intent" ->
        %{type: "intent", intent: Map.fetch!(event, :intent)}

      _ ->
        %{type: "event", event: event}
    end
  end

  defp upcast!({:cantrip_loom_event, @version, event}), do: event

  defp upcast!({:cantrip_loom_event, version, _event}) do
    raise "unsupported loom Mnesia version: #{version}"
  end

  # Legacy v1 records before the version envelope stored the event map directly.
  defp upcast!(event) when is_map(event), do: event
end
