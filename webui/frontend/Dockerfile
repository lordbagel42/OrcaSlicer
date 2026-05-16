# syntax=docker/dockerfile:1
#
# Frontend image: build the Lustre SPA to static JS, serve it with Caddy.
# Caddy also reverse-proxies /api and /files to the backend so the browser
# talks to a single origin (no CORS needed in normal operation).
#
# Build context: webui/frontend

FROM ghcr.io/gleam-lang/gleam:v1.11.0-erlang-alpine AS build
RUN apk add --no-cache nodejs npm
WORKDIR /build
COPY gleam.toml ./
COPY src ./src
COPY index.html ./
RUN gleam deps download
RUN gleam run -m lustre/dev build app --minify

FROM docker.io/caddy:2-alpine AS runtime
COPY --from=build /build/index.html /srv/index.html
COPY --from=build /build/priv/static /srv/priv/static
COPY Caddyfile /etc/caddy/Caddyfile
EXPOSE 80
