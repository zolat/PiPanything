#!/usr/bin/env bash
# Build pipanythingctl and copy it into the PiPanything.app bundle's
# Resources directory. Invoked from project.yml as a postCompileScripts
# phase on the PiPanything target.
#
# - Release configuration → universal binary (aarch64 + x86_64, lipo'd).
# - Debug configuration   → host arch only (fast dev iteration).
#
# Xcode build phases run with a sparse PATH; we probe common cargo
# locations rather than assuming `cargo` is on PATH.

set -euo pipefail

: "${SRCROOT:?SRCROOT must be set (run this from an Xcode build phase)}"
: "${TARGET_BUILD_DIR:?TARGET_BUILD_DIR must be set}"
: "${PRODUCT_NAME:?PRODUCT_NAME must be set}"
: "${CONFIGURATION:?CONFIGURATION must be set}"

CLI_DIR="${SRCROOT}/pipanythingctl"
OUT_DIR="${TARGET_BUILD_DIR}/${PRODUCT_NAME}.app/Contents/Resources"
OUT_BIN="${OUT_DIR}/pipanythingctl"

mkdir -p "$OUT_DIR"

CARGO="${CARGO:-}"
if [ -z "$CARGO" ]; then
    for candidate in \
        "$HOME/.cargo/bin/cargo" \
        "/opt/homebrew/bin/cargo" \
        "/opt/homebrew/opt/rustup/bin/cargo" \
        "/usr/local/bin/cargo"; do
        if [ -x "$candidate" ]; then
            CARGO="$candidate"
            break
        fi
    done
fi

if [ -z "$CARGO" ] || [ ! -x "$CARGO" ]; then
    echo "error: cargo not found. Install rustup (https://rustup.rs) or 'brew install rustup'." >&2
    exit 1
fi

cd "$CLI_DIR"

build_arch() {
    local target="$1"
    "$CARGO" build --release --target "$target" --quiet
}

case "$CONFIGURATION" in
    Release)
        build_arch aarch64-apple-darwin
        build_arch x86_64-apple-darwin
        lipo -create \
            "target/aarch64-apple-darwin/release/pipanythingctl" \
            "target/x86_64-apple-darwin/release/pipanythingctl" \
            -output "$OUT_BIN"
        ;;
    *)
        case "$(uname -m)" in
            arm64)  HOST_TARGET=aarch64-apple-darwin ;;
            x86_64) HOST_TARGET=x86_64-apple-darwin ;;
            *) echo "error: unknown host arch: $(uname -m)" >&2; exit 1 ;;
        esac
        build_arch "$HOST_TARGET"
        cp "target/$HOST_TARGET/release/pipanythingctl" "$OUT_BIN"
        ;;
esac

echo "pipanythingctl bundled at $OUT_BIN ($(file -b "$OUT_BIN"))"
