import AppKit
import CoreGraphics

/// Read-only wrappers around private SkyLight space APIs (resolved via dlsym).
enum SkyLight {
    private typealias MainConnectionFn = @convention(c) () -> Int32
    private typealias CopySpacesFn = @convention(c) (Int32) -> Unmanaged<CFArray>?

    private static let handle = dlopen("/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight", RTLD_NOW)

    private static func symbol<T>(_ names: [String], as _: T.Type) -> T? {
        for name in names {
            if let p = dlsym(handle, name) { return unsafeBitCast(p, to: T.self) }
        }
        return nil
    }

    private static let mainConnection = symbol(["SLSMainConnectionID", "CGSMainConnectionID"], as: MainConnectionFn.self)
    private static let copySpaces = symbol(["SLSCopyManagedDisplaySpaces", "CGSCopyManagedDisplaySpaces"], as: CopySpacesFn.self)

    static var isAvailable: Bool { mainConnection != nil && copySpaces != nil }

    static func managedDisplaySpaces() -> [[String: Any]] {
        guard let mainConnection, let copySpaces,
              let array = copySpaces(mainConnection())?.takeRetainedValue() else { return [] }
        return array as? [[String: Any]] ?? []
    }
}

struct Tile {
    let windowID: CGWindowID
    let pid: pid_t?
    let appName: String
    let x: Double
}

struct SplitSpace {
    let spaceID: UInt64
    let isCurrent: Bool
    let tiles: [Tile]
    let raw: [String: Any]
}

enum Spaces {
    /// Split View = type-4 space whose TileLayoutManager.TileSpaces has 2+ entries (macOS 26+).
    static func splitSpaces() -> [SplitSpace] {
        var result: [SplitSpace] = []
        for display in SkyLight.managedDisplaySpaces() {
            let currentID = uint64((display["Current Space"] as? [String: Any])?["ManagedSpaceID"])
            for space in display["Spaces"] as? [[String: Any]] ?? [] {
                guard let layout = space["TileLayoutManager"] as? [String: Any],
                      let tileSpaces = layout["TileSpaces"] as? [[String: Any]],
                      tileSpaces.count >= 2,
                      let spaceID = uint64(space["ManagedSpaceID"] ?? space["id64"]) else { continue }
                let tiles = tileSpaces.compactMap(parseTile)
                guard tiles.count >= 2 else { continue }
                result.append(SplitSpace(spaceID: spaceID, isCurrent: spaceID == currentID, tiles: tiles, raw: space))
            }
        }
        return result
    }

    private static func parseTile(_ dict: [String: Any]) -> Tile? {
        guard let wid = uint64(dict["TileWindowID"] ?? dict["fs_wid"]) else { return nil }
        // pid may be a number or an array of numbers.
        let pidValue = (dict["pid"] as? [Any])?.first ?? dict["pid"]
        let pid = (pidValue as? NSNumber).map { pid_t($0.int32Value) }
        let x = ((dict["TileRect"] as? [String: Any])?["X"] as? NSNumber)?.doubleValue ?? 0
        // appName is absent on macOS 27; fall back to the running app's name.
        let appName = dict["appName"] as? String
            ?? pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            ?? "?"
        return Tile(windowID: CGWindowID(truncatingIfNeeded: wid), pid: pid, appName: appName, x: x)
    }

    private static func uint64(_ value: Any?) -> UInt64? {
        (value as? NSNumber)?.uint64Value
    }
}
