defmodule Cantrip.Familiar.Cookie do
  @moduledoc false

  @cookie_re ~r/\Acantrip_[0-9a-f]{48}\z/

  @doc false
  @spec random() :: atom()
  def random do
    suffix = :crypto.strong_rand_bytes(24) |> Base.encode16(case: :lower)
    String.to_atom("cantrip_" <> suffix)
  end

  @doc false
  @spec for_workspace!(Path.t()) :: atom()
  def for_workspace!(root) when is_binary(root) do
    # Existing files must already be in Cantrip's generated format. That keeps
    # atom creation bounded and prevents silent rotation of an operator
    # credential that other distributed nodes may still rely on.
    cookie_path = Path.join([root, ".cantrip", "cookie"])

    case File.read(cookie_path) do
      {:ok, existing} when byte_size(existing) > 0 ->
        existing
        |> String.trim()
        |> validate_existing!(cookie_path)

      _ ->
        generate!(cookie_path)
    end
  end

  defp validate_existing!(cookie, cookie_path) do
    if Regex.match?(@cookie_re, cookie) do
      String.to_atom(cookie)
    else
      raise ArgumentError, """
      Cantrip cookie at #{cookie_path} does not match the expected format.

      Refusing to overwrite an existing distributed-Erlang cookie because
      doing so would break nodes that still authenticate with the old value.
      Delete the cookie file explicitly if you want Cantrip to generate a new
      workspace cookie.
      """
    end
  end

  defp generate!(cookie_path) do
    cookie =
      "cantrip_" <>
        (:crypto.strong_rand_bytes(24) |> Base.encode16(case: :lower))

    File.mkdir_p!(Path.dirname(cookie_path))
    File.write!(cookie_path, cookie)
    File.chmod(cookie_path, 0o600)
    String.to_atom(cookie)
  end
end
