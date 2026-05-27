#!/usr/bin/env bash
set -euo pipefail

# Ensure signer policy docs exist
[[ -f docs/signer-key-runbook.md ]] || {
  echo "missing docs/signer-key-runbook.md"
  exit 1
}

# Ensure signer verification is covered in tests
if ! grep -E -n "allow_compile_signers|signature verification" test/hot_reload_test.exs >/dev/null; then
  echo "missing signer verification coverage in test/hot_reload_test.exs"
  exit 1
fi

# Basic guard: do not commit obvious private key material
if grep -R -E -n \
  --exclude-dir=.git \
  --exclude-dir=deps \
  --exclude-dir=_build \
  "BEGIN (RSA |EC |OPENSSH )?PRIVATE KEY" . >/dev/null; then
  echo "private key material detected in repository"
  exit 1
fi

echo "signer policy checks passed"
