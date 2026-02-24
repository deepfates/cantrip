#!/usr/bin/env bash
set -euo pipefail

# Ensure signer policy docs exist
[[ -f SIGNER_KEY_RUNBOOK.md ]] || {
  echo "missing SIGNER_KEY_RUNBOOK.md"
  exit 1
}

# Ensure signer verification is covered in tests
if ! rg -n "allow_compile_signers|signature verification" test/m7_hot_reload_test.exs >/dev/null; then
  echo "missing signer verification coverage in test/m7_hot_reload_test.exs"
  exit 1
fi

# Basic guard: do not commit obvious private key material
if rg -n --glob '!deps/**' --glob '!_build/**' "BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY" . >/dev/null; then
  echo "private key material detected in repository"
  exit 1
fi

echo "signer policy checks passed"
