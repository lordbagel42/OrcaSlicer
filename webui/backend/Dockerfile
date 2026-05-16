# syntax=docker/dockerfile:1
#
# Backend image: Gleam (Wisp/Mist on the BEAM) + the headless OrcaSlicer CLI.
# Build context MUST be the repository root:
#
#   docker build -f webui/backend/Dockerfile -t orca-web-backend .
#
# The OrcaSlicer source build is long (deps + slic3r). README documents an
# optional AppImage fast path.
#
# Gleam + Erlang are installed into the *same* Ubuntu image that built
# orca-slicer, so the BEAM that compiles the app is the BEAM that runs it
# (no OTP-version mismatch) and orca-slicer keeps its native runtime libs.

# ---------------------------------------------------------------------------
# Stage 1 — build the OrcaSlicer binary from this repo (mirrors scripts/Dockerfile)
# ---------------------------------------------------------------------------
FROM docker.io/ubuntu:24.04 AS orca

RUN apt-get update && echo 'debconf debconf/frontend select Noninteractive' \
    | debconf-set-selections
RUN echo deb-src http://archive.ubuntu.com/ubuntu \
    $(cat /etc/*release | grep VERSION_CODENAME | cut -d= -f2) main universe \
    >> /etc/apt/sources.list

COPY ./ /OrcaSlicer
WORKDIR /OrcaSlicer

RUN ./build_linux.sh -u
RUN ./build_linux.sh -dr
RUN ./build_linux.sh -sr
RUN ./build_linux.sh -ir
# Binary now at /OrcaSlicer/build/package/bin/orca-slicer

# ---------------------------------------------------------------------------
# Stage 2 — runtime: same image + Erlang + Gleam, compile and run the backend
# ---------------------------------------------------------------------------
FROM orca AS runtime

ARG GLEAM_VERSION=v1.11.0
# Build hosts are amd64; for arm64 override with the matching release asset.
ARG GLEAM_ARCH=x86_64-unknown-linux-musl

RUN apt-get update && apt-get install -y --no-install-recommends \
        erlang-nox erlang-dev xvfb curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN curl -fsSL \
      "https://github.com/gleam-lang/gleam/releases/download/${GLEAM_VERSION}/gleam-${GLEAM_VERSION}-${GLEAM_ARCH}.tar.gz" \
      | tar -xz -C /usr/local/bin gleam \
    && gleam --version

# orca-slicer may touch GL for thumbnails; xvfb gives it a virtual display.
RUN printf '#!/bin/sh\nexec xvfb-run -a /OrcaSlicer/build/package/bin/orca-slicer "$@"\n' \
        > /usr/local/bin/orca-slicer-headless \
    && chmod +x /usr/local/bin/orca-slicer-headless

WORKDIR /srv/backend
COPY webui/backend/gleam.toml ./
COPY webui/backend/src ./src
COPY webui/backend/test ./test
RUN gleam deps download && gleam build

ENV ORCA_BIN=/usr/local/bin/orca-slicer-headless \
    ORCA_PROFILES_DIR=/OrcaSlicer/resources/profiles \
    ORCA_WORK_DIR=/tmp/orca \
    PORT=8080
EXPOSE 8080

CMD ["gleam", "run"]
