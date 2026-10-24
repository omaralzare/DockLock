#!/usr/bin/env bash
set -e
echo "⬇️  Downloading DockLock..."
TMP_DIR=$(mktemp -d)
curl -fsSL "https://raw.githubusercontent.com/omaralzare/DockLock/main/dock_lock.swift" -o "$TMP_DIR/dock_lock.swift"
echo "🔨 Building /Applications/DockLock.app..."
swiftc -O "$TMP_DIR/dock_lock.swift" -o "$TMP_DIR/dock-lock"
"$TMP_DIR/dock-lock" --install-app
rm -rf "$TMP_DIR"
echo "✅ Installed! Launching DockLock..."
open /Applications/DockLock.app
