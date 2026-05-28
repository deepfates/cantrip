defmodule Cantrip.RedactTest do
  @moduledoc """
  PROD-8: Implementations MUST redact secrets from logs, traces, and default
  loom exports. Credentials and tokens MUST NOT appear in user-visible
  observations by default.

  These tests pin behavior at two layers:
    1. `Cantrip.Redact.scan/1` — the pure pattern-matching layer.
    2. End-to-end: a gate that returns content with secrets in it produces
       an observation with those secrets replaced before the entity sees it.
  """

  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM
  alias Cantrip.LLMs.Helpers
  alias Cantrip.Redact
  alias Cantrip.SafeFormat

  defmodule ErrorLLM do
    @behaviour Cantrip.LLM

    @impl true
    def query(state, _request) do
      {:error, %{message: "OPENAI_API_KEY=#{Map.fetch!(state, :secret)}"}, state}
    end
  end

  test "top-level Cantrip inspect output never prints LLM state secrets" do
    text =
      inspect(%Cantrip{
        id: "demo",
        llm_module: FakeLLM,
        llm_state: %{api_key: "sk-test-parent-secret", model: "demo"},
        child_llm: {FakeLLM, %{api_key: "sk-test-child-secret"}},
        identity: Cantrip.Identity.new(),
        circle: Cantrip.Circle.new(type: :conversation)
      })

    refute text =~ "llm_state"
    refute text =~ "child_llm"
    refute text =~ "sk-test-parent-secret"
    refute text =~ "sk-test-child-secret"
  end

  describe "scan/1 — well-known credential shapes" do
    test "redacts OpenAI/Anthropic sk-* keys" do
      assert Redact.scan(
               "OPENAI_API_KEY=sk-proj-VeqpnxccDQtWXwhtUgtJXFDFsoesUWR4Y9kj9a5W857MeOAvSm"
             ) =~
               "[REDACTED]"

      refute Redact.scan(
               "OPENAI_API_KEY=sk-proj-VeqpnxccDQtWXwhtUgtJXFDFsoesUWR4Y9kj9a5W857MeOAvSm"
             ) =~
               "VeqpnxccDQtWXwhtUgtJXFDF"
    end

    test "redacts Anthropic sk-ant-* keys" do
      assert Redact.scan("ANTHROPIC_API_KEY=sk-ant-api03-HCe3QI1DBMbWNFlNd0dJZylNrs") =~
               "[REDACTED]"

      refute Redact.scan("ANTHROPIC_API_KEY=sk-ant-api03-HCe3QI1DBMbWNFlNd0dJZylNrs") =~
               "HCe3QI1DBMbWNFlNd0dJ"
    end

    test "redacts Google AIza keys" do
      input = "GEMINI_API_KEY=AIzaSyDZwB5922WT87Q5pBkvfdA5vFRGZW5iO2A"
      out = Redact.scan(input)
      assert out =~ "[REDACTED]"
      refute out =~ "AIzaSyDZwB5922WT87Q5pBkvfdA5"
    end

    test "redacts AWS access keys" do
      assert Redact.scan("AWS_ACCESS_KEY=AKIAIOSFODNN7EXAMPLE") =~ "[REDACTED]"
      assert Redact.scan("token AKIAIOSFODNN7EXAMPLE in logs") =~ "[REDACTED]"
    end

    test "redacts Bearer tokens" do
      assert Redact.scan("Authorization: Bearer eyJ0eXAiOiJKV1QiLCJhbGciOiJIUzI1NiJ9.foo.bar") =~
               "[REDACTED]"
    end

    test "redacts generic *_KEY / *_SECRET / *_TOKEN env assignments" do
      # Even when the value doesn't match a well-known prefix, an env-style
      # assignment to a credential-named variable should be redacted.
      assert Redact.scan("MY_CUSTOM_TOKEN=abc123def456ghi789") =~ "[REDACTED]"
      assert Redact.scan("APP_SECRET = topsecretvalue") =~ "[REDACTED]"
      refute Redact.scan("MY_CUSTOM_TOKEN=abc123def456ghi789") =~ "abc123def456ghi789"
    end

    test "passes innocent content through unchanged" do
      input = "# README\n\nThis is a normal file with no credentials in it."
      assert Redact.scan(input) == input
    end

    test "preserves surrounding structure — keeps the env var name visible" do
      out =
        Redact.scan("OPENAI_API_KEY=sk-proj-VeqpnxccDQtWXwhtUgtJXFDFsoesUWR4Y9kj9a5W857MeOAvSm")

      # Keeping the variable name lets the user know what was redacted.
      assert out =~ "OPENAI_API_KEY"
    end

    test "scan is idempotent — redacting twice is the same as once" do
      input = "OPENAI_API_KEY=sk-proj-VeqpnxccDQtWXwhtUgtJXFDFsoesUWR4Y9kj9a5W857MeOAvSm"
      assert Redact.scan(Redact.scan(input)) == Redact.scan(input)
    end

    test "non-binary values pass through untouched" do
      assert Redact.scan(42) == 42
      assert Redact.scan(:atom) == :atom
      assert Redact.scan(nil) == nil
      assert Redact.scan(["a", 1]) == ["a", 1]
    end
  end

  describe "PROD-8 at the gate observation boundary" do
    test "read_file observation has secrets redacted before reaching the entity" do
      tmp_dir = Path.join(System.tmp_dir!(), "redact_e2e_#{System.unique_integer([:positive])}")
      File.mkdir_p!(tmp_dir)
      env_path = Path.join(tmp_dir, ".env")

      env_body = """
      OPENAI_API_KEY=sk-proj-VeqpnxccDQtWXwhtUgtJXFDFsoesUWR4Y9kj9a5W857MeOAvSm
      ANTHROPIC_API_KEY=sk-ant-api03-HCe3QI1DBMbWNFlNd0dJZylNrsCUs6zZTxJvdmjfJp5YOZ
      GEMINI_API_KEY=AIzaSyDZwB5922WT87Q5pBkvfdA5vFRGZW5iO2A
      INNOCENT_FIELD=just-a-value
      """

      File.write!(env_path, env_body)

      circle =
        Cantrip.Circle.new(%{
          type: :code,
          gates: [%{name: "read_file", dependencies: %{root: tmp_dir}}, %{name: "done"}],
          wards: [%{max_turns: 1}]
        })

      obs = Cantrip.Gate.execute(circle, "read_file", %{path: ".env"})

      assert obs.is_error == false
      assert is_binary(obs.result)

      # The observation MUST NOT contain credential bodies.
      refute obs.result =~ "VeqpnxccDQtWXwhtUgtJXFDF"
      refute obs.result =~ "HCe3QI1DBMbWNFlNd0dJ"
      refute obs.result =~ "AIzaSyDZwB5922WT87Q5pBkvfdA5"

      # Innocent content survives.
      assert obs.result =~ "INNOCENT_FIELD"
      assert obs.result =~ "just-a-value"

      # [REDACTED] markers are visible so the entity (and user) can tell
      # something was filtered.
      assert obs.result =~ "[REDACTED]"

      File.rm_rf!(tmp_dir)
    end
  end

  describe "Pass 5 boundary formatting" do
    @secret "sk-proj-VeqpnxccDQtWXwhtUgtJXFDFsoesUWR4Y9kj9a5W857MeOAvSm"

    test "SafeFormat redacts inspected values and exception messages" do
      inspected = SafeFormat.inspect(%{api_key: @secret})
      message = SafeFormat.exception(%RuntimeError{message: "failed with #{@secret}"})

      assert inspected =~ "[REDACTED]"
      refute inspected =~ "VeqpnxccDQtWXwhtUgtJXFDF"
      assert message =~ "[REDACTED]"
      refute message =~ "VeqpnxccDQtWXwhtUgtJXFDF"
    end

    test "LLM helper fallback redacts provider error bodies" do
      message = Helpers.extract_error(%{provider_response: %{authorization: "Bearer #{@secret}"}})

      assert message =~ "Bearer [REDACTED]"
      refute message =~ "VeqpnxccDQtWXwhtUgtJXFDF"
    end

    test "JSONL persistence redacts inspected fallback keys before disk write" do
      path = tmp_jsonl_path()

      event = %{
        {:tuple_key, "OPENAI_API_KEY=#{@secret}"} => "value",
        type: :unsafe_key
      }

      _loom =
        %{system_prompt: nil}
        |> Cantrip.Loom.new(storage: {:jsonl, path})
        |> Cantrip.Loom.append_event(event)

      body = File.read!(path)
      assert body =~ "[REDACTED]"
      refute body =~ "VeqpnxccDQtWXwhtUgtJXFDF"

      File.rm(path)
    end

    test "gate observations redact inspected non-binary done results" do
      circle =
        Cantrip.Circle.new(%{
          type: :conversation,
          gates: [:done],
          wards: [%{max_turns: 1}]
        })

      obs =
        Cantrip.Gate.execute(circle, "done", %{
          answer: %{api_key: @secret, visible: "kept"}
        })

      assert obs.result =~ "[REDACTED]"
      assert obs.result =~ "visible"
      refute obs.result =~ "VeqpnxccDQtWXwhtUgtJXFDF"
    end

    test "unrestricted code-medium exception observations are redacted" do
      circle =
        Cantrip.Circle.new(%{
          type: :code,
          gates: [:done],
          wards: [%{sandbox: :unrestricted, max_turns: 1}]
        })

      runtime = %Cantrip.Runtime{
        circle: circle,
        execute_gate: fn gate, args -> Cantrip.Gate.execute(circle, gate, args) end
      }

      {:ok, _state, observations, _result, _terminated?} =
        Cantrip.Medium.Code.execute(~s[raise "OPENAI_API_KEY=#{@secret}"], %{}, runtime)

      code_error = Enum.find(observations, &(&1.gate == "code" and &1.is_error))

      assert code_error.result =~ "[REDACTED]"
      refute code_error.result =~ "VeqpnxccDQtWXwhtUgtJXFDF"
    end

    test "ACP wire stringification redacts credential-shaped content" do
      text = Cantrip.ACP.EventBridge.stringify(%{api_key: @secret, answer: "visible"})

      assert text =~ "[REDACTED]"
      assert text =~ "visible"
      refute text =~ "VeqpnxccDQtWXwhtUgtJXFDF"
    end

    test "ACP runtime prompt errors redact provider error reasons" do
      {:ok, cantrip} =
        Cantrip.new(
          llm: {ErrorLLM, %{secret: @secret}},
          circle: %{type: :conversation, gates: [:done], wards: [%{max_turns: 1}]}
        )

      session = %{cantrip: cantrip, entity_pid: nil, stream_to: nil}

      assert {:error, message, _session} =
               Cantrip.ACP.Runtime.Familiar.prompt(session, "trigger provider error")

      assert message =~ "[REDACTED]"
      refute message =~ "VeqpnxccDQtWXwhtUgtJXFDF"
    end

    test "port code-medium exceptions are redacted and do not return stacktraces" do
      llm =
        {FakeLLM,
         FakeLLM.new([
           %{code: ~s[raise "boom OPENAI_API_KEY=#{@secret}"]}
         ])}

      {:ok, cantrip} =
        Cantrip.new(
          llm: llm,
          circle: %{type: :code, gates: [:done], wards: [%{max_turns: 1}]}
        )

      {:ok, _result, _next, loom, _meta} = Cantrip.cast(cantrip, "trigger exception")

      observations = Enum.flat_map(loom.turns, & &1.observation)
      code_error = Enum.find(observations, &(&1.gate == "code" and &1.is_error))

      assert code_error
      assert code_error.result =~ "[REDACTED]"
      refute code_error.result =~ "VeqpnxccDQtWXwhtUgtJXFDF"
      refute code_error.result =~ "lib/cantrip/medium/code/port_child.ex"
    end
  end

  defp tmp_jsonl_path do
    Path.join(
      System.tmp_dir!(),
      "cantrip_redact_jsonl_#{System.unique_integer([:positive])}.jsonl"
    )
  end
end
