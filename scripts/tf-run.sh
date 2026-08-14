#!/usr/bin/env bash
#
# Run a terraform command, retrying the transient errors Object Storage returns
# on state access.
#
#   tf-run.sh plan -out .planfile -input=false
#
# BucketNotFound (a 404 for a bucket that exists) and NotAuthenticated (a 401
# while a freshly created API key propagates) both arrive spuriously, on maybe
# one call in five, and both are gone on the next attempt. Everything else fails
# immediately.
#
# An apply is only retried when it failed *before touching anything*: once
# Terraform has started creating, modifying or destroying, a rerun is a
# decision for a human, not for this script.

set -euo pipefail

log=$(mktemp)
trap 'rm -f "$log"' EXIT

for attempt in 1 2 3; do
  set +e
  terraform "$@" 2>&1 | tee "$log"
  rc=${PIPESTATUS[0]}
  set -e

  [ "$rc" -eq 0 ] && exit 0
  grep -qE "BucketNotFound|NotAuthenticated" "$log" || exit "$rc"

  # Terraform prefixes progress lines with the resource address and a colon.
  # Keep the address pattern dumb — a bracket expression here needs `]` escaped
  # in a way grep does not support, and quietly stops matching.
  if grep -qE "^[^[:space:]]+: (Creating|Modifying|Destroying|Still)" "$log"; then
    echo "state error after resource work had started — not retrying" >&2
    exit "$rc"
  fi

  echo "transient Object Storage error (attempt $attempt/3) — retrying" >&2
  sleep 5
done

exit 1
