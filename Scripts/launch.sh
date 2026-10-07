#!/usr/bin/env bash
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
if [[ ! -x "$ROOT/MacPulse.app/Contents/MacOS/MacPulse" ]]; then
  "$ROOT/Scripts/package_app.sh"
fi
open "$ROOT/MacPulse.app"
