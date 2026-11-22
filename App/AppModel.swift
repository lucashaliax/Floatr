import AppKit
import Combine
import ServiceManagement

/// App state shared by the settings window, the optional menu bar item and the hotkey router.
@MainActor
final class AppModel: ObservableObject {
    static let shared = AppModel()

    @Published var settings: FloatrSettings {
        didSet {
            guard settings != oldValue else { return }
            SettingsStore.save(settings)
            if settings.shortcuts != oldValue.shortcuts
                || settings.hotkeysWhenSafariInBackground != oldValue.hotkeysWhenSafariInBackground {
                applyHotkeys()
            }
            if settings.showMenuBarIcon != oldValue.showMenuBarIcon { MenuBarController.shared.update() }
        }
    }

    @Published var extensionEnabled: Bool?
    @Published var accessibilityTrusted = AccessibilityPresser.isTrusted
    @Published var launchAtLogin = SMAppService.mainApp.status == .enabled
    /// Shortcuts another app already registered.
    @Published var takenShortcuts: Set<PiPCommand> = []
    /// Title of the video that is floating, if any (from the extension's events).
    @Published var floatingTitle: String?
    /// Pane shown in the settings window (set when opening it from a notification or menu).
    @Published var selectedPane: SettingsPane? = .shortcuts

    private var lastGestureFallback = Date.distantPast

    private init() {
        settings = SettingsStore.load()
    }

    // MARK: Hotkeys

    func applyHotkeys() {
        let active = settings.hotkeysWhenSafariInBackground || SafariBridge.isSafariFrontmost
        takenShortcuts = active ? HotkeyCenter.shared.register(settings.shortcuts) : []
        if !active { HotkeyCenter.shared.unregisterAll() }
    }

    /// Commands that share a shortcut with another Floatr command.
    var duplicateShortcuts: Set<PiPCommand> {
        var seen: [Shortcut: PiPCommand] = [:]
        var dupes = Set<PiPCommand>()
        for cmd in PiPCommand.allCases {
            guard let sc = settings.shortcuts[cmd] else { continue }
            if let other = seen[sc] { dupes.insert(cmd); dupes.insert(other) } else { seen[sc] = cmd }
        }
        return dupes
    }

    // MARK: Routing

    func perform(_ command: PiPCommand) {
        guard SafariBridge.safariApp != nil else {
            showHUD(.safariClosed)
            return
        }
        if command == .toggle && settings.alwaysPressToolbar {
            pressToolbar()
            return
        }
        SafariBridge.send(command) { [weak self] error in
            guard let self else { return }
            if error != nil {
                self.refreshExtensionState()
                self.showHUD(.extensionOff)
                return
            }
            if command == .focusTab { SafariBridge.activateSafari() }
        }
    }

    /// The page refused PiP without a user gesture: click the toolbar button instead.
    func handleNeedsGesture() {
        guard settings.toolbarFallback else {
            showHUD(.blocked)
            return
        }
        // Guard against loops if the toolbar click is refused as well.
        guard Date().timeIntervalSince(lastGestureFallback) > 1.5 else { return }
        lastGestureFallback = Date()
        pressToolbar()
    }

    private func pressToolbar() {
        switch AccessibilityPresser.pressToolbarButton() {
        case .pressed: break
        case .safariClosed: showHUD(.safariClosed)
        case .buttonNotFound: showHUD(.toolbarMissing)
        case .notTrusted:
            showHUD(.needsAccessibility)
            AccessibilityPresser.requestTrust()
        }
    }

    // MARK: Events from the extension

    func handleExtensionEvent() {
        guard let e = SettingsStore.readEvent(), Date().timeIntervalSince(e.date) < 3 else { return }
        switch e.event {
        case .pipOn: floatingTitle = e.detail
        case .pipOff: floatingTitle = nil
        default: break
        }
        MenuBarController.shared.update()
        showHUD(e.event, detail: e.event == .pipOn ? nil : e.detail)
    }

    func showHUD(_ event: HUDEvent, detail: String? = nil) {
        guard settings.showHUD else { return }
        HUD.shared.show(event, detail: detail)
    }

    // MARK: System state

    func refreshExtensionState() {
        SafariBridge.extensionEnabled { [weak self] enabled in self?.extensionEnabled = enabled }
        accessibilityTrusted = AccessibilityPresser.isTrusted
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    /// The language the running process was started with; a different choice needs a relaunch.
    let launchedLanguage = SettingsStore.load().language

    func relaunch() {
        let path = Bundle.main.bundlePath
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/bin/sh")
        // Wait for this process to exit, then open the app again.
        task.arguments = ["-c", "sleep 0.5; /usr/bin/open \"$0\"", path]
        try? task.run()
        NSApp.terminate(nil)
    }

    func setLaunchAtLogin(_ on: Bool) {
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSLog("Floatr: launch at login failed: \(error)")
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
