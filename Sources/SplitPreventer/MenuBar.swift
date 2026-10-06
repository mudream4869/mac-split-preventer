import AppKit
import ServiceManagement

/// Menu bar icon with toggles for the preventer.
final class MenuBarController: NSObject, NSMenuDelegate {
    private let preventer: Preventer
    private let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
    private var lastAction: String?
    private var flashTimer: Timer?

    /// Shown at the top of the menu (e.g. waiting for permission).
    var status: String? { didSet { updateIcon() } }

    init(preventer: Preventer) {
        self.preventer = preventer
        super.init()
        let menu = NSMenu()
        menu.delegate = self
        item.menu = menu
        menuNeedsUpdate(menu)
        updateIcon()

        preventer.onUnsplit = { [weak self] apps in
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            self?.lastAction = "\(f.string(from: Date())) 拆開 \(apps)"
            self?.flash()
        }
    }

    // Rebuild on open so states are always current.
    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.removeAllItems()
        if let status {
            menu.addItem(disabledItem(status))
        }
        menu.addItem(disabledItem(lastAction ?? "尚未拆開過 Split View"))
        menu.addItem(.separator())
        menu.addItem(toggle("啟用", preventer.isEnabled, #selector(toggleEnabled)))
        menu.addItem(toggle("Dry-run（只偵測）", preventer.options.dryRun, #selector(toggleDryRun)))
        menu.addItem(toggle("拆出後保持視窗（不重新全螢幕）", preventer.options.windowed, #selector(toggleWindowed)))
        menu.addItem(.separator())
        let login = toggle("登入時啟動", SMAppService.mainApp.status == .enabled, #selector(toggleLoginItem))
        login.isEnabled = isBundled // SMAppService needs an .app bundle
        menu.addItem(login)
        menu.addItem(withTitle: "打開 Log", action: #selector(openLog), keyEquivalent: "").target = self
        menu.addItem(.separator())
        menu.addItem(withTitle: "關於 SplitPreventer", action: #selector(showAbout), keyEquivalent: "").target = self
        menu.addItem(withTitle: "結束", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
    }

    private var isBundled: Bool { Bundle.main.bundleURL.pathExtension == "app" }

    private func disabledItem(_ title: String) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        return item
    }

    private func toggle(_ title: String, _ on: Bool, _ action: Selector) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: "")
        item.target = self
        item.state = on ? .on : .off
        return item
    }

    @objc private func toggleEnabled() {
        preventer.isEnabled.toggle()
        log("menu: \(preventer.isEnabled ? "enabled" : "paused")")
        updateIcon()
    }

    @objc private func toggleDryRun() {
        preventer.options.dryRun.toggle()
        log("menu: dry-run \(preventer.options.dryRun)")
        updateIcon()
    }

    @objc private func toggleWindowed() {
        preventer.options.windowed.toggle()
        log("menu: windowed \(preventer.options.windowed)")
    }

    @objc private func toggleLoginItem() {
        let service = SMAppService.mainApp
        do {
            if service.status == .enabled {
                try service.unregister()
            } else {
                try service.register()
            }
        } catch {
            log("⚠️ login item: \(error)")
        }
    }

    @objc private func openLog() {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Logs/SplitPreventer.log")
        NSWorkspace.shared.open(url)
    }

    // Menu bar app has no main window, so activate first or the panel stays behind.
    @objc private func showAbout() {
        let link = "https://github.com/mudream4869/mac-split-preventer"
        let credits = NSAttributedString(string: link, attributes: [
            .link: URL(string: link)!,
            .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
        ])
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [
            .applicationName: "SplitPreventer",
            .credits: credits,
        ])
    }

    // Dimmed when paused, dry-run or not yet running.
    private func updateIcon() {
        guard let button = item.button else { return }
        button.image = symbol("rectangle.split.2x1")
        button.appearsDisabled = !preventer.isEnabled || preventer.options.dryRun || status != nil
        button.toolTip = "SplitPreventer"
    }

    // Briefly show the filled icon after an unsplit.
    private func flash() {
        item.button?.image = symbol("rectangle.split.2x1.fill")
        flashTimer?.invalidate()
        flashTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: false) { [weak self] _ in self?.updateIcon() }
    }

    private func symbol(_ name: String) -> NSImage? {
        let image = NSImage(systemSymbolName: name, accessibilityDescription: "SplitPreventer")
        image?.isTemplate = true
        return image
    }
}
