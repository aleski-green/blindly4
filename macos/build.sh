#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
profile=${1:-release}
case "$profile" in
  release) release=--release ;;
  debug) release= ;;
  *) echo 'Usage: macos/build.sh [release|debug]' >&2; exit 64 ;;
esac
export MACOSX_DEPLOYMENT_TARGET=13.0
cargo build $release --manifest-path "$repo/macos/Cargo.toml" --target-dir "$repo/.build/macos-rust"
mkdir -p "$repo/.build/$profile"
cp "$repo/.build/macos-rust/$profile/blindly4" "$repo/.build/$profile/blindly4"
printf 'Blindly4: %s\n' "$repo/.build/$profile/blindly4"
