#!/usr/bin/env bash
# Builds Cron Manager with SwiftPM (no Xcode needed), wraps it in
# dist/CronManager.app, signs it and launches it. Usage: ./build.sh [run|build]
set -euo pipefail
cd "$(dirname "$0")"

APP=dist/CronManager.app
pkill -x CronManager 2>/dev/null || true

swift build -c release --disable-keychain

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/CronManager" "$APP/Contents/MacOS/CronManager"

PLIST="$APP/Contents/Info.plist"
plutil -create xml1 "$PLIST"
set_key() { plutil -replace "$1" "-$2" "$3" "$PLIST"; }
set_key CFBundleExecutable string CronManager
set_key CFBundleIdentifier string com.per.CronManager
set_key CFBundleName string "Cron Manager"
set_key CFBundlePackageType string APPL
VERSION=$(git describe --tags --match 'v[0-9]*' --abbrev=0 2>/dev/null || echo v0.0.0)
set_key CFBundleShortVersionString string "${VERSION#v}"
set_key CFBundleVersion string "$(git rev-list --count HEAD 2>/dev/null || echo 1)"
set_key LSMinimumSystemVersion string 26.0
set_key NSPrincipalClass string NSApplication
set_key NSHighResolutionCapable bool YES

# Apple Development certificate when one exists, otherwise ad-hoc.
IDENTITY=$(security find-identity -p codesigning -v 2>/dev/null | awk -F'"' '/Apple Development:/ { print $2; exit }')
codesign --force --sign "${IDENTITY:--}" "$APP"
echo "Built $APP (signed: ${IDENTITY:-ad-hoc})"

if [ "${1:-run}" = run ]; then open "$APP"; fi
