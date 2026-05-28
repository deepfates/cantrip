defmodule Cantrip.HotReloadTest do
  use ExUnit.Case, async: true

  alias Cantrip.FakeLLM

  test "compile_and_load requires an explicit module allowlist" do
    module_name = "Elixir.Cantrip.HotReloadNoAllow"

    obs =
      Cantrip.Gate.CompileAndLoad.execute(
        %{module: module_name, source: "defmodule Cantrip.HotReloadNoAllow do end"},
        [%{max_turns: 1}],
        %{name: "compile_and_load"}
      )

    assert obs.is_error
    assert obs.result =~ "requires allow_compile_modules or allow_compile_namespaces"
  end

  test "hot-reload gate compiles and reloads allowed module" do
    module_name = "Elixir.Cantrip.HotReloadDemo"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.HotReloadDemo do
      def version, do: 2
    end
    """

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{gate: "compile_and_load", args: %{module: module_name, source: source}},
             %{gate: "done", args: %{answer: "ok"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [%{max_turns: 10}, %{allow_compile_modules: [module_name]}]
        }
      )

    assert {:ok, "ok", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "reload")
    assert apply(module, :version, []) == 2

    assert Enum.any?(
             hd(loom.turns).observation,
             &(&1.gate == "compile_and_load" and not &1.is_error)
           )

    purge_module(module)
  end

  test "hot-reload gate accepts modules in an allowed namespace" do
    # The Familiar uses namespace prefixes rather than exact allowlists
    # so it can write new modules at runtime as long as they live in a
    # scoped sub-tree (e.g., `Cantrip.Hot.*`) without redefining core
    # framework modules.
    module_name = "Elixir.Cantrip.Hot.SafeNs"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.Hot.SafeNs do
      def version, do: 7
    end
    """

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{gate: "compile_and_load", args: %{module: module_name, source: source}},
             %{gate: "done", args: %{answer: "loaded"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 10},
            %{allow_compile_namespaces: ["Elixir.Cantrip.Hot."]}
          ]
        }
      )

    assert {:ok, "loaded", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "namespace ok")

    assert Enum.any?(loom.turns, fn turn ->
             Enum.any?(turn.observation, &(&1.gate == "compile_and_load" and not &1.is_error))
           end)

    purge_module(module)
  end

  test "hot-reload gate rejects modules outside the allowed namespace" do
    module_name = "Elixir.Cantrip.Familiar"

    source = """
    defmodule Cantrip.Familiar do
      def version, do: 666
    end
    """

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{gate: "compile_and_load", args: %{module: module_name, source: source}},
             %{gate: "done", args: %{answer: "blocked"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 10},
            %{allow_compile_namespaces: ["Elixir.Cantrip.Hot."]}
          ]
        }
      )

    assert {:ok, "blocked", _cantrip, loom, _meta} =
             Cantrip.cast(cantrip, "namespace blocks Familiar redefinition")

    [turn] = loom.turns
    [obs | _] = turn.observation
    assert obs.is_error
    assert obs.result =~ "module not allowed"
  end

  test "hot-reload gate rejects non-warded modules" do
    module_name = "Elixir.Cantrip.ForbiddenReload"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.ForbiddenReload do
      def version, do: 1
    end
    """

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{gate: "compile_and_load", args: %{module: module_name, source: source}},
             %{gate: "done", args: %{answer: "blocked"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [%{max_turns: 10}, %{allow_compile_modules: ["Elixir.Cantrip.AllowedOnly"]}]
        }
      )

    assert {:ok, "blocked", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "reject")
    [turn] = loom.turns
    [obs | _] = turn.observation
    assert obs.is_error
    assert obs.result =~ "module not allowed"
    purge_module(module)
  end

  test "hot-reload gate rejects non-warded compile paths" do
    module_name = "Elixir.Cantrip.PathDeniedReload"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.PathDeniedReload do
      def version, do: 9
    end
    """

    denied_path = Path.join(System.tmp_dir!(), "cantrip_denied/path_denied_reload.ex")
    allowed_root = Path.join(System.tmp_dir!(), "cantrip_allowed")

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{
               gate: "compile_and_load",
               args: %{module: module_name, source: source, path: denied_path}
             },
             %{gate: "done", args: %{answer: "blocked"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 10},
            %{allow_compile_modules: [module_name]},
            %{allow_compile_paths: [allowed_root]}
          ]
        }
      )

    assert {:ok, "blocked", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "reject path")
    [turn] = loom.turns
    [obs | _] = turn.observation
    assert obs.is_error
    assert obs.result =~ "path not allowed"
    purge_module(module)
  end

  test "hot-reload gate rejects sibling paths that only share a prefix with allowed root" do
    module_name = "Elixir.Cantrip.PathPrefixDeniedReload"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.PathPrefixDeniedReload do
      def version, do: 11
    end
    """

    allowed_root = Path.join(System.tmp_dir!(), "cantrip_allowed")

    denied_path =
      Path.join(System.tmp_dir!(), "cantrip_allowed_evil/path_prefix_denied_reload.ex")

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{
               gate: "compile_and_load",
               args: %{module: module_name, source: source, path: denied_path}
             },
             %{gate: "done", args: %{answer: "blocked"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 10},
            %{allow_compile_modules: [module_name]},
            %{allow_compile_paths: [allowed_root]}
          ]
        }
      )

    assert {:ok, "blocked", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "reject prefixed path")
    [turn] = loom.turns
    [obs | _] = turn.observation
    assert obs.is_error
    assert obs.result =~ "path not allowed"
    purge_module(module)
  end

  test "code-circle can hot-reload via compile_and_load host function" do
    module_name = "Elixir.Cantrip.HotReloadFromCode"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.HotReloadFromCode do
      def value, do: 7
    end
    """

    code = """
    compile_and_load.(%{module: "#{module_name}", source: #{inspect(source)}})
    done.(Cantrip.HotReloadFromCode.value())
    """

    llm = {FakeLLM, FakeLLM.new([%{code: code}])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :code,
          gates: [:done, :compile_and_load],
          wards: [%{max_turns: 10}, %{allow_compile_modules: [module_name]}]
        }
      )

    assert {:ok, 7, _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "code reload")
    purge_module(module)
  end

  test "failed hot reload keeps the previous module and does not overwrite the file" do
    suffix = System.unique_integer([:positive])
    module_name = "Elixir.Cantrip.Hot.SafeReload#{suffix}"
    bare_module = String.replace_prefix(module_name, "Elixir.", "")
    module = String.to_atom(module_name)
    purge_module(module)

    path =
      Path.join(
        System.tmp_dir!(),
        "cantrip_safe_reload_#{suffix}/safe_reload.ex"
      )

    good_source = """
    defmodule #{bare_module} do
      def value, do: :old
    end
    """

    bad_source = """
    defmodule #{bare_module} do
      def value, do:
    end
    """

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{
               gate: "compile_and_load",
               args: %{module: module_name, source: good_source, path: path}
             },
             %{
               gate: "compile_and_load",
               args: %{module: module_name, source: bad_source, path: path}
             },
             %{gate: "done", args: %{answer: "checked"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 10},
            %{allow_compile_modules: [module_name]},
            %{allow_compile_paths: [Path.dirname(path)]}
          ]
        }
      )

    assert {:ok, "checked", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "safe reload")

    observations = hd(loom.turns).observation
    assert Enum.any?(observations, &(&1.gate == "compile_and_load" and not &1.is_error))
    assert Enum.any?(observations, &(&1.gate == "compile_and_load" and &1.is_error))
    assert apply(module, :value, []) == :old
    assert File.read!(path) == good_source

    File.rm_rf!(Path.dirname(path))
    purge_module(module)
  end

  test "hot-reload gate enforces source sha256 allowlist when configured" do
    module_name = "Elixir.Cantrip.SignedReload"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.SignedReload do
      def version, do: 3
    end
    """

    sha256 = :crypto.hash(:sha256, source) |> Base.encode16(case: :lower)

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{
               gate: "compile_and_load",
               args: %{module: module_name, source: source, sha256: sha256}
             },
             %{gate: "done", args: %{answer: "ok"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 10},
            %{allow_compile_modules: [module_name]},
            %{allow_compile_sha256: [sha256]}
          ]
        }
      )

    assert {:ok, "ok", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "signed reload")
    assert apply(module, :version, []) == 3
    purge_module(module)
  end

  test "hot-reload gate rejects source when sha256 mismatches source" do
    module_name = "Elixir.Cantrip.SignedMismatch"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.SignedMismatch do
      def version, do: 4
    end
    """

    wrong_sha = :crypto.hash(:sha256, "different source") |> Base.encode16(case: :lower)

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{
               gate: "compile_and_load",
               args: %{module: module_name, source: source, sha256: wrong_sha}
             },
             %{gate: "done", args: %{answer: "blocked"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 10},
            %{allow_compile_modules: [module_name]},
            %{allow_compile_sha256: [wrong_sha]}
          ]
        }
      )

    assert {:ok, "blocked", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "reject bad hash")
    [turn] = loom.turns
    [obs | _] = turn.observation
    assert obs.is_error
    assert obs.result =~ "sha256 mismatch"
    purge_module(module)
  end

  test "hot-reload gate accepts valid signature from allowlisted signer" do
    module_name = "Elixir.Cantrip.SignedByKey"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.SignedByKey do
      def version, do: 5
    end
    """

    {private_key, public_key_pem} = signer_keypair()
    signature = Base.encode64(:public_key.sign(source, :sha256, private_key))

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{
               gate: "compile_and_load",
               args: %{
                 module: module_name,
                 source: source,
                 key_id: "dev-key-1",
                 signature: signature
               }
             },
             %{gate: "done", args: %{answer: "ok"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 10},
            %{allow_compile_modules: [module_name]},
            %{allow_compile_signers: %{"dev-key-1" => public_key_pem}}
          ]
        }
      )

    assert {:ok, "ok", _cantrip, _loom, _meta} = Cantrip.cast(cantrip, "signed compile")
    assert apply(module, :version, []) == 5
    purge_module(module)
  end

  test "hot-reload gate rejects compile when signature verification fails" do
    module_name = "Elixir.Cantrip.SignedInvalid"
    module = String.to_atom(module_name)
    purge_module(module)

    source = """
    defmodule Cantrip.SignedInvalid do
      def version, do: 6
    end
    """

    {private_key, public_key_pem} = signer_keypair()
    bad_signature = Base.encode64(:public_key.sign("different source", :sha256, private_key))

    llm =
      {FakeLLM,
       FakeLLM.new([
         %{
           tool_calls: [
             %{
               gate: "compile_and_load",
               args: %{
                 module: module_name,
                 source: source,
                 key_id: "dev-key-1",
                 signature: bad_signature
               }
             },
             %{gate: "done", args: %{answer: "blocked"}}
           ]
         }
       ])}

    {:ok, cantrip} =
      Cantrip.new(
        llm: llm,
        circle: %{
          type: :conversation,
          gates: [:done, :compile_and_load],
          wards: [
            %{max_turns: 10},
            %{allow_compile_modules: [module_name]},
            %{allow_compile_signers: %{"dev-key-1" => public_key_pem}}
          ]
        }
      )

    assert {:ok, "blocked", _cantrip, loom, _meta} = Cantrip.cast(cantrip, "bad signature")
    [turn] = loom.turns
    [obs | _] = turn.observation
    assert obs.is_error
    assert obs.result =~ "signature verification failed"
    purge_module(module)
  end

  defp purge_module(module) do
    :code.purge(module)
    :code.delete(module)
  end

  defp signer_keypair do
    private_key = :public_key.generate_key({:rsa, 1024, 65_537})

    {:RSAPrivateKey, :"two-prime", modulus, public_exp, _private_exp, _p1, _p2, _exp1, _exp2,
     _coef, _other} = private_key

    public_key = {:RSAPublicKey, modulus, public_exp}
    pem = :public_key.pem_encode([:public_key.pem_entry_encode(:RSAPublicKey, public_key)])
    {private_key, pem}
  end
end
