defmodule Cantrip.ACP.DiagnosticsTest do
  @moduledoc """
  Pins the live-introspection contract: from a remsh into a running BEAM,
  Diagnostics.dump/0 must return structured data describing every active
  AgentHandler table — sessions, bridges, last_answers, and the conn.
  """

  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Cantrip.ACP.{AgentHandler, Diagnostics, EventBridge}

  test "dump/0 walks every acp_handler ETS table and reports its contents" do
    table = AgentHandler.new()
    AgentHandler.set_connection(table, %{conn: self()})

    bridge = EventBridge.start(nil, "sess_diag", notify_fn: fn _ -> :ok end)
    :ets.insert(table, {{:session, "sess_diag"}, %{cwd: "/tmp"}})
    :ets.insert(table, {{:bridge, "sess_diag"}, bridge})
    :ets.insert(table, {{:last_answer, "sess_diag"}, "the answer"})

    test_pid = self()

    capture_io(fn ->
      send(test_pid, {:dump_result, Diagnostics.dump()})
    end)

    assert_receive {:dump_result, dump}

    [info | _] =
      dump
      |> Enum.filter(fn %{table: t} -> t == table end)

    assert info.conn == %{conn: self()}
    assert {"sess_diag", %{cwd: "/tmp"}} in info.sessions

    assert Enum.any?(info.bridges, fn
             {"sess_diag", ^bridge, bi} when is_list(bi) -> true
             _ -> false
           end)

    assert {"sess_diag", "<redacted answer #{byte_size("the answer")} chars>"} in info.last_answers
  end

  test "bridges/0 returns a flat list across all tables" do
    table = AgentHandler.new()
    AgentHandler.set_connection(table, %{conn: self()})
    bridge = EventBridge.start(nil, "sess_b", notify_fn: fn _ -> :ok end)
    :ets.insert(table, {{:bridge, "sess_b"}, bridge})

    assert {"sess_b", bridge} in Diagnostics.bridges()
  end

  test "bridge_info/1 returns :dead for an exited process" do
    pid = spawn(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _}, 500

    assert :dead = Diagnostics.bridge_info(pid)
  end

  test "bridge_info/1 returns Process.info keys for a live process" do
    pid = spawn(fn -> Process.sleep(:infinity) end)
    on_exit(fn -> Process.exit(pid, :kill) end)

    info = Diagnostics.bridge_info(pid)
    assert is_list(info)
    assert Keyword.has_key?(info, :status)
    assert Keyword.has_key?(info, :message_queue_len)
  end

  describe "redact/1 — never leak secrets in diagnostic dumps" do
    test "replaces secret-shaped fields with placeholders preserving length" do
      payload = %{
        model: "gpt-5-mini",
        api_key: "sk-proj-VeqpnxccDQtWXwhtUgtJXFDF",
        timeout_ms: 30_000
      }

      out = Diagnostics.redact(payload)

      assert out.model == "gpt-5-mini"
      assert out.timeout_ms == 30_000
      assert out.api_key == "<redacted #{byte_size("sk-proj-VeqpnxccDQtWXwhtUgtJXFDF")} chars>"
      refute String.contains?(inspect(out), "sk-proj")
    end

    test "recurses into nested maps, lists, and tuples" do
      term = %{
        cantrip: %{
          llm_state: %{api_key: "secret-thing", base_url: "https://api"},
          retry: %{max_retries: 3}
        },
        children: [
          %{api_key: "k1"},
          {:tagged, %{token: "t1"}}
        ]
      }

      out = Diagnostics.redact(term)

      assert out.cantrip.llm_state.api_key == "<redacted 12 chars>"
      assert out.cantrip.llm_state.base_url == "https://api"
      assert out.cantrip.retry.max_retries == 3
      [first, {:tagged, second}] = out.children
      assert first.api_key == "<redacted 2 chars>"
      assert second.token == "<redacted 2 chars>"
    end

    test "redacts any key whose name contains a secret pattern (token, password, secret, authorization, cookie)" do
      patterns = %{
        anthropic_api_key: "a",
        access_token: "b",
        refresh_token: "c",
        password: "d",
        client_secret: "e",
        authorization: "f",
        session_cookie: "g"
      }

      out = Diagnostics.redact(patterns)

      Enum.each(Map.values(out), fn v -> assert v =~ "<redacted" end)
    end

    test "leaves nil and empty-string values alone" do
      assert %{api_key: nil} = Diagnostics.redact(%{api_key: nil})
      assert %{api_key: ""} = Diagnostics.redact(%{api_key: ""})
    end

    test "preserves struct __struct__ on Cantrip-shaped maps" do
      cantrip = %Cantrip{
        id: "c1",
        llm_state: %{api_key: "leaky", model: "x"}
      }

      out = Diagnostics.redact(cantrip)

      assert out.__struct__ == Cantrip
      assert out.llm_state.api_key == "<redacted 5 chars>"
      assert out.llm_state.model == "x"
    end

    test "dump_table/2 redacts by default; redact: false leaves the value intact" do
      table = AgentHandler.new()
      AgentHandler.set_connection(table, %{conn: self()})

      session = %{
        cwd: "/tmp",
        cantrip: %{api_key: "VERY-SECRET", model: "gpt-5"}
      }

      :ets.insert(table, {{:session, "sess_x"}, session})
      :ets.insert(table, {{:last_answer, "sess_x"}, "copied token sk-proj-example"})

      test_pid = self()

      capture_io(fn ->
        send(test_pid, {:dump_table_default, Diagnostics.dump_table(table)})
      end)

      assert_receive {:dump_table_default, info_default}
      [{_id, s}] = info_default.sessions
      assert s.cantrip.api_key == "<redacted 11 chars>"

      assert {"sess_x", "<redacted answer #{byte_size("copied token sk-proj-example")} chars>"} in info_default.last_answers

      capture_io(fn ->
        send(test_pid, {:dump_table_raw, Diagnostics.dump_table(table, redact: false)})
      end)

      assert_receive {:dump_table_raw, info_raw}
      [{_id, raw}] = info_raw.sessions
      assert raw.cantrip.api_key == "VERY-SECRET"
      assert {"sess_x", "copied token sk-proj-example"} in info_raw.last_answers
    end

    test "printed dump output is redacted by default" do
      table = AgentHandler.new()
      AgentHandler.set_connection(table, %{conn: self()})

      :ets.insert(
        table,
        {{:session, "sess_print"}, %{cantrip: %{api_key: "VERY-SECRET", model: "gpt-5"}}}
      )

      :ets.insert(table, {{:last_answer, "sess_print"}, "copied token sk-proj-example"})

      output = capture_io(fn -> Diagnostics.dump_table(table) end)

      assert output =~ "<redacted"
      assert output =~ "<redacted answer"
      refute output =~ "VERY-SECRET"
      refute output =~ "sk-proj-example"
    end
  end
end
