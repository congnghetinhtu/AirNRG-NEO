#!/bin/zsh
set -e
cd "$(dirname "$0")"
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
export PATH=/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/bin:$PATH
echo "Building release binaries (needs full Xcode for SwiftUI macros)…"
swift build -c release --product nrg2wav --product AirNRGNeo
BIN_DIR=$(swift build -c release --show-bin-path)
echo "Binaries in $BIN_DIR"
ls -lh "$BIN_DIR/nrg2wav" "$BIN_DIR/AirNRGNeo"
APP="AirNRG Neo.app"
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$BIN_DIR/AirNRGNeo" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/"
codesign --sign - --force --deep "$APP"
echo "Created $APP"
echo "Drag $APP to /Applications. Then drag .nrg files onto its window or Dock icon."
