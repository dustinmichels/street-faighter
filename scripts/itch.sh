#!/usr/bin/env bash
# Push the builds from `mise run export` to itch.io (channels mac, windows, linux).
#USAGE arg "<version>" help="Version shown on itch.io, like v1.2.3"
set -euo pipefail
version="${usage_version}"
for f in build/macos/street-fAIghter.zip build/windows/street-fAIghter.exe build/linux/street-fAIghter.x86_64; do
  [[ -f "$f" ]] || { echo "missing $f; run 'mise run export' first" >&2; exit 1; }
done
rm -rf build/itch
mkdir -p build/itch/mac
ditto -x -k build/macos/street-fAIghter.zip build/itch/mac
butler push build/itch/mac "$ITCH_TARGET:mac" --userversion "$version"
butler push build/windows "$ITCH_TARGET:windows" --userversion "$version"
butler push build/linux "$ITCH_TARGET:linux" --userversion "$version"
