#!/bin/sh
# Raise the Go modules with known vulnerabilities in upstream Jaeger Operator v1.65.0 to their fixed releases.
# Run inside the upstream source tree.
set -eu

# Retry transient module proxy and checksum database failures.
retry() {
  attempt=1
  until "$@"; do
    if [ "$attempt" -ge 4 ]; then
      return 1
    fi
    echo "Command failed (attempt $attempt), retrying: $*" >&2
    sleep $((attempt * 5))
    attempt=$((attempt + 1))
  done
}

PINS="github.com/klauspost/compress@v1.20.3 go.opentelemetry.io/otel/sdk@v1.47.0 golang.org/x/net@v0.62.0 golang.org/x/oauth2@v0.37.0 golang.org/x/sys@v0.49.0 golang.org/x/text@v0.43.0"

# shellcheck disable=SC2086
retry go get $PINS
retry go mod tidy

# Fail the build if any pin was not applied.
for pin in $PINS; do
  module=${pin%@*}
  want=${pin#*@}
  have=$(go list -m -f '{{.Version}}' "$module")
  if [ "$have" != "$want" ]; then
    echo "module $module is $have, want $want" >&2
    exit 1
  fi
done
