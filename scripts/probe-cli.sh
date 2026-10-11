#!/usr/bin/env bash
# Upgrade diagnostics only. Exit codes are printed, not counted as test successes.
# scripts/test_detections.py remains the actual fail-closed test gate.
set -euo pipefail
if [[ -n "${RUNREVEAL_TOKEN:-}" ]]; then
  printf '%s\n' 'Remove any real RUNREVEAL_TOKEN before this local-only probe.' >&2
  exit 2
fi
cli="${1:-.tools/runreveal}"
export RUNREVEAL_TOKEN='offline-fixture-not-a-credential'
export RUNREVEAL_WORKSPACE='offline-validation'
export RUNREVEAL_BASEURL='http://127.0.0.1:1'
export RUNREVEAL_PROFILE='offline-probe-no-authentication'
export XDG_CONFIG_HOME
XDG_CONFIG_HOME="$(mktemp -d)"

probe() {
  printf '\nDiagnostic command:'
  printf ' %q' "$@"
  printf '\n'
  if timeout 30 "$@"; then
    probe_code=0
  else
    probe_code=$?
  fi
  printf 'Diagnostic exit code: %s (not a test verdict)\n' "$probe_code"
}

probe "$cli" detections sync --help
probe "$cli" detections run --help
probe "$cli" lint sigma detections/sigma
probe "$cli" lint sql detections/sql
probe "$cli" detections run -f detections/sigma/aws-waf-blocked-admin-request.yaml -i fixtures/waf-positive.ndjson
probe "$cli" detections run -f detections/sigma/aws-waf-blocked-admin-request.yaml -i fixtures/waf-negative.ndjson
