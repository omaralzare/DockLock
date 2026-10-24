import Cocoa
import ApplicationServices

struct Config {
    static let bottomGuardMargin: CGFloat = 2.0
    static let bypassFlags: CGEventFlags = [.maskAlternate, .maskCommand]
    static let bundleID = "com.local.docklock.app"
    static let agentLabel = "com.local.docklock"
}

final class DisplayGuard {
    static let shared = DisplayGuard()

    var isLocked = true
    private(set) var primaryDisplayID: CGDirectDisplayID = CGMainDisplayID()
    private(set) var allDisplayBounds: [(id: CGDirectDisplayID, bounds: CGRect)] = []

    private init() {
        refreshDisplays()
    }

    func refreshDisplays() {
        primaryDisplayID = CGMainDisplayID()
        var count: UInt32 = 0
        guard CGGetActiveDisplayList(0, nil, &count) == .success, count > 0 else {
            allDisplayBounds = []
            return
        }
        var ids = [CGDirectDisplayID](repeating: 0, count: Int(count))
        guard CGGetActiveDisplayList(count, &ids, &count) == .success else {
            allDisplayBounds = []
            return
        }
        allDisplayBounds = ids.map { ($0, CGDisplayBounds($0)) }
    }

    private func hasDisplayBelow(x: CGFloat, bottomEdgeY: CGFloat, currentID: CGDirectDisplayID) -> Bool {
        let probe = CGPoint(x: x, y: bottomEdgeY + 4.0)
        return allDisplayBounds.contains { $0.id != currentID && $0.bounds.contains(probe) }
    }

    func handleMouseEvent(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        guard isLocked, allDisplayBounds.count > 1, !event.flags.contains(Config.bypassFlags) else {
            return Unmanaged.passUnretained(event)
        }

        let location = event.location
        guard let current = allDisplayBounds.first(where: { $0.bounds.contains(location) }),
              current.id != primaryDisplayID else {
            return Unmanaged.passUnretained(event)
        }

        let maxY = current.bounds.maxY
        let safeY = maxY - Config.bottomGuardMargin

        if location.y >= safeY {
            if hasDisplayBelow(x: location.x, bottomEdgeY: maxY, currentID: current.id) {
                return Unmanaged.passUnretained(event)
            }

            let deltaX = event.getDoubleValueField(.mouseEventDeltaX)
            let deltaY = event.getDoubleValueField(.mouseEventDeltaY)

            if type == .mouseMoved && deltaY > 0 && abs(deltaX) < 0.5 {
                return nil
            }

            if deltaY > 0 {
                event.setIntegerValueField(.mouseEventDeltaY, value: 0)
                event.setDoubleValueField(.mouseEventDeltaY, value: 0.0)
            }
            event.location = CGPoint(x: location.x, y: safeY)
        }

        return Unmanaged.passUnretained(event)
    }

    func summonDockToPrimaryDisplay() {
        refreshDisplays()
        guard let primary = allDisplayBounds.first(where: { $0.id == primaryDisplayID }) else { return }

        let savedLocation = CGEvent(source: nil)?.location
        let targetPoint = CGPoint(x: primary.bounds.midX, y: primary.bounds.maxY - 1.0)

        DispatchQueue.global(qos: .userInteractive).async {
            CGWarpMouseCursorPosition(targetPoint)
            CGAssociateMouseAndMouseCursorPosition(1)

            for _ in 0..<6 {
                if let moveEvent = CGEvent(
                    mouseEventSource: nil,
                    mouseType: .mouseMoved,
                    mouseCursorPosition: targetPoint,
                    mouseButton: .left
                ) {
                    moveEvent.setIntegerValueField(.mouseEventDeltaY, value: 20)
                    moveEvent.post(tap: .cghidEventTap)
                }
                usleep(25_000)
            }

            if let original = savedLocation {
                CGWarpMouseCursorPosition(original)
                CGAssociateMouseAndMouseCursorPosition(1)
            }
        }
    }
}

final class EventTapController {
    fileprivate var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    func start() -> Bool {
        let mask: CGEventMask =
            (1 << CGEventType.mouseMoved.rawValue) |
            (1 << CGEventType.leftMouseDragged.rawValue) |
            (1 << CGEventType.rightMouseDragged.rawValue) |
            (1 << CGEventType.otherMouseDragged.rawValue)

        let callback: CGEventTapCallBack = { _, type, event, userInfo in
            if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                if let userInfo = userInfo,
                   let tap = Unmanaged<EventTapController>.fromOpaque(userInfo).takeUnretainedValue().eventTap {
                    CGEvent.tapEnable(tap: tap, enable: true)
                }
                return Unmanaged.passUnretained(event)
            }
            return DisplayGuard.shared.handleMouseEvent(type: type, event: event)
        }

        let selfPtr = Unmanaged.passUnretained(self).toOpaque()
        let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        ) ?? CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: callback,
            userInfo: selfPtr
        )

        guard let validTap = tap else { return false }

        eventTap = validTap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, validTap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
        CGEvent.tapEnable(tap: validTap, enable: true)
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
    }
}

enum LaunchAgentManager {
    static var plistURL: URL {
        FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents/\(Config.agentLabel).plist")
    }

    static var isEnabled: Bool {
        FileManager.default.fileExists(atPath: plistURL.path)
    }

    static func setEnabled(_ enabled: Bool) {
        let fm = FileManager.default
        if enabled {
            let appBinary = "/Applications/DockLock.app/Contents/MacOS/DockLock"
            let execPath = fm.fileExists(atPath: appBinary)
                ? appBinary
                : URL(fileURLWithPath: CommandLine.arguments[0]).standardized.path

            let plist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>Label</key>
                <string>\(Config.agentLabel)</string>
                <key>ProgramArguments</key>
                <array>
                    <string>\(execPath)</string>
                </array>
                <key>RunAtLoad</key>
                <true/>
                <key>KeepAlive</key>
                <true/>
            </dict>
            </plist>
            """
            try? fm.createDirectory(at: plistURL.deletingLastPathComponent(), withIntermediateDirectories: true)
            try? plist.write(to: plistURL, atomically: true, encoding: .utf8)
        } else {
            try? fm.removeItem(at: plistURL)
        }
    }
}

enum AppBundleInstaller {
    static func renderIcon(size: CGFloat = 1024) -> NSImage {
        let image = NSImage(size: NSSize(width: size, height: size))
        image.lockFocus()

        guard let ctx = NSGraphicsContext.current?.cgContext else {
            image.unlockFocus()
            return image
        }

        let scale = size / 1024.0
        ctx.saveGState()

        let inset = 96.0 * scale
        let bgRect = NSRect(x: inset, y: inset, width: size - inset * 2, height: size - inset * 2)
        let bgPath = NSBezierPath(roundedRect: bgRect, xRadius: 185.0 * scale, yRadius: 185.0 * scale)

        let gradient = NSGradient(colors: [
            NSColor(calibratedRed: 0.06, green: 0.10, blue: 0.22, alpha: 1.0),
            NSColor(calibratedRed: 0.11, green: 0.28, blue: 0.58, alpha: 1.0),
            NSColor(calibratedRed: 0.05, green: 0.52, blue: 0.78, alpha: 1.0)
        ])
        gradient?.draw(in: bgPath, angle: -55)

        NSColor(calibratedWhite: 1.0, alpha: 0.22).setStroke()
        bgPath.lineWidth = 6.0 * scale
        bgPath.stroke()

        let dockWidth = 620.0 * scale
        let dockHeight = 130.0 * scale
        let dockX = (size - dockWidth) / 2.0
        let dockY = 175.0 * scale
        let dockRect = NSRect(x: dockX, y: dockY, width: dockWidth, height: dockHeight)
        let dockPath = NSBezierPath(roundedRect: dockRect, xRadius: 38.0 * scale, yRadius: 38.0 * scale)

        NSColor(calibratedWhite: 1.0, alpha: 0.20).setFill()
        dockPath.fill()
        NSColor(calibratedWhite: 1.0, alpha: 0.40).setStroke()
        dockPath.lineWidth = 4.0 * scale
        dockPath.stroke()

        let tileColors: [NSColor] = [
            NSColor(calibratedRed: 0.22, green: 0.65, blue: 1.00, alpha: 0.95),
            NSColor(calibratedRed: 0.20, green: 0.84, blue: 0.55, alpha: 0.95),
            NSColor(calibratedRed: 1.00, green: 0.62, blue: 0.18, alpha: 0.95),
            NSColor(calibratedRed: 0.95, green: 0.33, blue: 0.45, alpha: 0.95)
        ]
        let tileSize = 78.0 * scale
        let tileSpacing = 44.0 * scale
        let totalTilesWidth = CGFloat(tileColors.count) * tileSize + CGFloat(tileColors.count - 1) * tileSpacing
        var tileX = (size - totalTilesWidth) / 2.0
        let tileY = dockY + (dockHeight - tileSize) / 2.0

        for color in tileColors {
            let tileRect = NSRect(x: tileX, y: tileY, width: tileSize, height: tileSize)
            let tilePath = NSBezierPath(roundedRect: tileRect, xRadius: 20.0 * scale, yRadius: 20.0 * scale)
            color.setFill()
            tilePath.fill()
            tileX += tileSize + tileSpacing
        }

        let bodyWidth = 260.0 * scale
        let bodyHeight = 210.0 * scale
        let bodyX = (size - bodyWidth) / 2.0
        let bodyY = 390.0 * scale

        let shackleWidth = 150.0 * scale
        let shackleHeight = 155.0 * scale
        let shackleX = (size - shackleWidth) / 2.0
        let shackleY = bodyY + bodyHeight - 35.0 * scale
        let shackleRect = NSRect(x: shackleX, y: shackleY, width: shackleWidth, height: shackleHeight)
        let shacklePath = NSBezierPath(roundedRect: shackleRect, xRadius: shackleWidth / 2.0, yRadius: shackleWidth / 2.0)
        shacklePath.lineWidth = 36.0 * scale
        NSColor.white.setStroke()
        shacklePath.stroke()

        let bodyRect = NSRect(x: bodyX, y: bodyY, width: bodyWidth, height: bodyHeight)
        let bodyPath = NSBezierPath(roundedRect: bodyRect, xRadius: 42.0 * scale, yRadius: 42.0 * scale)
        NSColor.white.setFill()
        bodyPath.fill()

        let holeRadius = 22.0 * scale
        let holeCenter = NSPoint(x: size / 2.0, y: bodyY + bodyHeight * 0.56)
        let holePath = NSBezierPath()
        holePath.appendArc(withCenter: holeCenter, radius: holeRadius, startAngle: 0, endAngle: 360)
        let slotWidth = 18.0 * scale
        let slotHeight = 48.0 * scale
        let slotRect = NSRect(x: (size - slotWidth) / 2.0, y: holeCenter.y - slotHeight, width: slotWidth, height: slotHeight)
        holePath.append(NSBezierPath(roundedRect: slotRect, xRadius: slotWidth / 2.0, yRadius: slotWidth / 2.0))
        NSColor(calibratedRed: 0.09, green: 0.24, blue: 0.50, alpha: 1.0).setFill()
        holePath.fill()

        ctx.restoreGState()
        image.unlockFocus()
        return image
    }

    static func writePNG(image: NSImage, pixelSize: Int, to url: URL) throws {
        guard let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .calibratedRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else { return }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
        image.draw(in: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize), from: .zero, operation: .copy, fraction: 1.0)
        NSGraphicsContext.restoreGraphicsState()

        if let data = rep.representation(using: .png, properties: [:]) {
            try data.write(to: url)
        }
    }

    static func installAppBundle() {
        let fm = FileManager.default
        let appURL = URL(fileURLWithPath: "/Applications/DockLock.app")
        let contentsURL = appURL.appendingPathComponent("Contents")
        let macosURL = contentsURL.appendingPathComponent("MacOS")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")

        do {
            try fm.createDirectory(at: macosURL, withIntermediateDirectories: true)
            try fm.createDirectory(at: resourcesURL, withIntermediateDirectories: true)

            let currentExec = URL(fileURLWithPath: CommandLine.arguments[0]).standardized
            let destExec = macosURL.appendingPathComponent("DockLock")
            if fm.fileExists(atPath: destExec.path) {
                try fm.removeItem(at: destExec)
            }
            try fm.copyItem(at: currentExec, to: destExec)
            try fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: destExec.path)

            let masterIcon = renderIcon(size: 1024)
            let tempIconset = fm.temporaryDirectory.appendingPathComponent("AppIcon.iconset")
            if fm.fileExists(atPath: tempIconset.path) {
                try fm.removeItem(at: tempIconset)
            }
            try fm.createDirectory(at: tempIconset, withIntermediateDirectories: true)

            let sizes: [(String, Int)] = [
                ("icon_16x16.png", 16), ("icon_16x16@2x.png", 32),
                ("icon_32x32.png", 32), ("icon_32x32@2x.png", 64),
                ("icon_128x128.png", 128), ("icon_128x128@2x.png", 256),
                ("icon_256x256.png", 256), ("icon_256x256@2x.png", 512),
                ("icon_512x512.png", 512), ("icon_512x512@2x.png", 1024)
            ]

            for (name, pixels) in sizes {
                try writePNG(image: masterIcon, pixelSize: pixels, to: tempIconset.appendingPathComponent(name))
            }

            let icnsURL = resourcesURL.appendingPathComponent("AppIcon.icns")
            let iconutil = Process()
            iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
            iconutil.arguments = ["-c", "icns", tempIconset.path, "-o", icnsURL.path]
            try? iconutil.run()
            iconutil.waitUntilExit()
            try? fm.removeItem(at: tempIconset)

            let infoPlist = """
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>CFBundleExecutable</key>
                <string>DockLock</string>
                <key>CFBundleIconFile</key>
                <string>AppIcon</string>
                <key>CFBundleIdentifier</key>
                <string>\(Config.bundleID)</string>
                <key>CFBundleName</key>
                <string>DockLock</string>
                <key>CFBundlePackageType</key>
                <string>APPL</string>
                <key>CFBundleShortVersionString</key>
                <string>1.2</string>
                <key>LSUIElement</key>
                <true/>
            </dict>
            </plist>
            """
            try infoPlist.write(to: contentsURL.appendingPathComponent("Info.plist"), atomically: true, encoding: .utf8)

            let codesign = Process()
            codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
            codesign.arguments = ["--force", "--deep", "--sign", "-", appURL.path]
            try? codesign.run()
            codesign.waitUntilExit()

            NSWorkspace.shared.setIcon(masterIcon, forFile: appURL.path, options: [])
        } catch {
            exit(1)
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let tapController = EventTapController()
    private var statusItem: NSStatusItem?
    private var lockMenuItem: NSMenuItem?
    private var loginMenuItem: NSMenuItem?
    private var permissionTimer: Timer?

    func applicationDidFinishLaunching(_ notification: Notification) {
        setupMenuBar()

        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        if AXIsProcessTrustedWithOptions(options) {
            activateTap()
        } else {
            statusItem?.button?.title = "⚠️"
            permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] timer in
                if AXIsProcessTrusted() {
                    timer.invalidate()
                    self?.activateTap()
                }
            }
        }

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleScreenChange),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(handleWake),
            name: NSWorkspace.screensDidWakeNotification,
            object: nil
        )
    }

    private func activateTap() {
        guard tapController.start() else { return }
        statusItem?.button?.title = DisplayGuard.shared.isLocked ? "⚓️" : "🔓"
    }

    func applicationWillTerminate(_ notification: Notification) {
        permissionTimer?.invalidate()
        tapController.stop()
    }

    @objc private func handleScreenChange() {
        DisplayGuard.shared.refreshDisplays()
        if DisplayGuard.shared.isLocked {
            DisplayGuard.shared.summonDockToPrimaryDisplay()
        }
    }

    @objc private func handleWake() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            DisplayGuard.shared.refreshDisplays()
            if DisplayGuard.shared.isLocked {
                DisplayGuard.shared.summonDockToPrimaryDisplay()
            }
        }
    }

    private func setupMenuBar() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.title = "⚓️"

        let menu = NSMenu()

        let toggleItem = NSMenuItem(title: "Lock Dock to Primary Screen", action: #selector(toggleLock), keyEquivalent: "l")
        toggleItem.target = self
        toggleItem.state = DisplayGuard.shared.isLocked ? .on : .off
        menu.addItem(toggleItem)
        lockMenuItem = toggleItem

        let summonItem = NSMenuItem(title: "Move Dock to Primary Screen Now", action: #selector(summonNow), keyEquivalent: "m")
        summonItem.target = self
        menu.addItem(summonItem)

        let loginItem = NSMenuItem(title: "Launch at Login", action: #selector(toggleLogin), keyEquivalent: "")
        loginItem.target = self
        loginItem.state = LaunchAgentManager.isEnabled ? .on : .off
        menu.addItem(loginItem)
        loginMenuItem = loginItem

        menu.addItem(.separator())

        let quitItem = NSMenuItem(title: "Quit DockLock", action: #selector(quitApp), keyEquivalent: "q")
        quitItem.target = self
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func toggleLock() {
        DisplayGuard.shared.isLocked.toggle()
        let locked = DisplayGuard.shared.isLocked
        lockMenuItem?.state = locked ? .on : .off
        statusItem?.button?.title = locked ? "⚓️" : "🔓"
    }

    @objc private func summonNow() {
        DisplayGuard.shared.summonDockToPrimaryDisplay()
    }

    @objc private func toggleLogin() {
        let newState = !LaunchAgentManager.isEnabled
        LaunchAgentManager.setEnabled(newState)
        loginMenuItem?.state = newState ? .on : .off
    }

    @objc private func quitApp() {
        tapController.stop()
        NSApp.terminate(nil)
    }
}

if CommandLine.arguments.contains("--install-app") {
    AppBundleInstaller.installAppBundle()
    exit(0)
}

let app = NSApplication.shared
app.setActivationPolicy(.accessory)
let delegate = AppDelegate()
app.delegate = delegate
app.run()