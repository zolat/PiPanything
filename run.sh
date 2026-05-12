#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

xcodegen generate
xcodebuild -scheme PiPanything -configuration Debug build

APP=$(xcodebuild -showBuildSettings -scheme PiPanything 2>/dev/null \
  | awk -F' = ' '/^[[:space:]]+BUILT_PRODUCTS_DIR = / {print $2}')

exec "$APP/PiPanything.app/Contents/MacOS/PiPanything" "$@"
