#!/usr/bin/env bash
set -e
echo "🛑 Stopping any running DockLock instances..."
launchctl bootout "gui/$(id -u)" "$HOME/Library/LaunchAgents/com.local.docklock.plist" 2>/dev/null || true
launchctl remove com.local.docklock 2>/dev/null || true
killall DockLock dock-lock 2>/dev/null || true

echo "⬇️  Downloading DockLock..."
TMP_DIR=$(mktemp -d)
curl -fsSL "https://raw.githubusercontent.com/omaralzare/DockLock/main/dock_lock.swift" -o "$TMP_DIR/dock_lock.swift"
echo "🔨 Building /Applications/DockLock.app..."
swiftc -O "$TMP_DIR/dock_lock.swift" -o "$TMP_DIR/dock-lock"
"$TMP_DIR/dock-lock" --install-app
rm -rf "$TMP_DIR"
echo "✅ Installed! Launching DockLock..."
open /Applications/DockLock.app
