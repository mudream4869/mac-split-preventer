import ApplicationServices
import CoreGraphics
import Foundation

enum AX {
    private typealias GetWindowFn = @convention(c) (AXUIElement, UnsafeMutablePointer<CGWindowID>) -> AXError
    private typealias CreateWithTokenFn = @convention(c) (CFData) -> Unmanaged<AXUIElement>?

    private static let handle = dlopen("/System/Library/Frameworks/ApplicationServices.framework/ApplicationServices", RTLD_NOW)

    // Private: AXUIElement -> CGWindowID.
    private static let getWindow: GetWindowFn? =
        dlsym(handle, "_AXUIElementGetWindow").map { unsafeBitCast($0, to: GetWindowFn.self) }

    // Private: build an AXUIElement from a remote token; reaches windows on other spaces.
    private static let createWithRemoteToken: CreateWithTokenFn? =
        dlsym(handle, "_AXUIElementCreateWithRemoteToken").map { unsafeBitCast($0, to: CreateWithTokenFn.self) }

    static var hasGetWindow: Bool { getWindow != nil }
    static var hasRemoteToken: Bool { createWithRemoteToken != nil }

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
        if AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
           let windows = value as? [AXUIElement],
           let match = windows.first(where: { self.windowID(of: $0) == windowID }) {
            return match
        }
        return bruteForceWindow(pid: pid, windowID: windowID)
    }

    /// kAXWindowsAttribute only lists windows on the current space; brute-force element ids
    /// via remote token instead (AltTab's technique). Token: pid | 0 | "coco" | element id.
    private static func bruteForceWindow(pid: pid_t, windowID: CGWindowID) -> AXUIElement? {
        guard let createWithRemoteToken else { return nil }
        var token = Data(count: 20)
        token.replaceSubrange(0..<4, with: withUnsafeBytes(of: pid) { Data($0) })
        token.replaceSubrange(4..<8, with: withUnsafeBytes(of: Int32(0)) { Data($0) })
        token.replaceSubrange(8..<12, with: withUnsafeBytes(of: Int32(0x636f_636f)) { Data($0) })
        for elementID: UInt64 in 0..<1000 {
            token.replaceSubrange(12..<20, with: withUnsafeBytes(of: elementID) { Data($0) })
            if let element = createWithRemoteToken(token as CFData)?.takeRetainedValue(),
               self.windowID(of: element) == windowID {
                return element
            }
        }
        return nil
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
