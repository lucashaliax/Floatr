import AppKit

/// Optional menu bar item (off by default; Floatr runs invisibly).
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {
    static let shared = MenuBarController()
    private var item: NSStatusItem?

    func update() {
        let model = AppModel.shared
        if model.settings.showMenuBarIcon {
            if item == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
                item.button?.image = NSImage(systemSymbolName: "pip", accessibilityDescription: "Floatr")
                let menu = NSMenu()
                menu.delegate = self
                item.menu = menu
                self.item = item
            }
            item?.button?.image = NSImage(systemSymbolName: model.floatingTitle == nil ? "pip" : "pip.fill",
                                          accessibilityDescription: "Floatr")
        } else if let item {
            NSStatusBar.system.removeStatusItem(item)
            self.item = nil
        }
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let model = AppModel.shared
        menu.removeAllItems()

        if let title = model.floatingTitle {
            let header = NSMenuItem(title: String(localized: "In PiP: \(title)"), action: nil, keyEquivalent: "")
            header.isEnabled = false
            menu.addItem(header)
            menu.addItem(.separator())
        }

        let floating = model.floatingTitle != nil
        add(menu, floating ? String(localized: "Exit PiP") : String(localized: "Enter PiP"), .toggle)
        add(menu, String(localized: "Play / pause"), .playPause)
        add(menu, String(localized: "Go to the video's tab"), .focusTab)
        menu.addItem(.separator())

        let update = NSMenuItem(title: String(localized: "Check for Updates…"), action: #selector(checkUpdates), keyEquivalent: "")
        update.target = self
        menu.addItem(update)
        let settings = NSMenuItem(title: String(localized: "Settings…"), action: #selector(openSettings), keyEquivalent: ",")
        settings.target = self
        menu.addItem(settings)
        let quit = NSMenuItem(title: String(localized: "Quit Floatr"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        menu.addItem(quit)
    }

    private func add(_ menu: NSMenu, _ title: String, _ cmd: PiPCommand) {
        let item = NSMenuItem(title: title, action: #selector(run(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = cmd.rawValue
        if let sc = AppModel.shared.settings.shortcuts[cmd] {
            // Shown as a hint only; the global hotkey does the work.
            item.toolTip = sc.displayString
            item.title = "\(title)    \(sc.displayString)"
        }
        menu.addItem(item)
    }

    @objc private func run(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String, let cmd = PiPCommand(rawValue: raw) else { return }
        AppModel.shared.perform(cmd)
    }

    @objc private func checkUpdates() {
        (NSApp.delegate as? AppDelegate)?.showSettings(pane: .about)
        Task { await Updater.shared.check() }
    }

    @objc private func openSettings() {
        (NSApp.delegate as? AppDelegate)?.showSettings()
    }
}
