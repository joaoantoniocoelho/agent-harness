#!/usr/bin/env bash
# Single verification entry point for agents, ship.sh and CI (installed by agent-harness).
# Commands below come from this repo's own tooling; edit them freely, keep the order.
set -euo pipefail

cd "$(git rev-parse --show-toplevel)"

# Xcode project settings (filled by /harness-init).
SCHEME='CHANGE_ME'
DESTINATION='platform=iOS Simulator,name=iPhone 16'
export SCHEME DESTINATION

FORMAT_CMD='swift format lint --recursive --strict .'
LINT_CMD='swiftlint lint --strict --quiet'
TYPECHECK_CMD=''
TEST_CMD='xcodebuild build test -scheme "$SCHEME" -destination "$DESTINATION" -quiet'
BUILD_CMD=''

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
