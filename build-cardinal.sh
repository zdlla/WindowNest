#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
ROOT="$PWD"
BUILD="${WINDOW_NEST_BUILD_DIR:-$ROOT/../../work/build}"
if [[ -x "$ROOT/../../work/cargo/bin/cargo" ]]; then
  export RUSTUP_HOME="$ROOT/../../work/rustup"
  export CARGO_HOME="$ROOT/../../work/cargo"
  CARGO="$CARGO_HOME/bin/cargo"
else
  CARGO="${CARGO:-cargo}"
fi
export CARGO_TARGET_DIR="$BUILD/cardinal"
SDK="${WINDOW_NEST_SDK:-/Library/Developer/CommandLineTools/SDKs/MacOSX26.sdk}"
if [[ ! -d "$SDK" ]]; then SDK="$(xcrun --show-sdk-path)"; fi
export SDKROOT="$SDK" MACOSX_DEPLOYMENT_TARGET="${WINDOW_NEST_DEPLOYMENT_TARGET:-14.0}"
TASK_WORKSPACE_ROOT="$(cd "$ROOT/../.." && pwd -P)"
# Encode flags so paths containing spaces cannot split into extra arguments.
TASK_REMAP_FLAGS="--remap-path-prefix=$HOME=/build/user"$'\x1f'"--remap-path-prefix=$TASK_WORKSPACE_ROOT=/build/WindowNest"
export CARGO_ENCODED_RUSTFLAGS="${CARGO_ENCODED_RUSTFLAGS:+$CARGO_ENCODED_RUSTFLAGS$'\x1f'}$TASK_REMAP_FLAGS"
SLICES=()
for ARCH in ${WINDOW_NEST_ARCHS:-arm64 x86_64}; do
  case "$ARCH" in
    arm64) TARGET=aarch64-apple-darwin ;;
    x86_64) TARGET=x86_64-apple-darwin ;;
    *) printf 'Unsupported architecture: %s\n' "$ARCH" >&2; exit 1 ;;
  esac
  "$CARGO" +nightly-2025-12-11 build --release --locked --target "$TARGET" --manifest-path CardinalBridge/Cargo.toml
  SLICES+=("$CARGO_TARGET_DIR/$TARGET/release/windownest-cardinal")
done
mkdir -p Engine
xcrun lipo -create "${SLICES[@]}" -output Engine/WindowNestCardinal
python3 Scripts/engine_fingerprint.py > Engine/source.sha256
printf 'Built Cardinal engine: %s\n' "$ROOT/Engine/WindowNestCardinal"
