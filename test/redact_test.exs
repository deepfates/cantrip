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

  alias Cantrip.Redact

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
end
