#!/bin/bash
# Build Kiri's static Linux engine (kiri, kiri-init) from a checkout, in a Rust container.
# Usage: scripts/build-kiri-linux.sh <kiri checkout> <output dir>
# Same as `cargo xtask linux --arch amd64`, without needing cargo on the host.
set -eu
SRC=$(cd "$1" && pwd); OUT=$2
mkdir -p "$OUT"
docker run --rm -v "$SRC":/src -v kiri-cargo-registry:/usr/local/cargo/registry -w /src \
  -e CARGO_TARGET_DIR=/src/target/linux-x86_64 rust:1-alpine \
  sh -c 'apk add -q musl-dev && cargo build --release -p kiri -p kiri-init'
cp "$SRC"/target/linux-x86_64/release/kiri "$SRC"/target/linux-x86_64/release/kiri-init "$OUT"/
ls -la "$OUT"
