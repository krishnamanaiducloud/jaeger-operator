# Jaeger Operator hardened source build

The final upstream Jaeger Operator release, 1.65.0, rebuilt from its verified source
commit with a current Chainguard Go toolchain and Wolfi runtime. Published as
`mohankrishna999/jaeger-operator:1.65.0-patched` for amd64 and arm64.

Jaeger Operator is a legacy v1 component. New Jaeger v2 installations should normally
use the Jaeger v2 Kubernetes or OpenTelemetry Operator deployment model. This image is
provided for clusters that still depend on Jaeger v1 custom resources.

The runtime uses primary GID 0 and group-writable runtime paths for OpenShift arbitrary
UID compatibility. CI builds, tests, and scans weekly with both Trivy and Grype.
