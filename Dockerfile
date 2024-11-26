#ARG GO_VERSION=1.19

FROM golang:1.22-alpine AS builder

ARG REVISION

RUN mkdir -p /workspace/

WORKDIR /workspace
#WORKDIR /csr-approver

COPY . .

RUN apk add bash curl gcc musl-dev pkgconfig lld clang

RUN go mod download

RUN export CGO_LDFLAGS="-static -fuse-ld=lld" && \
    export GO_ENABLED="1" && \
    go build -ldflags "-s -w" \
      -tags 'netgo,osusergo,static_build' \
      -a -o ./build/csr-approver ./cmd/csr-approver/*
#	-X github.com/deas/csr-approver/pkg/version.REVISION=$(GIT_COMMIT)

#RUN CGO_ENABLED=0 go build \
#    -ldflags "-s -w -X github.com/deas/csr-approver/pkg/version.REVISION=${REVISION}" \
#    -a -o build/csr-approver cmd/csr-approver/*

FROM alpine:3.20

ARG BUILD_DATE
ARG VERSION
ARG REVISION

LABEL maintainer="deas"

RUN addgroup -S app \
    && adduser -S -G app app \
    && apk --no-cache add \
    ca-certificates curl netcat-openbsd

WORKDIR /home/app

COPY --from=builder /workspace/build/csr-approver .
RUN chown -R app:app ./

USER app

CMD ["./csr-approver"]
