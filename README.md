# DockLock (macOS Primary Screen Dock Anchor)

A lightweight, zero-dependency native macOS utility written in Swift that keeps your Mac's Dock anchored to your primary display across multi-monitor setups.

When **Displays have separate Spaces** is enabled in macOS, moving your cursor to the bottom edge of any secondary monitor normally summons the Dock away from your main screen. **DockLock** runs a low-level CoreGraphics Event Tap (`CGEvent.tapCreate`) that silently drops downward bottom-edge trigger packets on secondary monitors while keeping horizontal cursor movement completely smooth.

## Features

| Feature | Details |
| :--- | :--- |
| **Zero-Lag Edge Guard** | Drops only downward edge-push packets (`deltaY > 0`) on secondary displays with no cursor bounce or `CGWarpMouseCursorPosition` lag |
| **Vertical Stack Aware** | Automatically allows normal cursor movement across shared top/bottom boundaries when monitors are stacked vertically |
| **Modifier Key Bypass** | Hold **Option + Command (`⌥ + ⌘`)** at any time to temporarily allow moving the Dock to another display |
| **Wake & Display Recovery** | Automatically pulls the Dock back to your primary screen after sleep/wake or monitor reconnection |
| **Menu Bar Controls (`⚓️`)** | Toggle Dock locking, summon the Dock back to the primary display on demand, or toggle **Launch at Login** with one click |

## Requirements

- **macOS 13.0 (Ventura)** or later (Apple Silicon or Intel)
- **System Settings → Desktop & Dock → Position on screen**: set to **Bottom**
- **System Settings → Desktop & Dock → Mission Control**: **Displays have separate Spaces** enabled
- **Accessibility Permission**: required by macOS to filter bottom-edge pointer events

## Installation

### Option 1: One-Line Terminal Installer

Run the following command in **Terminal** to download, compile, generate the native app icon, and launch `/Applications/DockLock.app`:

```bash
curl -fsSL https://raw.githubusercontent.com/omaralzare/DockLock/main/install.sh | bash
```

### Option 2: Download Pre-Built App

1. Download **`DockLock.zip`** from the [Releases](https://github.com/omaralzare/DockLock/releases) page.
2. Unzip and drag **`DockLock.app`** into your **Applications** folder.
3. Right-click **`DockLock.app` → Open** on first launch.

### Option 3: Build from Source

```bash
git clone https://github.com/omaralzare/DockLock.git
cd DockLock
swiftc -O dock_lock.swift -o dock-lock
./dock-lock --install-app
rm -f dock-lock
open /Applications/DockLock.app
```

## First-Launch Setup

1. On first launch, `DockLock` displays a **`⚠️`** icon in the menu bar and prompts for **Accessibility** access.
2. Open **System Settings → Privacy & Security → Accessibility** (or **Device Control and Data Access** on newer macOS releases) and toggle **DockLock** **On**.
3. The menu bar icon automatically switches from **`⚠️`** to **`⚓️`** within a second—no restart required.
4. Click the **`⚓️`** icon in your menu bar and check **Launch at Login** if you want `DockLock` to start automatically every time you log in.

## License

Released under the MIT License.
