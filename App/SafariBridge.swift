import AppKit
import SafariServices

/// Talks to Safari and to the Floatr extension from the app.
enum SafariBridge {
    static let safariBundleID = "com.apple.Safari"

    static var safariApp: NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: safariBundleID).first
    }

    static var isSafariFrontmost: Bool {
        NSWorkspace.shared.frontmostApplication?.bundleIdentifier == safariBundleID
    }

    /// Sends a command to the extension, which forwards it to the right page.
    static func send(_ command: PiPCommand, completion: ((Error?) -> Void)? = nil) {
        SFSafariApplication.dispatchMessage(withName: command.rawValue,
                                            toExtensionWithIdentifier: Floatr.extensionBundleID,
                                            userInfo: nil) { error in
            DispatchQueue.main.async { completion?(error) }
        }
    }

    /// nil when Safari can't tell (for example the extension was never registered).
    static func extensionEnabled(_ completion: @escaping (Bool?) -> Void) {
        SFSafariExtensionManager.getStateOfSafariExtension(withIdentifier: Floatr.extensionBundleID) { state, error in
            DispatchQueue.main.async { completion(error == nil ? state?.isEnabled : nil) }
        }
    }

    static func openExtensionSettings() {
        SFSafariApplication.showPreferencesForExtension(withIdentifier: Floatr.extensionBundleID) { _ in }
    }

    static func activateSafari() {
        safariApp?.activate()
    }
}
