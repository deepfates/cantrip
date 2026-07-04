# Cantrip in an ACP-Aware Editor — Mounting the Familiar

Walks a user from "I want cantrip in my editor" to "cantrip is mounted and responding," with Zed as the primary path and brief notes for JetBrains and Toad.

## What this doc gets you

A working Cantrip Familiar mounted as a custom ACP agent inside an ACP-aware
editor. By the end you will have a Familiar that shows up in your editor's
agent picker, holds a chat-like conversation about your codebase, and remembers
prior turns across editor restarts via the workspace-keyed Mnesia loom. Read
time: 10 minutes. Hands-on time: 15 minutes if Elixir and provider keys are
already in place.

The Agent Client Protocol (ACP) is the LSP-equivalent for AI agents — an open
standard for editors to discover, mount, and stream from agents over JSON-RPC
on stdio. It is backed by Zed and has community plugins for JetBrains, Neovim,
Emacs, and VS Code. As of May 2026 the ACP Registry includes Claude Code,
Codex CLI, Copilot CLI, OpenCode, and Gemini CLI. Cantrip slots into the same
shape as a custom agent.

## 1. Prerequisites

- **Elixir 1.19+** with OTP 26+ on PATH (`elixir --version` to check).
- **Cantrip in your project**, either as a dep in `mix.exs`:

  ```elixir
  defp deps do
    [{:cantrip, "~> 1.3"}]
  end
  ```

  or as a cloned checkout you've run `mix deps.get && mix compile` against.
- **Provider keys configured.** Copy `.env.example` to `.env` and fill in
  one provider's keys. Minimum for an OpenAI-compatible provider:

  ```bash
  CANTRIP_LLM_PROVIDER=openai_compatible
  OPENAI_API_KEY=sk-...
  OPENAI_MODEL=gpt-5-mini
  ```

  The Familiar reads these via `Cantrip.LLM.from_env/0` at session creation.
- **epmd reachable** (`epmd -daemon` works, port 4369 isn't blocked). The
  workspace-keyed Mnesia loom requires a named BEAM. If you can't run a
  named node, pass `--loom-path .cantrip/familiar.jsonl` to opt into the
  JSONL escape hatch.

## 2. Smoke-test the ACP server standalone

Before wiring an editor in, confirm the stdio server actually speaks JSON-RPC.
Run it from your workspace root with provider env loaded:

```bash
source .env
mix cantrip.familiar --acp
```

You should see one stderr line: `Familiar ACP server starting on stdio...`
and then silence — the server is waiting on stdin. Pipe a synthetic
`initialize` request to confirm the response shape:

```bash
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":1}}' \
  | (source .env && mix cantrip.familiar --acp)
```

You should see a JSON-RPC response on stdout with `agentCapabilities` and
`protocolVersion: 1`. If you get that, the server side of the protocol is
healthy and editor integration will not be the failing layer.

If you get `Cannot resolve LLM` on stderr instead, your provider env didn't
load. Fix that before continuing.

## 3. Mount in Zed (primary path)

Zed registers external agents under the `agent_servers` key in its settings
file at `~/.config/zed/settings.json` (macOS and Linux). Add a `"Cantrip
Familiar"` entry whose `command` invokes the included wrapper script — the
wrapper `cd`s into the cantrip checkout and execs `mix cantrip.familiar --acp`,
which is what keeps `mix` finding the right project regardless of which
workspace Zed launches the agent from.

```json
{
  "agent_servers": {
    "Cantrip Familiar": {
      "type": "custom",
      "command": "/absolute/path/to/cantrip/scripts/familiar-acp.sh",
      "args": [],
      "env": {
        "CANTRIP_LLM_PROVIDER": "openai_compatible",
        "OPENAI_API_KEY": "sk-...",
        "OPENAI_MODEL": "gpt-5-mini"
      }
    }
  }
}
```

Notes:

- The `env` block is the cleanest way to give the spawned BEAM provider keys
  without depending on your shell's env propagating into Zed. Treat
  `settings.json` accordingly — it's now secret-bearing.
- The Familiar receives Zed's project cwd via the ACP `session/new` `cwd`
  field and uses it as the sandbox root for `read_file`, `list_dir`, and
  `search`. You do not configure root yourself.
- For a project-local consumer of cantrip-as-a-dep, replace the wrapper with
  `command: "mix"`, `args: ["cantrip.familiar", "--acp"]`, and add
  `"cwd": "/absolute/path/to/your/project"` so `mix` finds the right
  `mix.exs`. The wrapper script in the cantrip checkout is the convenience
  path for developers working *on* cantrip; project-as-consumer is the
  realistic shape for users.

Reload Zed's settings (`cmd-shift-p` → "zed: open settings", save). Open the
agent panel and Cantrip Familiar should appear in the picker alongside
whichever ACP agents you already have mounted.

## 4. What you see once it's mounted

Pick `Cantrip Familiar` from Zed's agent panel and you get a chat-like
surface. Type an intent like *"summarize the public modules under lib/cantrip"*
and the Familiar responds, streaming token-shaped chunks back through ACP
`session/update` notifications. Subsequent prompts in the same Zed session
continue the same conversation.

Close Zed, reopen it, mount the Familiar against the same workspace, and the
prior turns are still visible to the entity — the loom is keyed to your
workspace path via SHA-256 fingerprint and persists in
`<workspace>/.cantrip/mnesia/`. That persistence-across-editor-restart is the
clearest behavioural difference from a stateless ACP agent.

## 5. Alternatives

**JetBrains.** ACP support ships through the community plugin (search
"Agent Client Protocol" in the marketplace). Configuration shape is the same
three fields — command, args, env — set in the plugin's external-agent
settings UI. Point command at `scripts/familiar-acp.sh` or `mix` with the
right `cwd`, and the agent appears in the JetBrains AI side panel.

**Toad** (Will McGugan / Textual). Toad is a unified TUI for ACP agents.
Add a Cantrip entry via Toad's external-agent configuration (consult Toad's
current docs for exact syntax — the agent registration shape evolves), then
launch with the agent name to mount the Familiar in the terminal. Useful when
you want a quick chat-with-the-codebase surface without bringing up a full
editor.

## 6. What ACP supports today through cantrip

The handler at `lib/cantrip/acp/agent_handler.ex` implements:

- `initialize` — protocol version 1, capabilities `load_session: false`,
  `prompt_capabilities.image: false`.
- `authenticate` — no-op success (cantrip auth is provider-key based, not
  ACP-mediated).
- `session/new` — accepts a `cwd` (required to be absolute), starts a
  per-session event bridge, returns a `session_id`. Each session gets a fresh
  Familiar with the workspace as root.
- `session/prompt` — runs one Familiar turn. Streaming updates flow through
  the per-session bridge as `session/update` notifications; the final
  `PromptResponse` carries `stop_reason: :end_turn`.
- `session/cancel` — accepted as a notification (currently a no-op; cantrip
  cancellation through ACP is on the post-v1.3 list).
- Trace correlation via `_meta.trace_id` (or `_meta.cantrip_trace_id`) on
  both `session/new` and `session/prompt` — telemetry the Familiar emits is
  joined to whatever ID the editor supplies.

The Familiar's affordances over ACP are the same as in REPL: `read_file`,
`list_dir`, `search`, and `done`. **No write/edit gate yet** — the Familiar
will read and reason about your codebase, but it cannot modify files. If you
want a code-editing agent in your editor, Claude Code or Codex CLI mounted
through the same ACP picker is the right choice today.

## 7. Diagnostics and troubleshooting

Add `--diagnostics` to the command in your editor config to print the BEAM
node name and cookie on stderr at startup. With those, attach a remote shell:

```bash
iex --name inspector@127.0.0.1 --cookie <cookie> --remsh <node-name>
```

From the IEx prompt, `Cantrip.ACP.Diagnostics.dump()` walks every live
AgentHandler ETS table and prints session ids, bridge pids and their
alive/mailbox/current-function status, last cached answers, and the
connection target. Secrets are scrubbed by default. Use this when a session
hangs or you want to confirm the editor is talking to the BEAM you think it
is.

Common failure modes:

- **`Cannot resolve LLM`** — provider env did not reach the spawned process.
  Put the keys in the editor's `env` block, not just in your shell rc.
- **`Could not promote the BEAM to a named node`** — epmd isn't running or
  port 4369 is blocked. Either start `epmd -daemon` or fall back to
  `--loom-path .cantrip/familiar.jsonl` to skip Mnesia entirely.
- **Two cantrip mounts collide on the same workspace** — each ACP connection
  gets a per-pid name, so coexisting connections in the same editor are
  fine; cross-workspace collisions are prevented by the SHA-256 fingerprint.
  If you genuinely see contention, check `.cantrip/mnesia/` permissions.
- **No streaming, just a final blob arrives** — the bridge is alive but the
  runtime didn't emit `:final_response` for some reason; remsh in and run
  `Cantrip.ACP.Diagnostics.dump()` to see bridge status.

## What's different about cantrip-via-ACP

For *editing code in your editor*, Claude Code or Codex CLI mounted in the
same Zed picker is more capable today. Cantrip-via-ACP is a read-only
codebase companion — useful, but narrower.

Where cantrip is differentiated:

- **Workspace-keyed durable loom.** Conversations survive editor restarts
  and process kills with no extra setup. The Familiar that re-mounts
  tomorrow remembers yesterday's exchange.
- **OTP-supervised entity.** The Familiar is a process you can introspect
  live via remsh + `Cantrip.ACP.Diagnostics`. When it misbehaves, you have
  a real BEAM to attach to, not an opaque sidecar.
- **Composition primitives if you want to grow the entity.** Cantrip's
  `Cantrip.new/1` / `cast/3` / `cast_batch/2` are how you evolve this from
  "codebase Q&A" to a custom-shaped agent.

Mount it for the persistence and the introspection, not because it edits
better than Claude Code. When write/edit gates land post-v1.3, that framing
changes.
