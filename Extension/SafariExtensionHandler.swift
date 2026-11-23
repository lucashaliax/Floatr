import SafariServices
import os

private let log = Logger(subsystem: Floatr.extensionBundleID, category: "handler")

/// Bridges three sources of commands to the page's content script:
/// the toolbar button, the video context menu, and the Floatr app (global shortcuts).
final class SafariExtensionHandler: SFSafariExtensionHandler {
    private let registry = PageRegistry.shared
    private let tracker = CommandTracker.shared

    // MARK: Messages from content.js

    override func messageReceived(withName messageName: String, from page: SFSafariPage, userInfo: [String: Any]?) {
        let info = userInfo ?? [:]
        switch ScriptMessage(rawValue: messageName) {
        case .hello:
            // A page that (re)loads isn't floating anything, whatever we remembered about it.
            registry.clearPiP(ifStill: page)
            page.dispatchMessageToScript(withName: "settings", userInfo: SettingsStore.load().scriptPayload)

        case .ack:
            if let id = info["id"] as? String { tracker.ack(id) }

        case .trace:
            let text = info.keys.sorted().map { "\($0)=\(info[$0] ?? "")" }.joined(separator: " ")
            log.notice("page: \(text, privacy: .public)")

        case .probeResult:
            if let id = info["id"] as? String { TabProbe.shared.receive(id: id, info: info) }

        case .videoCheck:
            break // kept for older scripts; the toolbar button is always enabled now

        case .pipState:
            registry.setPiP(info["active"] as? Bool ?? false, page: page)

        case .result:
            guard let raw = info["event"] as? String, let event = HUDEvent(rawValue: raw) else { return }
            SettingsStore.writeEvent(.init(event: event, detail: info["detail"] as? String, date: Date()))

        case .needsGesture:
            // Safari refused PiP because no click reached the page. The app presses our
            // toolbar button through Accessibility, which comes back as toolbarItemClicked.
            log.notice("PiP needs a user gesture; asking the app to press the toolbar button")
            // The click must go back to this page, which may be a background tab.
            GestureTarget.shared.set(page)
            Darwin.post(DarwinName.needsGesture)

        case nil:
            log.error("unknown message \(messageName, privacy: .public)")
        }
    }

    // MARK: Commands from the Floatr app

    override func messageReceivedFromContainingApp(withName messageName: String, userInfo: [String: Any]? = nil) {
        if messageName == Floatr.settingsChangedMessage {
            // Open pages otherwise keep their old settings until they reload.
            let payload = SettingsStore.load().scriptPayload
            allPages { pages in pages.forEach { $0.dispatchMessageToScript(withName: "settings", userInfo: payload) } }
            return
        }
        guard let command = PiPCommand(rawValue: messageName) else { return }
        log.notice("command from app: \(messageName, privacy: .public)")

        if command == .focusTab {
            focusPiPTab()
            return
        }
        deliver(command.rawValue, userInfo: [:], window: nil, probeTabs: true)
    }

    private func focusPiPTab() {
        guard let page = registry.pipPage else {
            SettingsStore.writeEvent(.init(event: .noVideo, detail: nil, date: Date()))
            return
        }
        page.getContainingTab { tab in
            tab.activate {
                // Like the "return" button on the PiP window: bring the video back inline.
                self.tracker.send("exit", to: page) {
                    self.registry.clearPiP(ifStill: page)
                    SettingsStore.writeEvent(.init(event: .noVideo, detail: nil, date: Date()))
                }
            }
        }
    }

    // MARK: Toolbar button (same behaviour as PiPifier, plus toggling off)

    override func toolbarItemClicked(in window: SFSafariWindow) {
        // A click the app made for a page that asked for one (possibly a background tab).
        if let page = GestureTarget.shared.take() {
            tracker.send(PiPCommand.toggle.rawValue, to: page, userInfo: ["viaToolbar": true]) {
                SettingsStore.writeEvent(.init(event: .unreachable, detail: nil, date: Date()))
            }
            return
        }
        // A real click: the tab the user is looking at, right away (waiting could lose the click).
        deliver(PiPCommand.toggle.rawValue, userInfo: ["viaToolbar": true], window: window, probeTabs: false)
    }

    /// Always enabled. It used to be disabled on pages without a detected video, but that state
    /// is lost whenever Safari restarts the extension, which left the button grayed out on pages
    /// that do have videos. A click on a page without video shows "No video in this tab".
    override func validateToolbarItem(in window: SFSafariWindow, validationHandler: @escaping (Bool, String) -> Void) {
        validationHandler(true, "")
    }

    // MARK: Context menu on videos

    override func contextMenuItemSelected(withCommand command: String, in page: SFSafariPage, userInfo: [String: Any]? = nil) {
        tracker.send(PiPCommand.toggle.rawValue, to: page, userInfo: ["viaToolbar": true]) {
            SettingsStore.writeEvent(.init(event: .unreachable, detail: nil, date: Date()))
        }
    }

    override func validateContextMenuItem(withCommand command: String, in page: SFSafariPage, userInfo: [String: Any]? = nil,
                                          validationHandler: @escaping (Bool, String?) -> Void) {
        let hasVideo = userInfo?["hasVideo"] as? Bool ?? false
        // First argument is "should hide".
        validationHandler(!hasVideo, registry.isPiP(page) ? exitTitle : nil)
    }

    // MARK: Routing

    /// Sends a command to the page that owns the floating video, or else to the front tab.
    /// If the floating page doesn't answer, it's forgotten and the front tab gets the command.
    /// If the front tab doesn't answer either, the HUD asks the user to reload it.
    /// With `probeTabs`, a front tab without a playing video hands the command to a tab that is
    /// playing audio (see `TabProbe.choose`).
    private func deliver(_ name: String, userInfo: [String: Any], window: SFSafariWindow?, probeTabs: Bool) {
        let send: (SFSafariPage?) -> Void = { page in
            guard let page else {
                SettingsStore.writeEvent(.init(event: .noVideo, detail: nil, date: Date()))
                return
            }
            self.tracker.send(name, to: page, userInfo: userInfo) {
                log.error("page didn't answer \(name, privacy: .public); it has no Floatr script")
                SettingsStore.writeEvent(.init(event: .unreachable, detail: nil, date: Date()))
            }
        }
        let toActivePage = {
            self.activePage(in: window) { front in
                guard probeTabs else { return send(front) }
                self.allPages { pages in
                    TabProbe.shared.choose(front: front, pages: pages) { pick in
                        if let pick, let front, !pick.isEqual(front) {
                            log.notice("front tab has nothing playing; sending \(name, privacy: .public) to the tab playing audio")
                        }
                        send(pick)
                    }
                }
            }
        }
        guard let pip = registry.pipPage else { return toActivePage() }
        tracker.send(name, to: pip, userInfo: userInfo) {
            log.info("floating page is gone; sending \(name, privacy: .public) to the front tab")
            self.registry.clearPiP(ifStill: pip)
            toActivePage()
        }
    }

    /// The visible page of every tab in every window, front window first.
    private func allPages(_ body: @escaping ([SFSafariPage]) -> Void) {
        SFSafariApplication.getAllWindows { windows in
            let group = DispatchGroup()
            let lock = NSLock()
            var found: [(Int, Int, SFSafariPage)] = []
            for (w, window) in windows.enumerated() {
                group.enter()
                window.getAllTabs { tabs in
                    for (t, tab) in tabs.enumerated() {
                        group.enter()
                        tab.getActivePage { page in
                            if let page { lock.lock(); found.append((w, t, page)); lock.unlock() }
                            group.leave()
                        }
                    }
                    group.leave()
                }
            }
            group.notify(queue: .global()) {
                body(found.sorted { ($0.0, $0.1) < ($1.0, $1.1) }.map(\.2))
            }
        }
    }

    private func activePage(in window: SFSafariWindow?, _ body: @escaping (SFSafariPage?) -> Void) {
        let fromWindow: (SFSafariWindow?) -> Void = { window in
            guard let window else { return body(nil) }
            window.getActiveTab { tab in
                guard let tab else { return body(nil) }
                tab.getActivePage { body($0) }
            }
        }
        if let window { fromWindow(window) } else { SFSafariApplication.getActiveWindow(completionHandler: fromWindow) }
    }

    /// The extension runs with Safari's language, so it follows the language chosen in Floatr instead.
    private var exitTitle: String {
        SettingsStore.load().language == .pt ? "Sair do Picture in Picture" : "Exit Picture in Picture"
    }
}
