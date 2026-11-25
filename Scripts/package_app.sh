#!/usr/bin/env bash
set -euo pipefail
CONF=${1:-release}
ROOT=$(cd "$(dirname "$0")/.." && pwd)
cd "$ROOT"
source "$ROOT/version.env"
SIGNING_MODE=${SIGNING_MODE:-adhoc}
APP_IDENTITY=${APP_IDENTITY:-}
APP_OUTPUT_DIR=${APP_OUTPUT_DIR:-$ROOT}
APP_ENTITLEMENTS=${APP_ENTITLEMENTS:-$ROOT/Resources/MacPulse.entitlements}
SWIFT_BUILD_SYSTEM=${SWIFT_BUILD_SYSTEM:-native}
BUILD_ARGS=(--build-system "$SWIFT_BUILD_SYSTEM" -c "$CONF")
[[ "$CONF" == "debug" || "$CONF" == "release" ]] || { echo 'Configuration must be debug or release.' >&2; exit 1; }
[[ "$SIGNING_MODE" == "adhoc" || "$SIGNING_MODE" == "developer-id" ]] || { echo 'SIGNING_MODE must be adhoc or developer-id.' >&2; exit 1; }
python3 Scripts/package_check.py preflight "$APP_OUTPUT_DIR"
if [[ "$SIGNING_MODE" == "developer-id" ]]; then
  [[ -n "$APP_IDENTITY" ]] || { echo 'Developer ID Application identity is required.' >&2; exit 1; }
  python3 Scripts/package_check.py identity "$APP_IDENTITY"
  CODESIGN_ARGS=(--force --timestamp --options runtime --sign "$APP_IDENTITY")
else
  CODESIGN_ARGS=(--force --sign -)
fi
read -r -a ARCH_LIST <<< "${ARCHES:-$(uname -m)}"
for ARCH in "${ARCH_LIST[@]}"; do
  [[ "$ARCH" == "arm64" || "$ARCH" == "x86_64" ]] || { echo 'Unsupported architecture.' >&2; exit 1; }
done
for ARCH in "${ARCH_LIST[@]}"; do swift build "${BUILD_ARGS[@]}" --arch "$ARCH"; done
mkdir -p "$ROOT/.build" "$APP_OUTPUT_DIR"
STAGE=$(mktemp -d "$ROOT/.build/package-stage.XXXXXX")
trap 'rm -rf -- "$STAGE"' EXIT
APP="$STAGE/$APP_NAME.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
BINARIES=()
for ARCH in "${ARCH_LIST[@]}"; do
  BIN_DIR=$(swift build "${BUILD_ARGS[@]}" --arch "$ARCH" --show-bin-path)
  BINARIES+=("$BIN_DIR/$APP_NAME")
done
if [[ ${#BINARIES[@]} -gt 1 ]]; then lipo -create "${BINARIES[@]}" -output "$APP/Contents/MacOS/$APP_NAME"
else cp "${BINARIES[0]}" "$APP/Contents/MacOS/$APP_NAME"; fi
chmod +x "$APP/Contents/MacOS/$APP_NAME"
python3 Scripts/package_check.py metadata "$APP" "$SIGNING_MODE" "${ARCH_LIST[@]}"
cp -R "Sources/$APP_NAME/Resources/." "$APP/Contents/Resources/"
# The String Catalog ships compiled: en/tr .strings and .stringsdict inside the existing lproj folders.
python3 Scripts/localization.py compile "$APP/Contents/Resources"
rm "$APP/Contents/Resources/Localizable.xcstrings"
cp Icon.icns "$APP/Contents/Resources/Icon.icns"
cp docs/THIRD-PARTY.md "$APP/Contents/Resources/ThirdPartyNotices.md"
BIN_DIR=$(dirname "${BINARIES[0]}")
shopt -s nullglob
for BUNDLE in "$BIN_DIR/"*.bundle; do cp -R "$BUNDLE" "$APP/Contents/Resources/"; done
for FRAMEWORK in "$BIN_DIR/"*.framework; do cp -R "$FRAMEWORK" "$APP/Contents/Frameworks/"; done
shopt -u nullglob
if [[ -n "$(find "$APP/Contents/Frameworks" -mindepth 1 -maxdepth 1 -print -quit)" ]]; then
  install_name_tool -add_rpath '@executable_path/../Frameworks' "$APP/Contents/MacOS/$APP_NAME"
fi
# Local battery readers. No pairing, daemon installation or system permission change.
mkdir -p "$APP/Contents/Resources/bin"
MOBILE_BINARIES=()
WATCH_BINARIES=()
MOBILE_PREFIX=""
for PREFIX in /opt/homebrew /usr/local; do
  if [[ -f "$PREFIX/include/libimobiledevice/companion_proxy.h" ]]; then MOBILE_PREFIX="$PREFIX"; break; fi
done
for ARCH in "${ARCH_LIST[@]}"; do
  clang -fobjc-arc -O2 -arch "$ARCH" -mmacosx-version-min="$MACOS_MIN_VERSION" -framework Foundation \
    Helpers/mobile.m -o "$STAGE/mobile-$ARCH"
  MOBILE_BINARIES+=("$STAGE/mobile-$ARCH")
  if [[ -n "$MOBILE_PREFIX" ]]; then
    clang -O2 -arch "$ARCH" -mmacosx-version-min="$MACOS_MIN_VERSION" -I"$MOBILE_PREFIX/include" -L"$MOBILE_PREFIX/lib" \
      Helpers/watch.c -limobiledevice-1.0 -lplist-2.0 -o "$STAGE/watch-$ARCH"
    WATCH_BINARIES+=("$STAGE/watch-$ARCH")
  fi
done
lipo -create "${MOBILE_BINARIES[@]}" -output "$APP/Contents/Resources/bin/pilbar-mobile-native"
if [[ ${#WATCH_BINARIES[@]} -gt 0 ]]; then
  lipo -create "${WATCH_BINARIES[@]}" -output "$APP/Contents/Resources/bin/pilbar-watch"
fi
for HELPER in "$APP/Contents/Resources/bin/"*; do
  chmod +x "$HELPER"
  codesign "${CODESIGN_ARGS[@]}" "$HELPER"
done
chmod -R u+w "$APP"
xattr -cr "$APP"
find "$APP" -name '._*' -delete
shopt -s nullglob
for FRAMEWORK in "$APP/Contents/Frameworks/"*.framework; do
  while IFS= read -r -d '' BIN; do codesign "${CODESIGN_ARGS[@]}" "$BIN"; done < <(find "$FRAMEWORK" -type f -perm -111 -print0)
  codesign "${CODESIGN_ARGS[@]}" "$FRAMEWORK"
done
shopt -u nullglob
codesign "${CODESIGN_ARGS[@]}" --entitlements "$APP_ENTITLEMENTS" "$APP"
python3 Scripts/package_check.py verify "$APP" --mode "$SIGNING_MODE" --architectures "${ARCH_LIST[@]}"
python3 Scripts/package_check.py preflight "$APP_OUTPUT_DIR"
python3 Scripts/package_check.py publish "$APP" "$APP_OUTPUT_DIR/$APP_NAME.app"
echo "Created $APP_OUTPUT_DIR/$APP_NAME.app"
