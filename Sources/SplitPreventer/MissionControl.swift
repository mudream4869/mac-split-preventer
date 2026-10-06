import AppKit
import ApplicationServices

/// Tracks Mission Control via Dock's AX notifications (same approach as yabai).
final class MissionControlWatcher {
    private static let showNotifications = [
        "AXExposeShowAllWindows",
        "AXExposeShowFrontWindows",
        "AXExposeShowDesktop",
    ]
    private static let exitNotification = "AXExposeExit"

    private(set) var isActive = false
    private(set) var lastExit = Date.distantPast
    private var observer: AXObserver?

    func start() {
        guard let dock = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.dock").first else {
            log("⚠️ Dock not found; Mission Control state unknown")
            return
        }
        let pid = dock.processIdentifier
        let callback: AXObserverCallback = { _, _, notification, refcon in
            guard let refcon else { return }
            Unmanaged<MissionControlWatcher>.fromOpaque(refcon).takeUnretainedValue().handle(notification as String)
        }
        var obs: AXObserver?
        guard AXObserverCreate(pid, callback, &obs) == .success, let obs else {
            log("⚠️ AXObserverCreate failed for Dock")
            return
        }
        let app = AXUIElementCreateApplication(pid)
        let refcon = Unmanaged.passUnretained(self).toOpaque()
        for name in Self.showNotifications + [Self.exitNotification] {
            let err = AXObserverAddNotification(obs, app, name as CFString, refcon)
            log("observe \(name): \(err == .success ? "ok" : "error \(err.rawValue)")")
        }
        CFRunLoopAddSource(CFRunLoopGetMain(), AXObserverGetRunLoopSource(obs), .defaultMode)
        observer = obs
    }

    private func handle(_ name: String) {
        log("Mission Control: \(name)")
        if name == Self.exitNotification {
            isActive = false
            lastExit = Date()
        } else {
            isActive = true
        }
    }
}
