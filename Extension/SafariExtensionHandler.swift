import SafariServices
import os

private let log = Logger(subsystem: Floatr.extensionBundleID, category: "handler")

/// Bridges three sources of commands to the page's content script:
/// the toolbar button, the video context menu, and the Floatr app (global shortcuts).
final class SafariExtensionHandler: SFSafariExtensionHandler {
    private let registry = PageRegistry.shared

    // MARK: Messages from content.js

    override func messageReceived(withName messageName: String, from page: SFSafariPage, userInfo: [String: Any]?) {
        let info = userInfo ?? [:]
        switch ScriptMessage(rawValue: messageName) {
        case .hello:
            page.dispatchMessageToScript(withName: "settings", userInfo: SettingsStore.load().scriptPayload)

        case .videoCheck:
            registry.setHasVideo(info["found"] as? Bool ?? false, for: page)
            SFSafariApplication.setToolbarItemsNeedUpdate()

        case .pipState:
            registry.setPiP(info["active"] as? Bool ?? false, page: page)
            SFSafariApplication.setToolbarItemsNeedUpdate()

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

        // Controls (and toggling off) go to the page that owns the floating video,
        // even if the user moved to another tab. Otherwise use the front tab.
        if let pip = registry.pipPage {
            pip.dispatchMessageToScript(withName: command.rawValue, userInfo: [:])
            return
        }
        withActivePage { page in
            guard let page else {
                SettingsStore.writeEvent(.init(event: .noVideo, detail: nil, date: Date()))
                return
            }
            page.dispatchMessageToScript(withName: command.rawValue, userInfo: [:])
        }
    }

    private func focusPiPTab() {
        guard let page = registry.pipPage else {
            SettingsStore.writeEvent(.init(event: .noVideo, detail: nil, date: Date()))
            return
        }
        page.getContainingTab { tab in
            tab.activate {
                // Like the "return" button on the PiP window: bring the video back inline.
                page.dispatchMessageToScript(withName: "exit", userInfo: [:])
            }
        }
    }

    // MARK: Toolbar button (same behaviour as PiPifier, plus toggling off)

    override func toolbarItemClicked(in window: SFSafariWindow) {
        if let pip = registry.pipPage {
            pip.dispatchMessageToScript(withName: PiPCommand.toggle.rawValue, userInfo: ["viaToolbar": true])
            return
        }
        window.getActiveTab { tab in
            tab?.getActivePage { page in
                page?.dispatchMessageToScript(withName: PiPCommand.toggle.rawValue, userInfo: ["viaToolbar": true])
            }
        }
    }

    override func validateToolbarItem(in window: SFSafariWindow, validationHandler: @escaping (Bool, String) -> Void) {
        if registry.pipPage != nil {
            validationHandler(true, "")
            return
        }
        window.getActiveTab { tab in
            guard let tab else { return validationHandler(false, "") }
            tab.getActivePage { page in
                validationHandler(page.map(self.registry.hasVideo) ?? false, "")
            }
        }
    }

    // MARK: Context menu on videos

    override func contextMenuItemSelected(withCommand command: String, in page: SFSafariPage, userInfo: [String: Any]? = nil) {
        page.dispatchMessageToScript(withName: PiPCommand.toggle.rawValue, userInfo: ["viaToolbar": true])
    }

    override func validateContextMenuItem(withCommand command: String, in page: SFSafariPage, userInfo: [String: Any]? = nil,
                                          validationHandler: @escaping (Bool, String?) -> Void) {
        let hasVideo = userInfo?["hasVideo"] as? Bool ?? false
        // First argument is "should hide".
        validationHandler(!hasVideo, registry.isPiP(page) ? exitTitle : nil)
    }

    // MARK: Helpers

    /// The extension runs with Safari's language, so it follows the language chosen in Floatr instead.
    private var exitTitle: String {
        SettingsStore.load().language == .pt ? "Sair do Picture in Picture" : "Exit Picture in Picture"
    }

    private func withActivePage(_ body: @escaping (SFSafariPage?) -> Void) {
        SFSafariApplication.getActiveWindow { window in
            guard let window else { return body(nil) }
            window.getActiveTab { tab in
                guard let tab else { return body(nil) }
                tab.getActivePage { body($0) }
            }
        }
    }
}
