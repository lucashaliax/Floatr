import AppKit
import SwiftUI
import UserNotifications

@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, UNUserNotificationCenterDelegate {
    private var settingsWindow: NSWindow?
    private let model = AppModel.shared

    static func main() {
        applyInterfaceLanguage()
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory) // invisible: no Dock icon
        app.run()
    }

    /// English unless the user chose Portuguese. The bundle reads its language very early,
    /// so when the stored preference is missing or different, save it and restart in place.
    private static func applyInterfaceLanguage() {
        let wanted = [SettingsStore.load().language.localeCode]
        let key = "AppleLanguages" as CFString
        let current = CFPreferencesCopyAppValue(key, kCFPreferencesCurrentApplication) as? [String]
        guard current != wanted else { return }
        CFPreferencesSetAppValue(key, wanted as CFArray, kCFPreferencesCurrentApplication)
        CFPreferencesAppSynchronize(kCFPreferencesCurrentApplication)
        if let exe = Bundle.main.executablePath {
            execv(exe, CommandLine.unsafeArgv) // only returns on failure; then continue in the current language
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        HotkeyCenter.shared.onHotkey = { [weak self] cmd in self?.model.perform(cmd) }
        model.applyHotkeys()
        observeDarwin(DarwinName.event)
        observeDarwin(DarwinName.needsGesture)
        observeFrontmostApp()
        startUpdateChecks()
        MenuBarController.shared.update()
        model.refreshExtensionState()

        // `open -a Floatr --args -FloatrPreviewHUD pipOff` shows one HUD (used to check its look).
        if let raw = UserDefaults.standard.string(forKey: "FloatrPreviewHUD"), let event = HUDEvent(rawValue: raw) {
            HUD.shared.show(event, detail: "1,5×")
            return
        }
        // `open -a Floatr --args -FloatrRunUpdate YES` checks and installs the latest release
        // without asking (used to test updates).
        if UserDefaults.standard.bool(forKey: "FloatrRunUpdate") {
            Task {
                if let release = await Updater.shared.check() {
                    NSLog("Floatr: installing \(release.version)")
                    Updater.shared.install(release)
                } else {
                    NSLog("Floatr: no update (\(String(describing: Updater.shared.state)))")
                }
            }
            return
        }
        // `open -a Floatr --args -FloatrRunCommand toggle` runs one command, as if its shortcut
        // was pressed (used to test Floatr without a keyboard).
        if let raw = UserDefaults.standard.string(forKey: "FloatrRunCommand"), let cmd = PiPCommand(rawValue: raw) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { self.model.perform(cmd) }
            return
        }

        // First run, or the extension still needs to be turned on: show the window.
        // Launched at login with everything set up: stay invisible.
        SafariBridge.extensionEnabled { [weak self] enabled in
            guard let self else { return }
            if !self.model.settings.onboardingDone || enabled == false { self.showSettings() }
        }
    }

    /// Opening Floatr again (Spotlight, Launchpad, Finder) brings up the settings.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showSettings()
        return true
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDidBecomeActive(_ notification: Notification) {
        model.refreshExtensionState()
    }

    // MARK: Settings window

    func showSettings(pane: SettingsPane? = nil) {
        if let pane { model.selectedPane = pane }
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
                                  styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                                  backing: .buffered, defer: false)
            window.title = "Floatr"
            window.titlebarAppearsTransparent = true
            window.toolbarStyle = .unified
            window.isReleasedWhenClosed = false
            window.contentMinSize = NSSize(width: 680, height: 460)
            window.contentViewController = NSHostingController(rootView: SettingsView().environmentObject(model))
            window.setFrameAutosaveName("FloatrSettings")
            if !window.setFrameUsingName("FloatrSettings") { window.center() }
            settingsWindow = window
        }
        NSApp.activate()
        settingsWindow?.makeKeyAndOrderFront(nil)
        model.refreshExtensionState()
    }

    // MARK: Updates

    private var updateTimer: Timer?

    /// Checks GitHub once a day (the timer only looks at the date every 6 hours).
    private func startUpdateChecks() {
        UNUserNotificationCenter.current().delegate = self
        let tick = { [weak self] in
            guard let self, self.model.settings.checkForUpdates else { return }
            Updater.shared.checkInBackgroundIfDue()
        }
        tick()
        updateTimer = Timer.scheduledTimer(withTimeInterval: 6 * 3600, repeats: true) { _ in
            MainActor.assumeIsolated { tick() }
        }
        updateTimer?.tolerance = 600
    }

    /// Clicking the "new version" notification opens About, where the update can be installed.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        DispatchQueue.main.async {
            MainActor.assumeIsolated { self.showSettings(pane: .about) }
            completionHandler()
        }
    }

    // MARK: Notifications

    private func observeDarwin(_ name: String) {
        let observer = Unmanaged.passUnretained(self).toOpaque()
        CFNotificationCenterAddObserver(CFNotificationCenterGetDarwinNotifyCenter(), observer, { _, observer, name, _, _ in
            guard let observer, let name = name?.rawValue as String? else { return }
            let delegate = Unmanaged<AppDelegate>.fromOpaque(observer).takeUnretainedValue()
            DispatchQueue.main.async {
                MainActor.assumeIsolated { delegate.handleDarwin(name) }
            }
        }, name as CFString, nil, .deliverImmediately)
    }

    private func handleDarwin(_ name: String) {
        switch name {
        case DarwinName.event: model.handleExtensionEvent()
        case DarwinName.needsGesture: model.handleNeedsGesture()
        default: break
        }
    }

    /// With "shortcuts only while Safari is in front", hotkeys are registered on the fly
    /// so they never steal keys from other apps.
    private func observeFrontmostApp() {
        NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                                          object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.settings.hotkeysWhenSafariInBackground else { return }
                if !HotkeyCenter.shared.isSuspended { self.model.applyHotkeys() }
            }
        }
    }
}
