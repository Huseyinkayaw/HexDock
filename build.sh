#!/bin/bash
set -e
cd "$(dirname "$0")"
APP=build/HexDock.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
swiftc -O -swift-version 5 main.swift NowPlaying.swift Switcher.swift WindowActions.swift SelfTest.swift -o "$APP/Contents/MacOS/HexDock"
strip -x "$APP/Contents/MacOS/HexDock"   # hata ayıklama sembollerini at (daha küçük dosya)
cp Info.plist "$APP/Contents/Info.plist"
# Kalıcı sertifika varsa onunla imzala (izinler her derlemede sıfırlanmaz), yoksa ad-hoc.
if security find-identity -p codesigning | grep -q "HexDock Dev"; then ID="HexDock Dev"; else ID="-"; fi
codesign --force --sign "$ID" "$APP"
# Uygulamalar klasörüne kur
pkill -x HexDock || true
rm -rf /Applications/HexDock.app /Applications/DockPeek.app
pkill -x DockPeek || true
cp -R "$APP" /Applications/HexDock.app
echo "Installed /Applications/HexDock.app"
