defmodule Mix.Tasks.Cantrip.Familiar do
  @shortdoc "Run the Familiar — a persistent computational entity"
  @moduledoc """
  Run the Familiar in REPL mode (interactive), single-shot mode, or ACP server mode.

      mix cantrip.familiar                          # REPL mode
      mix cantrip.familiar "explain this codebase"  # single-shot
      mix cantrip.familiar --acp                    # ACP stdio server

  ## Options

    * `--acp` — start as an ACP stdio server instead of REPL
    * `--diagnostics` — print the cookie + remsh attach command on
      stderr (the BEAM is named regardless; this flag just makes the
      attach affordance visible)
    * `--json` — output events as JSONL stream (for piping/scripting)
    * `--loom-path PATH` — store the loom as JSONL at this path. When
      omitted, the loom is workspace-keyed Mnesia (BEAM-native).
    * `--max-turns N` — maximum turns per episode (default: 20)
    * `--help` — show this help

  ## Loom backend

  REPL and single-shot promote the BEAM to a workspace-stable named
  node and use Mnesia (`disc_copies`) keyed to the workspace as the
  loom backend. The same workspace re-summons the same loom across
  restarts, with prior turns visible as `loom.turns`.

  Pass `--loom-path PATH` to use JSONL instead, when you want a
  portable, exportable, human-readable trace.
  """

  use Mix.Task
  @requirements ["app.start"]

  alias Cantrip.CLI.Renderer

  @impl true
  def run(args) do
    case parse_args(args) do
      {:help, _} ->
        Mix.shell().info(usage())

      {:acp, ctx} ->
        if ctx.diagnostics, do: start_diagnostic_node()
        run_acp(ctx.opts)

      {:repl, ctx} ->
        # The named-node setup exists to give Mnesia a stable node identity
        # for `disc_copies` (the default loom backend). If the caller has
        # explicitly opted out of Mnesia by passing `--loom-path`, we don't
        # need a named node — and forcing one here would defeat the
        # documented JSONL escape hatch in environments where distributed
        # Erlang can't start (missing epmd, port restrictions, etc.).
        if is_nil(Keyword.get(ctx.opts, :loom_path)) do
          ensure_named_node!(File.cwd!())
          if ctx.diagnostics, do: announce_named_node()
        end

        run_familiar(ctx.intent, ctx.opts)
    end
  end

  @doc """
  Parses the task arguments into a routing decision.

  Pure function returning one of:

    * `{:help, %{opts: opts}}` — print usage and exit
    * `{:acp, %{opts: opts, diagnostics: bool}}` — run as ACP stdio server
    * `{:repl, %{opts: opts, intent: nil | binary, diagnostics: bool}}` —
      run interactive REPL (when intent is nil) or single-shot

  `diagnostics` is mode-agnostic: any mode (REPL, single-shot, ACP) may
  request the remsh-attach affordance via `--diagnostics`. ACP, REPL, and CLI
  are projections of the same runtime; the diagnostic node is part of that
  runtime, not an ACP-specific concern.
  """
  @spec parse_args([String.t()]) ::
          {:help, %{opts: keyword()}}
          | {:acp, %{opts: keyword(), diagnostics: boolean()}}
          | {:repl, %{opts: keyword(), intent: nil | String.t(), diagnostics: boolean()}}
  def parse_args(args) do
    {opts, positional, _} =
      OptionParser.parse(args,
        strict: [
          loom_path: :string,
          max_turns: :integer,
          help: :boolean,
          acp: :boolean,
          diagnostics: :boolean,
          json: :boolean
        ],
        aliases: [h: :help]
      )

    diagnostics = !!opts[:diagnostics]

    cond do
      opts[:help] -> {:help, %{opts: opts}}
      opts[:acp] -> {:acp, %{opts: opts, diagnostics: diagnostics}}
      true -> {:repl, %{opts: opts, intent: List.first(positional), diagnostics: diagnostics}}
    end
  end

  defp run_acp(_opts) do
    IO.puts(:stderr, "Familiar ACP server starting on stdio...")
    Cantrip.ACP.Server.run(runtime: Cantrip.ACP.Runtime.Familiar)
  end

  # ACP keeps the per-pid name (multiple ACP servers can coexist on one
  # host); the workspace-stable name belongs to REPL/single-shot, where
  # the workspace IS the identity.
  #
  # `--diagnostics` is an *optional* affordance — if epmd or net_kernel
  # can't start (no epmd on PATH, port 4369 blocked, etc.), warn but
  # don't crash the host runtime. ACP's stdio server should keep coming
  # up even when remsh attach is unavailable.
  defp start_diagnostic_node do
    cookie = Cantrip.Familiar.Cookie.random()
    name = :"familiar-#{System.pid()}@127.0.0.1"

    ensure_epmd_running()

    case :net_kernel.start([name, :longnames]) do
      {:ok, _} ->
        :erlang.set_cookie(node(), cookie)
        announce_node(name, cookie)

      {:error, {:already_started, _}} ->
        :ok

      {:error, reason} ->
        IO.puts(
          :stderr,
          "warning: could not register diagnostic node: #{Cantrip.SafeFormat.inspect(reason)}"
        )
    end
  rescue
    e ->
      IO.puts(
        :stderr,
        "warning: diagnostic node setup raised: #{Cantrip.SafeFormat.exception(e)}"
      )
  end

  # Promote the BEAM to a workspace-stable named node. Mnesia ties
  # `disc_copies` to node identity, so a stable name per workspace is
  # what makes "summon, kill, re-summon, see prior turns" hold across
  # restarts. `:nonode@nohost` would force `ram_copies` (per the
  # mnesia adapter's node-aware copy selection).
  #
  # Fail loud: a launcher whose stated job is BEAM-native persistence
  # should not pretend it succeeded when net_kernel can't start.
  # Same principle as `Cantrip.Loom.new/2`'s explicit-backend fail-loud
  # invariant — silent downgrades are how the prior "production
  # default" claim went hollow.
  defp ensure_named_node!(workspace_root) do
    case node() do
      :nonode@nohost ->
        ensure_epmd_running()
        name = node_name_for_workspace(workspace_root)
        cookie = Cantrip.Familiar.Cookie.for_workspace!(workspace_root)

        case :net_kernel.start([name, :longnames]) do
          {:ok, _} ->
            :erlang.set_cookie(node(), cookie)
            configure_mnesia_dir!(workspace_root)

          {:error, {:already_started, _}} ->
            :ok

          {:error, reason} ->
            raise """
            Could not promote the BEAM to a named node: #{Cantrip.SafeFormat.inspect(reason)}

            The Familiar's workspace-keyed Mnesia loom requires a named
            node so prior turns survive restarts. Common causes:

              * `epmd` is not on PATH or not allowed to run
              * port 4369 (epmd) is blocked

            If you cannot run a named BEAM in this environment, opt out
            of Mnesia by passing an explicit JSONL loom path:

              mix cantrip.familiar --loom-path .cantrip/familiar.jsonl
            """
        end

      _named ->
        # Already named (someone launched with --sname/--name). Trust
        # their setup; just relocate Mnesia under .cantrip/.
        configure_mnesia_dir!(workspace_root)
    end
  end

  # Point Mnesia at `.cantrip/mnesia/` for this workspace. Mnesia is
  # in `included_applications` (not `extra_applications`), so it's
  # loaded but not yet started. Setting `:dir` before the adapter's
  # lazy `:mnesia.start/0` is enough — no stop/restart cycle, no
  # orphaned `Mnesia.<node>/` dir at cwd from a premature auto-start.
  #
  # Verified empirically: after `mix run`, `Application.started_applications/0`
  # does not include `:mnesia`, and `:mnesia.system_info(:tables)`
  # errors with `node_not_running`. The launcher test suite does not
  # create any `Mnesia.*/` dir on disk. The "included apps may be
  # started with the parent" concern doesn't apply here because
  # `Cantrip.Application.start/2` never calls `Application.ensure_*`
  # on Mnesia.
  defp configure_mnesia_dir!(workspace_root) do
    desired = Path.join([workspace_root, ".cantrip", "mnesia"]) |> String.to_charlist()
    File.mkdir_p!(to_string(desired))
    Application.put_env(:mnesia, :dir, desired)
    :ok
  end

  # `System.cmd("epmd", ["-daemon"], ...)` raises `ErlangError` when
  # epmd is not on PATH. Catching here keeps the actionable
  # `--loom-path` error message in `ensure_named_node!` reachable
  # rather than dying inside the cmd call. If epmd really is missing,
  # the subsequent `:net_kernel.start` will surface the right error.
  defp ensure_epmd_running do
    System.cmd("epmd", ["-daemon"], stderr_to_stdout: true)
    :ok
  rescue
    _ -> :ok
  end

  @doc """
  Workspace-stable node name. Two distinct workspaces produce two
  distinct names (so they don't share a Mnesia schema); the same
  workspace produces the same name across launches (so Mnesia's
  per-node `disc_copies` find the prior data).
  """
  @spec node_name_for_workspace(String.t()) :: atom()
  def node_name_for_workspace(root) when is_binary(root) do
    String.to_atom("cantrip-familiar-" <> workspace_fingerprint(root) <> "@127.0.0.1")
  end

  defp workspace_fingerprint(root) do
    :crypto.hash(:sha256, root)
    |> Base.encode16(case: :lower)
    |> binary_part(0, 16)
  end

  defp announce_named_node do
    announce_node(node(), :erlang.get_cookie())
  end

  defp announce_node(name, cookie) do
    cookie_text = Atom.to_string(cookie)
    IO.puts(:stderr, "Diagnostic node: #{name}  (cookie: #{cookie_text})")

    IO.puts(
      :stderr,
      "Attach with: iex --name inspector@127.0.0.1 --cookie #{cookie_text} --remsh #{name}"
    )

    IO.puts(:stderr, "Then try: Cantrip.ACP.Diagnostics.dump()")
  end

  @doc """
  Build the Familiar from launcher opts. Pure construction — no
  process is started, no LLM call is made.

  Storage policy:

    * `:loom_path` set → JSONL at that path (caller's explicit
      portable-trace choice)
    * otherwise → workspace-keyed Mnesia, via `Cantrip.Familiar.new/1`'s
      Mnesia-by-`:root` default (which the launcher always sets)

  No defaulted JSONL — the launcher's job is to enable the BEAM-native
  posture the substrate documents, not to ship past it.

  Raises `KeyError` if `:llm` is missing from `opts`. The launcher
  always passes `:llm`; a missing one is a programmer error, not a
  runtime condition.
  """
  @spec build_familiar(keyword()) :: {:ok, Cantrip.t()} | {:error, String.t()} | no_return()
  def build_familiar(opts) when is_list(opts) do
    llm = Keyword.fetch!(opts, :llm)
    root = Keyword.get(opts, :root, File.cwd!())
    max_turns = Keyword.get(opts, :max_turns, 20)

    base = [llm: llm, max_turns: max_turns, root: root]

    base =
      case Keyword.get(opts, :loom_path) do
        nil -> base
        path -> Keyword.put(base, :loom_path, path)
      end

    Cantrip.Familiar.new(base)
  end

  defp run_familiar(intent, opts) do
    case Cantrip.LLM.from_env() do
      {:ok, llm} ->
        case build_familiar(Keyword.put(opts, :llm, llm)) do
          {:ok, cantrip} ->
            renderer = if opts[:json], do: Cantrip.CLI.JsonRenderer.new(), else: Renderer.new()

            if intent do
              run_single_shot(cantrip, intent, renderer, opts)
            else
              run_repl(cantrip, renderer)
            end

          {:error, reason} ->
            Mix.shell().error("Cannot build Familiar: #{reason}")
        end

      {:error, reason} ->
        Mix.shell().error("Cannot resolve LLM: #{reason}")

        Mix.shell().error(
          "Set CANTRIP_MODEL and CANTRIP_API_KEY (or provider-specific env vars)."
        )
    end
  end

  # -- Single-shot: cast with streaming events --

  defp run_single_shot(cantrip, intent, renderer, opts) do
    unless opts[:json] do
      IO.write(:stderr, "Familiar (single-shot)\n")
      IO.write(:stderr, "Intent: #{intent}\n\n")
    end

    caller = self()

    task =
      Task.async(fn ->
        Cantrip.cast(cantrip, intent, stream_to: caller)
      end)

    receive_loop(renderer, task)
  end

  # -- REPL: summon + send in a loop --

  defp run_repl(cantrip, renderer) do
    IO.write(:stderr, "Familiar REPL — persistent computational entity\n")
    IO.write(:stderr, "Type your intents. Ctrl-C to exit.\n\n")

    {:ok, pid} = Cantrip.summon(cantrip)
    repl_loop(pid, renderer)
  end

  defp repl_loop(pid, renderer) do
    case IO.gets("~> ") do
      :eof ->
        IO.write(:stderr, "\nGoodbye.\n")

      {:error, _reason} ->
        IO.write(:stderr, "\nGoodbye.\n")

      input when is_binary(input) ->
        input = String.trim(input)

        if input == "" do
          repl_loop(pid, renderer)
        else
          run_streaming_intent(pid, input, renderer)
          repl_loop(pid, renderer)
        end
    end
  end

  defp run_streaming_intent(pid, intent, renderer) do
    caller = self()

    task =
      Task.async(fn ->
        Cantrip.send(pid, intent, stream_to: caller)
      end)

    receive_loop(renderer, task)
  end

  # -- Event receive loop: renders events as they arrive --

  defp receive_loop(renderer, task) do
    renderer_mod = renderer.__struct__

    receive do
      {:cantrip_event, event} ->
        {output, device, renderer} = renderer_mod.render_event(renderer, event)
        write_output(output, device)
        receive_loop(renderer, task)

      {ref, result} when is_reference(ref) ->
        # Task completed
        Process.demonitor(ref, [:flush])
        drain_events(renderer)

        case result do
          {:ok, _result, _cantrip, _loom, _meta} ->
            :ok

          {:error, reason, _cantrip} ->
            IO.write(
              :stderr,
              IO.ANSI.red() <>
                "Error: #{Cantrip.SafeFormat.inspect(reason)}" <> IO.ANSI.reset() <> "\n"
            )

          {:error, reason} ->
            IO.write(
              :stderr,
              IO.ANSI.red() <>
                "Error: #{Cantrip.SafeFormat.inspect(reason)}" <> IO.ANSI.reset() <> "\n"
            )
        end

      {:DOWN, _ref, :process, _pid, reason} ->
        IO.write(
          :stderr,
          IO.ANSI.red() <>
            "Entity crashed: #{Cantrip.SafeFormat.inspect(reason)}" <> IO.ANSI.reset() <> "\n"
        )
    end
  end

  # Drain any remaining events after task completion
  defp drain_events(renderer) do
    renderer_mod = renderer.__struct__

    receive do
      {:cantrip_event, event} ->
        {output, device, renderer} = renderer_mod.render_event(renderer, event)
        write_output(output, device)
        drain_events(renderer)
    after
      0 -> :ok
    end
  end

  defp write_output(output, device) do
    data = IO.iodata_to_binary(output)

    if data != "" do
      case device do
        :stderr -> IO.write(:stderr, data)
        :stdout -> IO.write(data)
      end
    end
  end

  defp usage do
    """
    usage: mix cantrip.familiar [intent] [--acp] [--diagnostics] [--loom-path PATH] [--max-turns N] [--help]

    Run the Familiar — a persistent computational entity with filesystem observation.

    Without an intent argument, starts in interactive REPL mode.
    With an intent, runs single-shot and exits.
    With --acp, starts an ACP stdio server.

    REPL and single-shot promote the BEAM to a workspace-named node and
    persist the loom in workspace-keyed Mnesia under .cantrip/mnesia/.
    Pass --loom-path PATH to use JSONL instead.
    Add --diagnostics to print the cookie + remsh attach command.
    """
  end
end
