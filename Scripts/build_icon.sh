#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
swift "$ROOT/Scripts/GenerateIcon.swift" "$ROOT/artifacts/MacPulse.iconset"
iconutil --convert icns --output "$ROOT/Icon.icns" "$ROOT/artifacts/MacPulse.iconset"
