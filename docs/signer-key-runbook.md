# Signer Key Runbook (`allow_compile_signers`)

This runbook defines how to manage compile signer keys for `compile_and_load`.

## 1) Threat Model

`allow_compile_signers` is used to ensure hot-loaded source is authorized by a trusted signer.

Ward enforcement flow:
1. Caller provides `key_id` and `signature`.
2. Circle finds `key_id` in `allow_compile_signers`.
3. Signature is verified over `source` bytes with that public key.
4. Compile proceeds only on successful verification.

## 2) Key Generation (RSA example)

Generate private/public keypair (OpenSSL):

```bash
openssl genrsa -out cantrip_signer_private.pem 2048
openssl rsa -in cantrip_signer_private.pem -pubout -out cantrip_signer_public.pem
```

Keep private keys out of the repo.

## 3) Signing Flow

Create detached signature (base64):

```bash
openssl dgst -sha256 -sign cantrip_signer_private.pem source.ex \
  | base64 > source.sig.b64
```

Gate args should include:
1. `module`
2. `source`
3. `key_id`
4. `signature` (base64)

## 4) Circle Configuration

Configure trusted public keys by `key_id`:

```elixir
%{
  gates: [:done, :compile_and_load],
  wards: [
    %{max_turns: 10},
    %{allow_compile_modules: ["Elixir.My.Module"]},
    %{
      allow_compile_signers: %{
        "dev-key-1" => File.read!("cantrip_signer_public.pem")
      }
    }
  ]
}
```

## 5) Rotation

1. Add new key with a new `key_id` alongside current key.
2. Start signing new artifacts with the new private key.
3. Observe successful verification in environments.
4. Remove old `key_id` after migration window.

## 6) Incident Response

If private key compromise is suspected:
1. Remove compromised `key_id` from wards immediately.
2. Rotate to new keypair.
3. Re-sign trusted source with replacement key.
4. Audit prior compile events in loom storage.
