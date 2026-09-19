#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEVICE="${1:-${ANDROID_DEVICE_ID:-}}"

if [[ -z "$DEVICE" ]]; then
  if [[ -n "${EMULATOR_PORT:-}" ]]; then
    DEVICE="emulator-${EMULATOR_PORT}"
  else
    echo "Usage: $0 <adb-device-id>" >&2
    exit 1
  fi
fi

export PRESSURE_PLATE_SCREENSHOT_DIR="$ROOT/docs/screenshots"

rm -rf "$PRESSURE_PLATE_SCREENSHOT_DIR"
mkdir -p "$PRESSURE_PLATE_SCREENSHOT_DIR"

cd "$ROOT/app"

flutter drive \
  --driver=test_driver/integration_test.dart \
  --target=integration_test/screenshot_test.dart \
  -d "$DEVICE"

for screenshot in overview availability controls; do
  file="$PRESSURE_PLATE_SCREENSHOT_DIR/$screenshot.png"
  if [[ ! -s "$file" ]]; then
    echo "Missing generated screenshot: $file" >&2
    exit 1
  fi
done

echo "Generated screenshots in $PRESSURE_PLATE_SCREENSHOT_DIR"
