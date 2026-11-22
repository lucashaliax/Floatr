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
            log.info("PiP needs a user gesture; asking the app to press the toolbar button")
            Darwin.post(DarwinName.needsGesture)

        case nil:
            log.error("unknown message \(messageName, privacy: .public)")
        }
    }

    // MARK: Commands from the Floatr app

    override func messageReceivedFromContainingApp(withName messageName: String, userInfo: [String: Any]? = nil) {
        guard let command = PiPCommand(rawValue: messageName) else { return }
        log.info("command from app: \(messageName, privacy: .public)")

        if command == .focusTab {
            focusPiPTab()
            return
        }
        deliver(command.rawValue, userInfo: [:], window: nil)
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
        deliver(PiPCommand.toggle.rawValue, userInfo: ["viaToolbar": true], window: window)
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
    private func deliver(_ name: String, userInfo: [String: Any], window: SFSafariWindow?) {
        let toActivePage = {
            self.activePage(in: window) { page in
                guard let page else {
                    SettingsStore.writeEvent(.init(event: .noVideo, detail: nil, date: Date()))
                    return
                }
                self.tracker.send(name, to: page, userInfo: userInfo) {
                    log.error("page didn't answer \(name, privacy: .public); it has no Floatr script")
                    SettingsStore.writeEvent(.init(event: .unreachable, detail: nil, date: Date()))
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
