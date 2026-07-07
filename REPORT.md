# can-ix5r Report

Branch: `epipe-graceful`

## Reproduction

Pre-fix command, run from the repository root:

```sh
mix run -e 'port = Port.open({:spawn_executable, System.find_executable("elixir")}, [:binary, :exit_status, {:packet, 4}, args: Enum.flat_map(:code.get_path(), &["-pa", List.to_string(&1)]) ++ ["-e", "Cantrip.Medium.Code.PortChild.main()"]]); send_frame = fn term -> Port.command(port, :erlang.term_to_binary(term)) end; send_frame.({:init, []}); receive do {^port, {:data, payload}} -> IO.inspect(:erlang.binary_to_term(payload), label: "init") after 5000 -> IO.puts("init timeout") end; ref = System.unique_integer([:positive, :monotonic]); send_frame.({:eval, ref, "Process.sleep(200); done.(\"late\")", %{gate_names: ["done"], evaluator: :raw}}); Port.close(port); Process.sleep(1000); IO.puts("parent survived")'
```

Pre-fix output:

```text
init: :ready
** (EXIT from #PID<0.94.0>) an exception was raised:
    ** (ErlangError) Erlang error: :epipe
        (elixir 1.19.5) lib/io.ex:308: IO.binwrite/2
        lib/cantrip/medium/code/port_child.ex:856: Cantrip.Medium.Code.PortChild.do_write_frame/2
        lib/cantrip/medium/code/port_child.ex:165: Cantrip.Medium.Code.PortChild.protocol_loop/2

parent survived
```

Sequence: parent starts `Cantrip.Medium.Code.PortChild`, receives `:ready`, sends an eval that sleeps, closes the Erlang port before the child writes its reply, then the child attempts to write a frame to closed stdout. `IO.binwrite/2` raises `:epipe` inside the linked protocol process.

## Fix

`Cantrip.Medium.Code.PortChild.do_write_frame/2` now handles only the closed-pipe write failure. `:epipe` is returned to the main child loop as `{:error, :epipe}`; any other write-side exception is re-raised so unexpected write failures still fail loudly.

The top-level child loop treats `:epipe` as an expected shutdown class, not a successful normal exit. Before exiting it:

- flushes and closes the current transient loom via `Cantrip.Loom.close/1`;
- logs the stderr Goodbye line;
- exits with `{:shutdown, {:port_write_failed, :epipe}}`.

`Cantrip.Loom.Storage` now exposes optional `flush/1` and `close/1` lifecycle callbacks. JSONL implements them as synchronous/no-op lifecycle hooks because every append is already a complete `File.write!/3`; Mnesia implements `flush/1` with `:mnesia.sync_log/0` and leaves `close/1` as `:ok` because Mnesia is a shared VM application, not a per-loom handle.

Post-fix reproduction output:

```text
init: :ready
cantrip port child: parent port closed during write (:epipe); Goodbye.
parent survived
```

The regression test `port child treats epipe during reply as graceful shutdown` uses the real child process and packet protocol. It sends a loom into the child, appends a sentinel final turn before the delayed reply, closes the parent port to force `:epipe`, asserts `flush` then `close` were called by the storage backend, reloads the same loom storage, and asserts the sentinel last turn is present after re-summon. It also asserts the Goodbye log and no new `erl_crash.dump*` in the repo root.

## Verification

- `mix test test/port_code_medium_test.exs` passed: 21 tests, 0 failures.
- `mix test --only mnesia` passed: 56 tests, 0 failures.
- Isolated reruns of suite-timeout locations passed:
  - `mix test test/familiar_behavior_test.exs:108`
  - `mix test test/familiar_behavior_test.exs:159`
  - `mix test test/familiar_behavior_test.exs:403`

Full-suite status:

- `mix test` failed once with a Mnesia backend timeout in `test/loom_backend_symmetry_test.exs:43`.
- `mix test --max-cases 1` later cascaded into Familiar behavior timeouts and was stopped after the third timeout.
- Those failures were not fixed here because the affected tests pass in isolation and are outside the port-child `:epipe` hardening scope.

## Discovered Tickets

- `can-nlga`: Mnesia backend symmetry test can time out in full suite.
- `can-petw`: Familiar behavior tests can cascade time out in full-suite runs.

## Uncertainty

I did not find original incident logs from 2026-07-05 in this workspace, so the exact production trigger remains inferred. The reproduced failure matches the requested root sequence: parent port closes, child writes to it, `IO.binwrite/2` raises `:epipe`, and the linked protocol process can take down the child BEAM. The fix hardens that sequence directly.
