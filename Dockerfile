# syntax=docker/dockerfile:1.7
ARG GO_IMAGE=cgr.dev/chainguard/go:latest-dev@sha256:ed70318f7b4f2e4a82e1dbc363f7a13be3a5805081f86ed9d1ec02d2694c222f
ARG RUNTIME_IMAGE=cgr.dev/chainguard/wolfi-base:latest@sha256:8509ee4351a2e501b7f98201f2e2642396e82020c61a589cacdcfe74b9de46c1

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS source
ARG OPERATOR_VERSION=1.65.0
ARG OPERATOR_COMMIT=77c2ee4de53d07267002d6088e75eb7a34e5000d
USER root
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
WORKDIR /src
RUN apk add --no-cache bash openssl \
    && git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v${OPERATOR_VERSION}" \
      https://github.com/jaegertracing/jaeger-operator.git . \
    && test "$(git rev-parse HEAD)" = "${OPERATOR_COMMIT}" \
    && mkdir -p /out \
    && chown 65532:65532 /out
# Upstream v1.65.0 pins Go modules with known vulnerabilities; raise them to fixed releases
# before the tests run.
COPY build/patch-modules.sh /usr/local/bin/patch-modules.sh
RUN --mount=type=cache,id=jaeger-operator-go-mod-root,target=/root/go/pkg/mod,sharing=locked \
    sh /usr/local/bin/patch-modules.sh
# The fixed modules need go >= 1.24 in go.mod, and from Go 1.24 `go test` runs vet's printf check,
# which rejects one debug print in an upstream test (a non-constant format string). Print the
# name as plain text instead; test code only, the operator binary is unchanged.
RUN sed -i 's/fmt\.Printf(v\.(\*batchv1\.CronJob)\.Name)/fmt.Print(v.(*batchv1.CronJob).Name)/' pkg/inventory/cronjob_test.go \
    && grep -q 'fmt\.Print(v\.(\*batchv1\.CronJob)\.Name)' pkg/inventory/cronjob_test.go
USER 65532:65532
ENV HOME=/tmp

FROM source AS tested
ARG SETUP_ENVTEST_VERSION=v0.25.2
ARG ENVTEST_K8S_VERSION=1.30
RUN --mount=type=cache,id=jaeger-operator-go-path-nonroot,target=/tmp/gopath,uid=65532,gid=65532,sharing=locked \
    --mount=type=cache,id=jaeger-operator-go-build-nonroot,target=/tmp/go-build,uid=65532,gid=65532,sharing=locked \
    mkdir -p /tmp/bin \
    && GOPATH=/tmp/gopath GOMODCACHE=/tmp/gopath/pkg/mod GOCACHE=/tmp/go-build GOBIN=/tmp/bin go install \
      "sigs.k8s.io/controller-runtime/tools/setup-envtest@${SETUP_ENVTEST_VERSION}" \
    && assets='' \
    && for attempt in 1 2 3; do \
         assets="$(/tmp/bin/setup-envtest use "${ENVTEST_K8S_VERSION}" --bin-dir /tmp/envtest -p path)" && break; \
         sleep 3; \
       done \
    && test -n "${assets}" \
    && GOPATH=/tmp/gopath GOMODCACHE=/tmp/gopath/pkg/mod GOCACHE=/tmp/go-build \
       KUBEBUILDER_ASSETS="${assets}" go test -p 1 ./...

FROM tested AS build
ARG TARGETOS
ARG TARGETARCH
ARG OPERATOR_VERSION=1.65.0
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
# buildDate is the release commit's date (upstream uses the build time), so rebuilds are reproducible.
RUN --mount=type=cache,id=jaeger-operator-go-path-nonroot,target=/tmp/gopath,uid=65532,gid=65532,sharing=locked \
    --mount=type=cache,id=jaeger-operator-go-build-nonroot,target=/tmp/go-build,uid=65532,gid=65532,sharing=locked \
    v=github.com/jaegertracing/jaeger-operator/pkg/version \
    && date="$(TZ=UTC0 git -c safe.directory=/src show --quiet --date='format-local:%Y-%m-%dT%H:%M:%SZ' --format='%cd' HEAD)" \
    && test -n "${date}" \
    && GOPATH=/tmp/gopath GOMODCACHE=/tmp/gopath/pkg/mod GOCACHE=/tmp/go-build \
      GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" go build -trimpath -buildvcs=false \
      -ldflags "-s -w -buildid= -X ${v}.version=${OPERATOR_VERSION} -X ${v}.buildDate=${date} -X ${v}.defaultJaeger=1.65.0 -X ${v}.defaultAgent=1.62.0" \
      -o /out/jaeger-operator ./main.go

FROM ${RUNTIME_IMAGE}
ARG OPERATOR_VERSION=1.65.0
RUN apk upgrade --no-cache && apk add --no-cache openssl \
    && mkdir -p /tmp/_working_dir \
    && chgrp -R 0 /tmp/_working_dir \
    && chmod -R g=u /tmp/_working_dir
LABEL org.opencontainers.image.title="jaeger-operator" \
      org.opencontainers.image.version="${OPERATOR_VERSION}-patched" \
      org.opencontainers.image.source="https://github.com/jaegertracing/jaeger-operator" \
      org.opencontainers.image.licenses="Apache-2.0"
COPY --from=build --chown=1001:0 --chmod=0555 /out/jaeger-operator /jaeger-operator
COPY --from=build --chown=1001:0 --chmod=0555 /src/scripts/cert_generation.sh /scripts/cert_generation.sh
USER 1001:0
ENTRYPOINT ["/jaeger-operator"]
