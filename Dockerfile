# syntax=docker/dockerfile:1.7
ARG GO_IMAGE=cgr.dev/chainguard/go:latest-dev@sha256:c33b2ae1b183ff001b7f2c29936c587ce1cd4ffaf9efb031bd81240f16a96504
ARG RUNTIME_IMAGE=cgr.dev/chainguard/wolfi-base:latest@sha256:fd50bd0cdeb808cf4f45c9c9189e0cc7f7fcc27195d69abd6622c80527e7e021

FROM --platform=$BUILDPLATFORM ${GO_IMAGE} AS source
ARG OPERATOR_VERSION=1.65.0
ARG OPERATOR_COMMIT=77c2ee4de53d07267002d6088e75eb7a34e5000d
USER root
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
WORKDIR /src
RUN git -c advice.detachedHead=false clone --quiet --depth 1 --branch "v${OPERATOR_VERSION}" \
      https://github.com/jaegertracing/jaeger-operator.git . \
    && test "$(git rev-parse HEAD)" = "${OPERATOR_COMMIT}"

FROM source AS tested
RUN --mount=type=cache,id=jaeger-operator-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=jaeger-operator-go-build,target=/root/.cache/go-build,sharing=locked \
    go test ./...

FROM tested AS build
ARG TARGETOS
ARG TARGETARCH
ARG OPERATOR_VERSION=1.65.0
ENV CGO_ENABLED=0 GOTOOLCHAIN=local
RUN --mount=type=cache,id=jaeger-operator-go-mod,target=/root/go/pkg/mod,sharing=locked \
    --mount=type=cache,id=jaeger-operator-go-build,target=/root/.cache/go-build,sharing=locked \
    GOOS="${TARGETOS}" GOARCH="${TARGETARCH}" go build -trimpath -buildvcs=false \
      -ldflags "-s -w -buildid= -X github.com/jaegertracing/jaeger-operator/pkg/version.version=${OPERATOR_VERSION} -X github.com/jaegertracing/jaeger-operator/pkg/version.defaultJaeger=1.65.0 -X github.com/jaegertracing/jaeger-operator/pkg/version.defaultAgent=1.62.0" \
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
