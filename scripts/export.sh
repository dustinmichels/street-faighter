#!/usr/bin/env bash
# Export macOS, Windows and Linux builds into build/release/*.zip.
set -euo pipefail
rm -rf build
mkdir -p build/macos build/windows build/linux build/release
godot --headless --path . --export-release "macOS" build/macos/street-fAIghter.zip
godot --headless --path . --export-release "Windows" build/windows/street-fAIghter.exe
godot --headless --path . --export-release "Linux" build/linux/street-fAIghter.x86_64
cp build/macos/street-fAIghter.zip build/release/street-fAIghter-macos.zip
zip -j build/release/street-fAIghter-windows.zip build/windows/street-fAIghter.exe
zip -j build/release/street-fAIghter-linux.zip build/linux/street-fAIghter.x86_64
ls -lh build/release
