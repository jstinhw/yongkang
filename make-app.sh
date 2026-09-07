#!/bin/sh
# Builds .build/Yongkang.app — double-clickable, no Xcode project needed.
set -e
cd "$(dirname "$0")"
swift build -c release

APP=".build/Yongkang.app"
# `open` only reactivates an already-running instance, so it'd show the old binary.
pkill -x Yongkang 2>/dev/null || true
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp .build/release/Yongkang "$APP/Contents/MacOS/Yongkang"
cp -R .claude/skills "$APP/Contents/Resources/skills"

cat > "$APP/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key><string>Yongkang</string>
  <key>CFBundleIdentifier</key><string>local.yongkang.app</string>
  <key>CFBundleName</key><string>Yongkang</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleShortVersionString</key><string>0.1</string>
  <key>LSMinimumSystemVersion</key><string>13.0</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

echo "built $PWD/$APP  —  open it with: open $APP"
