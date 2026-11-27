# syntax=docker/dockerfile:1
FROM golang:1.27.4-alpine3.24 AS build
WORKDIR /src
COPY . .
ARG VERSION=dev
RUN CGO_ENABLED=0 go build -trimpath -ldflags "-s -w -X main.version=${VERSION}" -o /out/pulse-agent ./cmd/pulse-agent

FROM gcr.io/distroless/static-debian12:nonroot
COPY --from=build /out/pulse-agent /pulse-agent
USER nonroot:nonroot
EXPOSE 9123
HEALTHCHECK --interval=30s --timeout=5s --start-period=10s CMD ["/pulse-agent", "--healthcheck"]
ENTRYPOINT ["/pulse-agent"]
