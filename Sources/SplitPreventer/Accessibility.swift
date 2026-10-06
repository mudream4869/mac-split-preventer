import ApplicationServices
import CoreGraphics
import Foundation

enum AX {
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError

    // Private: AXUIElement -> CGWindowID.
    private static let getWindow: GetWindowFn? = {
        let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)
        return dlsym(handle, "_AXUIElementGetWindow").map { unsafeBitCast($0, to: GetWindowFn.self) }
    }()

    static var hasGetWindow: Bool { getWindow != nil }

    /// Prompts for Accessibility permission if not yet granted.
    static func ensureTrusted() -> Bool {
        let key = kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String
        return AXIsProcessTrustedWithOptions([key: true] as CFDictionary)
    }

    static func windowID(of element: AXUIElement) -> CGWindowID? {
        var wid: CGWindowID = 0
        guard let getWindow, getWindow(element, &wid) == .success else { return nil }
        return wid
    }

    static func findWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        let app = AXUIElementCreateApplication(pid)
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement] else { return nil }
        return windows.first { self.windowID(of: $0) == windowID }
    }

    static func isFullScreen(_ window: AXUIElement) -> Bool? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(window, "AXFullScreen" as CFString, &value) == .success else { return nil }
        return value as? Bool
    }

    @discardableResult
    static func setFullScreen(_ window: AXUIElement, _ on: Bool) -> AXError {
        AXUIElementSetAttributeValue(window, "AXFullScreen" as CFString, (on ? kCFBooleanTrue : kCFBooleanFalse)!)
    }

    /// Fallback when TileSpaces has no pid.
    static func ownerPID(of windowID: CGWindowID) -> pid_t? {
        guard let list = CGWindowListCopyWindowInfo([.optionAll], kCGNullWindowID) as? [[String: Any]] else { return nil }
        let info = list.first { ($0[kCGWindowNumber as String] as? NSNumber)?.uint32Value == windowID }
        return (info?[kCGWindowOwnerPID as String] as? NSNumber).map { pid_t($0.int32Value) }
    }
}
