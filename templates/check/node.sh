#!/usr/bin/env bash
# Single verification entry point for agents, ship.sh and CI (installed by agent-harness).
# Commands below come from this repo's own tooling; edit them freely, keep the order.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

FORMAT_CMD='npx prettier --check .'
LINT_CMD='npx eslint . --max-warnings 0'
TYPECHECK_CMD='npx tsc --noEmit'
TEST_CMD='npx jest --passWithNoTests'
BUILD_CMD='npm run build --if-present'

step() {
  local name=$1 cmd=$2
  if [[ -z "$cmd" ]]; then
    echo "==> $name: skipped (not configured)"
    return
  fi
  echo "==> $name: $cmd"
  if ! bash -c "$cmd"; then
    echo "✗ check failed at step: $name" >&2
    exit 1
  fi
}

step guardrails scripts/guardrails.sh
step tests-touched scripts/tests-touched.sh
step format "$FORMAT_CMD"
step lint "$LINT_CMD"
step typecheck "$TYPECHECK_CMD"
step test "$TEST_CMD"
step build "$BUILD_CMD"
echo "✓ check passed"
