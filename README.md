# Jaeger Operator hardened source build

The final upstream Jaeger Operator release, 1.65.0, rebuilt from its verified source
commit with a current Chainguard Go toolchain and Wolfi runtime. Published as
`mohankrishna999/jaeger-operator:1.65.0-patched` for amd64 and arm64.

The 1.65.0 release pins Go modules with known vulnerabilities. `build/patch-modules.sh`
raises them to the newest release in the same major version before the upstream tests run,
and the build fails if a pin does not apply:

| Module | Upstream 1.65.0 | `1.65.0-patched` |
|---|---|---|
| `github.com/klauspost/compress` | 1.17.9 | 1.20.3 |
| `go.opentelemetry.io/otel/sdk` | 1.32.0 | 1.47.0 |
| `golang.org/x/net` | 0.33.0 | 0.62.0 |
| `golang.org/x/oauth2` | 0.23.0 | 0.37.0 |
| `golang.org/x/sys` | 0.28.0 | 0.49.0 |
| `golang.org/x/text` | 0.21.0 | 0.43.0 |

The official 1.65.0 image was built with Go 1.22.3; this one uses the current Go toolchain,
so the Go standard library findings of the official image do not apply.

The upstream unit tests run during the build, against the raised modules. The fixed modules
need `go 1.24` or later in `go.mod`, which turns on `go vet`'s printf check during `go test`;
one debug print in `pkg/inventory/cronjob_test.go` fails it, so the build prints that value as
plain text. Only test code changes; the operator binary does not.

`jaeger-operator version` reports the same version, Jaeger and agent defaults as the official
image. Its `build-date` is the release commit's date rather than the build time, so rebuilds
from the same source are reproducible.

Jaeger Operator is a legacy v1 component. New Jaeger v2 installations should normally
use the Jaeger v2 Kubernetes or OpenTelemetry Operator deployment model. This image is
provided for clusters that still depend on Jaeger v1 custom resources.

The runtime uses primary GID 0 and group-writable runtime paths for OpenShift arbitrary
UID compatibility. CI builds, tests, and scans weekly with both Trivy and Grype.
