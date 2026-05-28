# Distributed Familiar

Cantrip's distributed story uses ordinary BEAM distribution. Cantrip does not
discover clusters for you; start named nodes, share an Erlang cookie, connect
the nodes, then let Cantrip use those nodes for Mnesia loom replication and
remote child cantrips.

## Node Setup

Run each host as a named node with the same cookie:

```sh
iex --name analysis@host-a --cookie "$CANTRIP_COOKIE" -S mix
iex --name agents@host-b --cookie "$CANTRIP_COOKIE" -S mix
```

Connect nodes using your deployment's normal mechanism:

```elixir
Node.connect(:"agents@host-b")
```

Cluster discovery is deliberately out of scope. `libcluster`, Kubernetes
headless services, static config, or manual `Node.connect/1` all work as long
as the BEAM nodes can reach each other and authenticate with the same cookie.

## Replicated Mnesia Loom

Once nodes are connected, join Mnesia to the remote DB node and replicate the
loom table:

```elixir
table = :cantrip_familiar_loom
nodes = [:"agents@host-b"]

{:ok, _connected} = Cantrip.Cluster.connect_mnesia(nodes)
:ok = Cantrip.Cluster.replicate_table(table, nodes, copy_type: :disc_copies)

{:ok, familiar} =
  Cantrip.Familiar.new(
    llm: llm,
    root: File.cwd!(),
    loom_storage: {:mnesia, table: table}
  )
```

`connect_mnesia/2` wraps `:mnesia.change_config(:extra_db_nodes, nodes)`.
`replicate_table/3` converts the local table copy and adds remote table copies.
Use `copy_type: :ram_copies` for ephemeral test clusters; use
`:disc_copies` for durable deployment nodes.

The launcher `mix cantrip.familiar` already promotes the current BEAM to a
workspace-stable node when using the default Mnesia loom. In a cluster, start
with explicit node names and cookies so all nodes agree on identity.

## Remote Child Cantrips

Child cantrip configs may include `:node`. When the node is remote,
`Cantrip.new/1` builds the child on that node with `:rpc.call/4`, and
`Cantrip.cast/3` runs the episode on that node. Parent observations still
receive the child result and loom turns, so the local Familiar's loom keeps the
delegation trace.

```elixir
{:ok, reader} =
  Cantrip.new(%{
    node: :"agents@host-b",
    identity: %{system_prompt: "Read files and return concise excerpts."},
    circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 2}]}
  })

{:ok, text, reader, child_loom, meta} =
  Cantrip.cast(reader, "Read README.md")
```

From the Familiar's code medium, the same shape works:

```elixir
{:ok, reader} = Cantrip.new(%{
  node: :"agents@host-b",
  identity: %{system_prompt: "Read README.md and return the first paragraph."},
  circle: %{type: :code, gates: ["read_file", "done"], wards: [%{max_turns: 2}]}
})

{:ok, paragraph, _reader, _loom, _meta} = Cantrip.cast(reader, "Read README.md")
done.(paragraph)
```

Remote casts intentionally do not stream local process events across nodes in
this first version. The request/response result and child loom are returned;
fire-and-forget inter-entity messaging remains future work.
