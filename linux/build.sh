#!/bin/sh
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
profile=${1:-release}
case "$profile" in
    release) release=--release ;;
    debug) release= ;;
    *) echo 'Usage: linux/build.sh [release|debug]' >&2; exit 64 ;;
esac
cargo build --locked $release --manifest-path "$repo/linux/Cargo.toml" --target-dir "$repo/.build/linux-rust"
mkdir -p "$repo/.build/$profile"
cp "$repo/.build/linux-rust/$profile/blindly4" "$repo/.build/$profile/blindly4"
