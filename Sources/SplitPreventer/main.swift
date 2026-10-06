import AppKit
import ApplicationServices

private let logFile: FileHandle? = {
    let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SplitPreventer.log")
    if !FileManager.default.fileExists(atPath: url.path) {
        FileManager.default.createFile(atPath: url.path, contents: nil)
    }
    let handle = try? FileHandle(forWritingTo: url)
    handle?.seekToEndOfFile()
    return handle
}()

func log(_ message: String) {
    let f = DateFormatter()
    f.dateFormat = "HH:mm:ss.SSS"
    let line = "[\(f.string(from: Date()))] \(message)"
    print(line)
    logFile?.write(Data((line + "\n").utf8)) // stdout is lost when launched as .app
}

struct Options {
    var dryRun = false
    var windowed = false // don't re-enter fullscreen after popping out
    var interval: TimeInterval = 0.5
}

/// Detects Split View spaces and breaks them back into separate fullscreen spaces.
final class Preventer {
    var options: Options
    var isEnabled = true
    var onUnsplit: ((String) -> Void)?
    private let settleDelay: TimeInterval = 1.0   // split must persist this long before acting
    private let postExitDelay: TimeInterval = 0.6 // wait after Mission Control closes
    private let retryBackoff: TimeInterval = 2.0

    private let missionControl = MissionControlWatcher()
    private var firstSeen: [UInt64: Date] = [:]
    private var reported: Set<UInt64> = []
    private var busy = false
    private var timer: Timer?

    init(options: Options) {
        self.options = options
    }

    func start() {
        missionControl.start()
        timer = Timer.scheduledTimer(withTimeInterval: options.interval, repeats: true) { [weak self] _ in self?.tick() }
        let mode = [
            options.dryRun ? "dry-run" : "active",
            options.windowed ? "windowed" : nil,
        ].compactMap { $0 }.joined(separator: ", ")
        log("running (\(mode), poll \(options.interval)s).")
    }

    private func tick() {
        guard isEnabled else { return }
        let splits = Spaces.splitSpaces()
        let ids = Set(splits.map(\.spaceID))
        firstSeen = firstSeen.filter { ids.contains($0.key) }
        reported.formIntersection(ids)

        let now = Date()
        for space in splits where firstSeen[space.spaceID] == nil {
            firstSeen[space.spaceID] = now
            let apps = space.tiles.map { "\($0.appName)#\($0.windowID)" }.joined(separator: " | ")
            log("🔍 split view detected: space \(space.spaceID) [\(apps)]\(space.isCurrent ? " (current)" : "")")
        }

        guard !busy, !missionControl.isActive,
              now.timeIntervalSince(missionControl.lastExit) >= postExitDelay else { return }

        guard let target = splits.first(where: { now.timeIntervalSince(firstSeen[$0.spaceID]!) >= settleDelay }) else { return }

        if options.dryRun {
            if reported.insert(target.spaceID).inserted {
                log("dry-run: would unsplit space \(target.spaceID). raw:\n\(target.raw)")
            }
            return
        }
        unsplit(target)
    }

    private func unsplit(_ space: SplitSpace) {
        // Pop out the rightmost tile; the other stays fullscreen in place.
        let tile = space.tiles.max { $0.x < $1.x }!
        guard let pid = tile.pid ?? AX.ownerPID(of: tile.windowID) else {
            log("⚠️ no pid for window \(tile.windowID)")
            backoff(space)
            return
        }
        guard let window = AX.findWindow(pid: pid, windowID: tile.windowID) else {
            log("⚠️ window \(tile.windowID) (\(tile.appName)) not reachable via AX; retrying (switching to that space may help)")
            backoff(space)
            return
        }

        busy = true
        let err = AX.setFullScreen(window, false)
        log("↩️ exit fullscreen \(tile.appName)#\(tile.windowID): \(err == .success ? "ok" : "error \(err.rawValue)")")
        guard err == .success else {
            busy = false
            backoff(space)
            return
        }
        onUnsplit?(space.tiles.map(\.appName).joined(separator: " | "))
        if options.windowed {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.busy = false }
        } else {
            reenterFullScreen(window, name: "\(tile.appName)#\(tile.windowID)", delay: 1.0, attemptsLeft: 10)
        }
    }

    private func reenterFullScreen(_ window: AXUIElement, name: String, delay: TimeInterval, attemptsLeft: Int) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [self] in
            if AX.isFullScreen(window) == false {
                let err = AX.setFullScreen(window, true)
                log("↪️ re-enter fullscreen \(name): \(err == .success ? "ok" : "error \(err.rawValue)")")
                // Let the animation finish before the next poll acts.
                DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { self.busy = false }
            } else if attemptsLeft > 0 {
                reenterFullScreen(window, name: name, delay: 0.5, attemptsLeft: attemptsLeft - 1)
            } else {
                log("⚠️ \(name) still fullscreen after exit request; giving up")
                busy = false
            }
        }
    }

    private func backoff(_ space: SplitSpace) {
        firstSeen[space.spaceID] = Date().addingTimeInterval(retryBackoff)
    }
}

// MARK: - Entry

setvbuf(stdout, nil, _IOLBF, 0)
let args = CommandLine.arguments

if args.contains("-h") || args.contains("--help") {
    print("""
    usage: SplitPreventer [--dump] [--dry-run] [--windowed] [--interval <sec>]
      --dump       print API availability and all spaces, then exit
      --dry-run    only log detected split views
      --windowed   leave the popped-out window windowed (no re-fullscreen)
      --interval   poll interval in seconds (default 0.5)
    """)
    exit(0)
}

print("SkyLight space API: \(SkyLight.isAvailable ? "✅" : "❌")")
print("_AXUIElementGetWindow: \(AX.hasGetWindow ? "✅" : "❌")")
print("_AXUIElementCreateWithRemoteToken: \(AX.hasRemoteToken ? "✅" : "❌")")
guard SkyLight.isAvailable, AX.hasGetWindow else { exit(1) }

if args.contains("--dump") {
    for display in SkyLight.managedDisplaySpaces() { print(display) }
    print("split spaces: \(Spaces.splitSpaces().map(\.spaceID))")
    exit(0)
}

var options = Options()
options.dryRun = args.contains("--dry-run")
options.windowed = args.contains("--windowed")
if let i = args.firstIndex(of: "--interval"), args.indices.contains(i + 1), let v = Double(args[i + 1]) {
    options.interval = v
}
let preventer = Preventer(options: options)

let app = NSApplication.shared
app.setActivationPolicy(.accessory) // menu bar only, no Dock icon
let menuBar = MenuBarController(preventer: preventer)

if AX.ensureTrusted() {
    preventer.start()
} else {
    print("請到 系統設定 → 隱私權與安全性 → 輔助使用，允許執行它的 app / terminal。")
    menuBar.status = "等待輔助使用權限…"
    // Start once permission is granted.
    Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { timer in
        guard AXIsProcessTrusted() else { return }
        timer.invalidate()
        menuBar.status = nil
        preventer.start()
    }
}
app.run()
